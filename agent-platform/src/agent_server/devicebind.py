"""Device binding — making an installation id something a caller must PROVE, not merely present.

**The hole this actually closes, stated honestly because the previous attempt did not.**

Session tokens were introduced to stop an installation id being a credential. They did not. They
moved it: instead of every endpoint accepting a guessable string, one endpoint accepts it and hands
back a signed token for whichever principal it names. Anyone who learns a victim's installation id
still calls `/v1/session` and walks away with a valid session for them. The surface shrank; the
takeover did not close. An external review found this and it was right.

Installation ids leak the way identifiers always leak — support tickets, crash logs, backups, a
screenshot. So the id has to become a *username*, with something alongside it that only the real
device can produce.

**The mechanism.** On first contact the device registers a public key it holds privately. Every
later session must present a signature over a fresh challenge made with that key. A caller who
knows the id but not the key gets nothing.

*Trust on first use*, deliberately. The first caller to claim an unused installation id binds it.
That is not much of an attack: ids are client-generated random values, so racing to claim one
nobody uses yet wins an empty account. What matters is that a BOUND id cannot be taken over, and
that is enforced.

**App Attest raises the ceiling, and this is what finally puts it on the request path.** The
attestation code was written, tested against a synthetic Apple CA, and referenced by nothing. When
a device presents an attestation, the key it binds is proven to live in a real Secure Enclave
running our bundle id — which additionally means the caller is our app, not a script with a stolen
key. Without one, the binding still works and is simply marked unattested: attestation is
unavailable on the simulator, on jailbroken devices, and during Apple outages, and refusing those
outright on day one locks out real users to stop a theoretical one.
"""

from __future__ import annotations

import base64
import hmac
import logging
import time
from dataclasses import dataclass

from agent_core.contracts import ErrorCode
from agent_server.core.errors import PlatformError

log = logging.getLogger("agent_server.devicebind")

#: How far a proof's timestamp may be from ours. Generous enough for a phone with a lazy clock and
#: a slow network, tight enough that a captured proof stops working quickly.
PROOF_SKEW_SECONDS = 300


class DeviceProofRequired(PlatformError):
    """This installation is bound to a key and the caller could not sign for it.

    Deliberately indistinguishable from a malformed proof. A caller who can tell "this id exists
    and you are not it" from "no such id" has an oracle for which installation ids are real.
    """

    code = ErrorCode.UNAUTHENTICATED
    status = 401
    message = "This device could not be verified. Reinstalling the app will set it up again."


@dataclass(frozen=True, slots=True)
class BoundDevice:
    installation_id: str
    public_key_der: bytes
    #: True when an App Attest attestation backed this key — the caller is our app on real hardware.
    attested: bool
    #: Highest App Attest assertion counter seen. Only meaningful when `attested`.
    counter: int


def proof_message(installation_id: str, timestamp: int) -> bytes:
    """Exactly what the device signs.

    The installation id is inside the signed bytes so a proof captured from one device cannot be
    replayed against another, and the timestamp bounds how long a captured proof stays useful.
    """
    return f"{installation_id}:{timestamp}".encode()


def verify_proof(
    device: BoundDevice, *, signature_b64: str, timestamp: int, now: int | None = None
) -> None:
    """Raise unless `signature` is this device's signature over a fresh message.

    Checked in cost order — clock first, because rejecting a stale proof costs nothing while an
    ECDSA verify is real work an unauthenticated caller could otherwise make us do repeatedly.
    """
    current = int(time.time()) if now is None else now
    if abs(current - timestamp) > PROOF_SKEW_SECONDS:
        raise DeviceProofRequired("proof timestamp outside the accepted window")

    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.hashes import SHA256
    from cryptography.hazmat.primitives.serialization import load_der_public_key

    try:
        signature = base64.b64decode(signature_b64, validate=True)
    except Exception:
        raise DeviceProofRequired("undecodable proof") from None

    try:
        load_der_public_key(device.public_key_der).verify(
            signature, proof_message(device.installation_id, timestamp), ec.ECDSA(SHA256())
        )
    except InvalidSignature:
        raise DeviceProofRequired("proof does not match the bound key") from None
    except Exception:
        # A key that will not load, a signature of the wrong shape — all one answer to the caller.
        raise DeviceProofRequired("proof could not be checked") from None


def load_public_key(key_b64: str) -> bytes:
    """Validate and normalise a client-supplied public key to DER.

    Parsed rather than stored blindly: an unparseable key would bind an installation to something
    no signature can ever satisfy, permanently locking that install out with no way back except a
    reinstall.
    """
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.serialization import (
        Encoding,
        PublicFormat,
        load_der_public_key,
    )

    try:
        raw = base64.b64decode(key_b64, validate=True)
        key = load_der_public_key(raw)
    except Exception:
        raise DeviceProofRequired("unusable device key") from None
    if not isinstance(key, ec.EllipticCurvePublicKey):
        # P-256 is what the Secure Enclave produces and what App Attest uses. Accepting anything
        # else means accepting a key the attestation path could never corroborate.
        raise DeviceProofRequired("device key must be an elliptic-curve key")
    return key.public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)


def same_key(left: bytes, right: bytes) -> bool:
    """Constant-time comparison, so a rebinding attempt cannot be probed byte by byte."""
    return hmac.compare_digest(left, right)
