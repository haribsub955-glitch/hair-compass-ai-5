"""App Attest — is this request coming from our real app, on a real Apple device?

Everything else authenticates a *person*: a session token proves which principal is calling, and a
StoreKit receipt proves someone paid. Neither says the caller is the app. A script with a valid
token and a valid receipt is indistinguishable from the iPhone that obtained them, and the thing it
gets access to is a provider API key the server holds and pays for.

That matters more than usual here. The abuse is not "read someone's data" — it is "use my key as a
free LLM endpoint", which costs money per request and looks exactly like legitimate traffic.

**How it works, briefly.** The app asks the Secure Enclave for a key it cannot export, and Apple
returns an *attestation* certifying that key came from a genuine device running this bundle id.
The server verifies the certificate chain to Apple's App Attest root and remembers the public key.
Afterwards each request carries an *assertion*: a signature over the request, made with that key,
plus a counter that only increases.

**What each half is worth.** The attestation is the strong claim and is checked once. The assertion
is the per-request claim, and it is cheap — one ECDSA verify. The counter is what stops a captured
assertion being replayed: a replay presents a counter that is not greater than the last one seen.

**Deliberately advisory by default.** Attestation fails for reasons that are not attacks —
jailbroken devices, a simulator, an enterprise build, Apple's service being down, a device with no
Secure Enclave. Turning that into a hard failure on day one means a portion of legitimate users
simply cannot use the app, and you find out from reviews. So the default records and reports;
`require_attestation` makes it binding when the data says it is safe to.
"""

from __future__ import annotations

import base64
import hashlib
import logging
from dataclasses import dataclass
from datetime import UTC, datetime

from agent_core.contracts import ErrorCode
from agent_server.core.errors import PlatformError

log = logging.getLogger("agent_server.attest")

#: Apple's OID for the nonce extension inside an attestation certificate.
APPLE_NONCE_OID = "1.2.840.113635.100.8.2"


class AttestationFailed(PlatformError):
    """The attestation or assertion did not check out. Never says which check failed — a caller
    who can tell "bad nonce" from "bad chain" has a map of the verifier."""

    code = ErrorCode.UNAUTHENTICATED
    status = 401
    message = "This device could not be verified."


@dataclass(frozen=True, slots=True)
class AttestedKey:
    """What a successful attestation establishes, and what has to be stored to use it later."""

    key_id: str
    public_key_der: bytes
    counter: int
    attested_at: datetime

    @property
    def public_key_b64(self) -> str:
        return base64.b64encode(self.public_key_der).decode()


def _sha256(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def _require_ca(cert) -> None:
    """An issuer must be a CA that is allowed to sign certificates.

    Without this, any leaf certificate can sign another and be spliced into a path — the bypass
    above worked partly because nothing asked whether the "issuer" was entitled to issue.
    """
    from cryptography import x509

    try:
        basic = cert.extensions.get_extension_for_class(x509.BasicConstraints).value
        usage = cert.extensions.get_extension_for_class(x509.KeyUsage).value
    except x509.ExtensionNotFound:
        raise AttestationFailed("issuer is not marked as a certificate authority") from None
    if not basic.ca or not usage.key_cert_sign:
        raise AttestationFailed("issuer is not permitted to sign certificates")


class AppAttestVerifier:
    """Verifies Apple App Attest attestations and assertions.

    Apple's roots are passed in rather than bundled, for the same reason as StoreKit's: pinning a
    certificate inside the image means a rotation ships as a release.
    """

    def __init__(self, *, bundle_id: str, team_id: str, root_certificates: list[bytes]) -> None:
        if not bundle_id or not team_id:
            raise RuntimeError("App Attest needs the bundle id and the team id")
        if not root_certificates:
            # A verifier with no chain to validate against is worse than none: it looks like a
            # control and accepts anything.
            raise RuntimeError("App Attest root certificates are required")
        self._bundle_id = bundle_id
        self._team_id = team_id
        self._roots = root_certificates
        #: `app_id` is what the attestation actually commits to — the team id and bundle id
        #: together. Checking only the bundle id would accept an attestation from another team's
        #: app that happened to choose the same name.
        self._app_id_hash = _sha256(f"{team_id}.{bundle_id}".encode())

    # --- attestation: once per install ----------------------------------------------------

    def verify_attestation(
        self, *, attestation: bytes, key_id: str, challenge: bytes
    ) -> AttestedKey:
        """Check an attestation object and return the key it certifies.

        The order of checks is cheapest-first and each one is a separate reason to reject:

        1. the CBOR decodes and names the format Apple uses
        2. the certificate chain reaches one of Apple's roots
        3. the nonce inside the leaf equals SHA256(authenticator data ‖ SHA256(challenge)) — this
           is what binds the attestation to *our* challenge rather than a replayed one
        4. the app id hash matches this team and bundle
        5. the key id equals SHA256 of the public key, so the client cannot name someone else's key
        6. the counter starts at zero, as Apple specifies for a fresh attestation
        """
        import cbor2
        from cryptography import x509
        from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

        try:
            obj = cbor2.loads(attestation)
        except Exception:
            raise AttestationFailed("undecodable attestation") from None

        if obj.get("fmt") != "apple-appattest":
            raise AttestationFailed("unexpected attestation format")

        statement = obj.get("attStmt") or {}
        auth_data: bytes = obj.get("authData") or b""
        chain = statement.get("x5c") or []
        if not chain or not auth_data:
            raise AttestationFailed("incomplete attestation")

        certs = [x509.load_der_x509_certificate(der) for der in chain]
        self._check_chain(certs)

        # 3. the nonce binds this attestation to the challenge WE issued.
        expected_nonce = _sha256(auth_data + _sha256(challenge))
        if self._nonce_of(certs[0]) != expected_nonce:
            raise AttestationFailed("nonce mismatch")

        # 4. authenticator data: 32 bytes rpIdHash, 1 byte flags, 4 bytes counter, then the
        #    attested credential data.
        if auth_data[:32] != self._app_id_hash:
            raise AttestationFailed("app id mismatch")
        counter = int.from_bytes(auth_data[33:37], "big")
        if counter != 0:
            # Apple specifies zero for a fresh attestation. A non-zero counter means this is not
            # the first use of the key, which is not what an attestation is.
            raise AttestationFailed("attestation counter is not zero")

        public_key = certs[0].public_key()
        der = public_key.public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)

        # 5. the key id is Apple's SHA256 over the raw public key point, and the CLIENT sends it.
        #    Without this check a client could attest one key and then assert with another.
        raw = public_key.public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
        if base64.b64decode(key_id) != _sha256(raw):
            raise AttestationFailed("key id does not match the attested key")

        return AttestedKey(
            key_id=key_id, public_key_der=der, counter=0, attested_at=datetime.now(UTC)
        )

    def _check_chain(self, certs: list) -> None:
        """Leaf → intermediate → one of Apple's roots, walked STRICTLY in order.

        **The previous version was fully bypassable and a review proved it by running the attack.**
        It searched the whole client-supplied list for an issuer and returned success as soon as
        *any* certificate reached a root — so appending the genuine Apple intermediate (a public
        artefact present in every real attestation) behind a forged leaf and a self-signed CA made
        it accept. The leaf verified against the attacker's CA, the attacker's CA verified against
        itself, and then the real intermediate verified against the real root and returned. With a
        forged leaf the attacker also controls the nonce, the public key and `authData`, so every
        remaining check passed trivially and the verifier collapsed to nothing.

        The fix is that a chain is an ORDERED path, not a bag of certificates. `certs[i]` must be
        issued by `certs[i+1]`, the last one must be issued by a trusted root, and every issuer
        must actually be a CA.
        """
        from cryptography import x509
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric import ec

        if not certs or len(certs) > 4:
            # Apple sends leaf + intermediate. A long list is someone padding a path.
            raise AttestationFailed("unexpected chain length")

        roots = [x509.load_der_x509_certificate(der) for der in self._roots]
        now = datetime.now(UTC)
        for cert in certs:
            if not (cert.not_valid_before_utc <= now <= cert.not_valid_after_utc):
                raise AttestationFailed("certificate outside its validity window")

        # Each link, in order. `certs[-1]` must be issued by a ROOT — never by another member of
        # the client's own list, which is what allowed a self-signed CA to be spliced in.
        for index, child in enumerate(certs):
            issuers = [certs[index + 1]] if index + 1 < len(certs) else roots
            issuer = next((c for c in issuers if c.subject == child.issuer), None)
            if issuer is None:
                raise AttestationFailed("chain does not reach a trusted root")
            if index + 1 < len(certs) or issuer in roots:
                _require_ca(issuer)
            try:
                issuer.public_key().verify(
                    child.signature,
                    child.tbs_certificate_bytes,
                    ec.ECDSA(child.signature_hash_algorithm),
                )
            except InvalidSignature:
                raise AttestationFailed("broken signature in the chain") from None
            except Exception:
                # A non-EC issuer key, an unsupported algorithm — one answer to the caller, and
                # never an unhandled 500, which would itself map the verifier.
                raise AttestationFailed("unverifiable signature in the chain") from None

    @staticmethod
    def _nonce_of(leaf) -> bytes:
        """The nonce Apple puts in a private certificate extension.

        Parsed by locating the OID's DER payload rather than fully decoding the extension: the
        value is a fixed-shape SEQUENCE containing one 32-byte OCTET STRING, and the last 32 bytes
        of it are the digest.
        """
        from cryptography import x509

        try:
            extension = leaf.extensions.get_extension_for_oid(
                x509.ObjectIdentifier(APPLE_NONCE_OID)
            )
        except x509.ExtensionNotFound:
            raise AttestationFailed("no nonce extension") from None
        raw = extension.value.value
        if len(raw) < 32:
            raise AttestationFailed("malformed nonce extension")
        return raw[-32:]

    # --- assertion: once per request ------------------------------------------------------

    def verify_assertion(self, *, assertion: bytes, key: AttestedKey, client_data: bytes) -> int:
        """Check a per-request assertion and return the new counter.

        The counter is the whole anti-replay story. A captured assertion re-sent later carries a
        counter that is no longer greater than the last one recorded, so it is refused — which is
        why the caller MUST persist the returned value. Verifying the signature and forgetting the
        counter leaves every past request replayable forever.
        """
        import cbor2
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import Prehashed
        from cryptography.hazmat.primitives.hashes import SHA256
        from cryptography.hazmat.primitives.serialization import load_der_public_key

        try:
            obj = cbor2.loads(assertion)
        except Exception:
            raise AttestationFailed("undecodable assertion") from None

        signature = obj.get("signature")
        auth_data = obj.get("authenticatorData")
        if not signature or not auth_data:
            raise AttestationFailed("incomplete assertion")

        if auth_data[:32] != self._app_id_hash:
            raise AttestationFailed("app id mismatch")

        counter = int.from_bytes(auth_data[33:37], "big")
        if counter <= key.counter:
            # Strictly greater. Equal is a replay of the most recent request, which is the easiest
            # capture to obtain and the one an attacker would try first.
            raise AttestationFailed("counter did not advance")

        digest = _sha256(auth_data + _sha256(client_data))
        try:
            load_der_public_key(key.public_key_der).verify(
                signature, digest, ec.ECDSA(Prehashed(SHA256()))
            )
        except InvalidSignature:
            raise AttestationFailed("bad assertion signature") from None
        return counter


class AttestationPolicy:
    """Whether attestation is advisory or binding, in one place.

    Advisory by default and that is a product decision, not laziness: attestation fails for
    jailbroken devices, simulators, enterprise builds, and Apple outages — none of which are
    attacks. Making it binding on day one means some legitimate users simply cannot use the app and
    you learn about it from reviews. Record first, enforce once the data says what the failure rate
    actually is.
    """

    def __init__(self, *, verifier: AppAttestVerifier | None, required: bool = False) -> None:
        self._verifier = verifier
        self.required = required

    @property
    def available(self) -> bool:
        return self._verifier is not None

    def enforce(self, failure: AttestationFailed) -> None:
        """Raise if attestation is binding here; otherwise log and continue."""
        if self.required:
            raise failure
        log.warning("attestation failed but is advisory: %s", failure)
