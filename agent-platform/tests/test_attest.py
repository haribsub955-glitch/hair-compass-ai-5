"""App Attest, tested against a synthetic Apple.

Apple will not issue attestations to a test suite, so the tests build their own root, intermediate
and leaf and sign a real attestation object with them. That is the only way to prove the verifier
ACCEPTS a well-formed attestation — and a verifier only ever tested with junk is one that might
reject everything, which fails closed and looks fine until launch day.

Every rejection test then takes that valid object and breaks exactly one thing.
"""

from __future__ import annotations

import base64
import hashlib
from datetime import UTC, datetime, timedelta

import cbor2
import pytest
from cryptography import x509
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import Prehashed
from cryptography.hazmat.primitives.hashes import SHA256
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from cryptography.x509.oid import NameOID

from agent_server.attest import (
    APPLE_NONCE_OID,
    AppAttestVerifier,
    AttestationFailed,
    AttestationPolicy,
    AttestedKey,
)

BUNDLE_ID = "harib.Hair-Compass-AI-5"
TEAM_ID = "ABCDE12345"
APP_ID_HASH = hashlib.sha256(f"{TEAM_ID}.{BUNDLE_ID}".encode()).digest()
CHALLENGE = b"a-challenge-the-server-issued"


def _sha256(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def _cert(
    subject: str,
    key,
    issuer_name=None,
    issuer_key=None,
    *,
    nonce: bytes | None = None,
    ca: bool = False,
):
    """One certificate, optionally a CA and optionally carrying Apple's nonce extension.

    `ca` matters: the verifier now refuses an issuer that is not marked as a certificate authority
    with `keyCertSign`. The original fixture built a "root" with neither, which is precisely the
    laxness that let a leaf certificate act as an issuer.
    """
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, subject)])
    now = datetime.now(UTC)
    builder = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(issuer_name or name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(days=1))
        .not_valid_after(now + timedelta(days=30))
    )
    if ca:
        builder = builder.add_extension(
            x509.BasicConstraints(ca=True, path_length=None), critical=True
        ).add_extension(
            x509.KeyUsage(
                digital_signature=False,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=True,
                crl_sign=True,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
    if nonce is not None:
        # Apple wraps the digest in a small SEQUENCE; the verifier reads the trailing 32 bytes, so
        # any prefix that ends with the digest reproduces the real shape closely enough.
        builder = builder.add_extension(
            x509.UnrecognizedExtension(x509.ObjectIdentifier(APPLE_NONCE_OID), b"\x30\x22" + nonce),
            critical=False,
        )
    return builder.sign(issuer_key or key, SHA256())


def _auth_data(*, app_id_hash: bytes = APP_ID_HASH, counter: int = 0) -> bytes:
    return app_id_hash + b"\x40" + counter.to_bytes(4, "big") + b"\x00" * 16


class Apple:
    """A stand-in certificate authority, so a *valid* attestation can be built."""

    def __init__(self) -> None:
        self.root_key = ec.generate_private_key(ec.SECP256R1())
        self.root = _cert("Fake Apple Root", self.root_key, ca=True)
        self.leaf_key = ec.generate_private_key(ec.SECP256R1())

    def attestation(self, *, challenge: bytes = CHALLENGE, **auth_kw) -> tuple[bytes, str]:
        auth_data = _auth_data(**auth_kw)
        nonce = _sha256(auth_data + _sha256(challenge))
        leaf = _cert(
            "attest-leaf",
            self.leaf_key,
            issuer_name=self.root.subject,
            issuer_key=self.root_key,
            nonce=nonce,
        )
        raw = self.leaf_key.public_key().public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
        key_id = base64.b64encode(_sha256(raw)).decode()
        obj = cbor2.dumps(
            {
                "fmt": "apple-appattest",
                "attStmt": {"x5c": [leaf.public_bytes(Encoding.DER)]},
                "authData": auth_data,
            }
        )
        return obj, key_id

    def verifier(self) -> AppAttestVerifier:
        return AppAttestVerifier(
            bundle_id=BUNDLE_ID,
            team_id=TEAM_ID,
            root_certificates=[self.root.public_bytes(Encoding.DER)],
        )


@pytest.fixture
def apple() -> Apple:
    return Apple()


# --------------------------------------------------------------------------------------------
# Attestation
# --------------------------------------------------------------------------------------------


def test_a_well_formed_attestation_is_accepted(apple) -> None:
    """The test that stops the verifier from being one that rejects everything."""
    attestation, key_id = apple.attestation()
    key = apple.verifier().verify_attestation(
        attestation=attestation, key_id=key_id, challenge=CHALLENGE
    )
    assert key.key_id == key_id
    assert key.counter == 0
    assert key.public_key_der


def test_an_attestation_for_a_different_challenge_is_refused(apple) -> None:
    """The replay case. Without the nonce check, one captured attestation works forever."""
    attestation, key_id = apple.attestation(challenge=b"someone-elses-challenge")
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_attestation(
            attestation=attestation, key_id=key_id, challenge=CHALLENGE
        )


def test_a_chain_that_does_not_reach_our_root_is_refused(apple) -> None:
    """Anyone can generate a certificate. The chain is the entire claim."""
    attestation, key_id = apple.attestation()
    stranger = Apple()  # valid-looking, signed by a root we do not trust
    with pytest.raises(AttestationFailed):
        stranger.verifier().verify_attestation(
            attestation=attestation, key_id=key_id, challenge=CHALLENGE
        )


def test_an_attestation_for_another_app_is_refused(apple) -> None:
    """A genuine Apple attestation from a DIFFERENT app is still a genuine Apple attestation."""
    attestation, key_id = apple.attestation(app_id_hash=_sha256(b"OTHER.com.someone.else"))
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_attestation(
            attestation=attestation, key_id=key_id, challenge=CHALLENGE
        )


def test_a_key_id_naming_a_different_key_is_refused(apple) -> None:
    """Otherwise a client attests one key and then asserts with another."""
    attestation, _ = apple.attestation()
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_attestation(
            attestation=attestation,
            key_id=base64.b64encode(b"x" * 32).decode(),
            challenge=CHALLENGE,
        )


def test_a_non_zero_counter_in_an_attestation_is_refused(apple) -> None:
    attestation, key_id = apple.attestation(counter=7)
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_attestation(
            attestation=attestation, key_id=key_id, challenge=CHALLENGE
        )


@pytest.mark.parametrize("junk", [b"", b"not-cbor", cbor2.dumps({"fmt": "webauthn"})])
def test_junk_is_refused_rather_than_crashing(apple, junk) -> None:
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_attestation(attestation=junk, key_id="x", challenge=CHALLENGE)


def test_a_verifier_without_apple_roots_refuses_to_exist() -> None:
    """A verifier with no chain to validate against looks like a control and accepts anything."""
    with pytest.raises(RuntimeError, match="root certificates"):
        AppAttestVerifier(bundle_id=BUNDLE_ID, team_id=TEAM_ID, root_certificates=[])


# --------------------------------------------------------------------------------------------
# Assertion — the per-request half
# --------------------------------------------------------------------------------------------


def _assertion(apple: Apple, *, counter: int, client_data: bytes) -> bytes:
    auth_data = _auth_data(counter=counter)
    digest = _sha256(auth_data + _sha256(client_data))
    # Prehashed, because the verifier checks the signature over the DIGEST rather than re-hashing.
    signature = apple.leaf_key.sign(digest, ec.ECDSA(Prehashed(SHA256())))
    return cbor2.dumps({"signature": signature, "authenticatorData": auth_data})


def _attested(apple: Apple) -> AttestedKey:
    attestation, key_id = apple.attestation()
    return apple.verifier().verify_attestation(
        attestation=attestation, key_id=key_id, challenge=CHALLENGE
    )


def test_a_valid_assertion_advances_the_counter(apple) -> None:
    key = _attested(apple)
    body = b'{"user_text":"is my shedding normal?"}'
    assert (
        apple.verifier().verify_assertion(
            assertion=_assertion(apple, counter=1, client_data=body), key=key, client_data=body
        )
        == 1
    )


def test_a_replayed_assertion_is_refused(apple) -> None:
    """The counter is the whole anti-replay story: a captured assertion re-sent later carries a
    counter that is no longer greater than the last one recorded."""
    key = _attested(apple)
    body = b"request"
    verifier = apple.verifier()
    captured = _assertion(apple, counter=5, client_data=body)
    assert verifier.verify_assertion(assertion=captured, key=key, client_data=body) == 5

    advanced = AttestedKey(
        key_id=key.key_id, public_key_der=key.public_key_der, counter=5, attested_at=key.attested_at
    )
    with pytest.raises(AttestationFailed):
        verifier.verify_assertion(assertion=captured, key=advanced, client_data=body)


def test_an_assertion_over_a_different_request_is_refused(apple) -> None:
    """Otherwise a valid assertion authenticates any body at all, which is no signature."""
    key = _attested(apple)
    signed_for = b'{"user_text":"harmless"}'
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_assertion(
            assertion=_assertion(apple, counter=1, client_data=signed_for),
            key=key,
            client_data=b'{"user_text":"something else entirely"}',
        )


def test_an_assertion_signed_by_another_key_is_refused(apple) -> None:
    key = _attested(apple)
    stranger = Apple()
    body = b"request"
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_assertion(
            assertion=_assertion(stranger, counter=1, client_data=body), key=key, client_data=body
        )


# --------------------------------------------------------------------------------------------
# Policy
# --------------------------------------------------------------------------------------------


def test_attestation_is_advisory_by_default(apple) -> None:
    """It fails for jailbroken devices, simulators, enterprise builds and Apple outages — none of
    which are attacks. Binding on day one means some legitimate users simply cannot use the app."""
    AttestationPolicy(verifier=apple.verifier()).enforce(AttestationFailed("nope"))


def test_attestation_can_be_made_binding(apple) -> None:
    with pytest.raises(AttestationFailed):
        AttestationPolicy(verifier=apple.verifier(), required=True).enforce(
            AttestationFailed("nope")
        )


# --------------------------------------------------------------------------------------------
# The chain bypass a review found by executing it. Kept as tests so it cannot come back.
#
# The original `_check_chain` searched the whole client-supplied list for an issuer and returned
# success as soon as ANY certificate reached a root. Appending the genuine Apple intermediate —
# a public artefact present in every real attestation — behind a forged leaf and a self-signed CA
# therefore passed, and with a forged leaf the attacker also controls the nonce, the public key
# and authData, so every remaining check passed trivially.
# --------------------------------------------------------------------------------------------


def test_an_attacker_cannot_splice_a_genuine_apple_certificate_onto_a_forged_leaf(apple) -> None:
    """The exact proof-of-concept: [forged leaf, attacker CA, genuine Apple-signed cert]."""
    attacker = Apple()
    genuine_intermediate = _cert(
        "Genuine Apple Intermediate",
        ec.generate_private_key(ec.SECP256R1()),
        issuer_name=apple.root.subject,
        issuer_key=apple.root_key,
        ca=True,
    )
    attestation, key_id = attacker.attestation()
    forged = cbor2.loads(attestation)
    forged["attStmt"]["x5c"] = [
        forged["attStmt"]["x5c"][0],
        attacker.root.public_bytes(Encoding.DER),
        genuine_intermediate.public_bytes(Encoding.DER),
    ]
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_attestation(
            attestation=cbor2.dumps(forged), key_id=key_id, challenge=CHALLENGE
        )


def test_a_leaf_repeated_as_its_own_issuer_is_refused(apple) -> None:
    """The second accepted variant: [leaf, leaf, genuine cert]."""
    attacker = Apple()
    genuine = _cert(
        "Genuine",
        ec.generate_private_key(ec.SECP256R1()),
        issuer_name=apple.root.subject,
        issuer_key=apple.root_key,
        ca=True,
    )
    attestation, key_id = attacker.attestation()
    forged = cbor2.loads(attestation)
    leaf = forged["attStmt"]["x5c"][0]
    forged["attStmt"]["x5c"] = [leaf, leaf, genuine.public_bytes(Encoding.DER)]
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_attestation(
            attestation=cbor2.dumps(forged), key_id=key_id, challenge=CHALLENGE
        )


def test_an_issuer_that_is_not_a_certificate_authority_is_refused(apple) -> None:
    """Without this, any leaf can sign another and be spliced into a path."""
    not_a_ca_key = ec.generate_private_key(ec.SECP256R1())
    not_a_ca = _cert(
        "Not A CA", not_a_ca_key, issuer_name=apple.root.subject, issuer_key=apple.root_key
    )  # ca=False
    child = _cert(
        "child",
        ec.generate_private_key(ec.SECP256R1()),
        issuer_name=not_a_ca.subject,
        issuer_key=not_a_ca_key,
    )
    with pytest.raises(AttestationFailed):
        apple.verifier()._check_chain([child, not_a_ca])


def test_an_absurdly_long_chain_is_refused(apple) -> None:
    """A long path is someone padding it. Apple sends leaf plus intermediate."""
    attestation, key_id = apple.attestation()
    forged = cbor2.loads(attestation)
    forged["attStmt"]["x5c"] = forged["attStmt"]["x5c"] * 5
    with pytest.raises(AttestationFailed):
        apple.verifier().verify_attestation(
            attestation=cbor2.dumps(forged), key_id=key_id, challenge=CHALLENGE
        )
