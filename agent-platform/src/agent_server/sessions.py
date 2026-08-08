"""Session tokens — proof that a caller is who they say they are.

**The hole this closes.** Identity was derived from `installation_id`, which the client sends and
picks. Nothing else authenticated anything. So anyone who learned another user's installation id
could call `/v1/privacy/state` and read their consent record and audit trail, or
`/v1/privacy/forget` and erase their account — and a StoreKit receipt could not help, because it
selects a *plan*, never a person.

An installation id is at best a username. This is the password half.

**The shape.** `/v1/session` is the one endpoint that accepts an installation id, and it hands back
a signed token naming the principal it derived. Every other endpoint requires the token and derives
identity from it. Guessing an installation id then gets you a session for a principal you already
control — which is nothing — instead of access to someone else's data.

**Why HMAC and not a database row.** The server already holds a secret used to derive principal
ids, verification is one hash, and there is no revocation requirement that a short expiry does not
already satisfy. A token table would add a database round trip to every request and a cleanup job,
to solve a problem this deployment does not have. If revocation becomes real (a stolen token, an
account takeover), add a `token_version` column and mix it into the payload — the seam is here.

The token is opaque to the client: it carries no readable claims, only what the server needs to
re-derive the principal and check the expiry.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import time

from agent_core.contracts import Entitlement, ErrorCode, Principal
from agent_server.core.errors import PlatformError

log = logging.getLogger("agent_server.sessions")

#: How long a session token is good for. Long enough that a phone in normal use never notices,
#: short enough that a leaked token is not a permanent credential. The client re-runs `/v1/session`
#: on expiry, which it already does on launch.
TOKEN_TTL_SECONDS = 24 * 60 * 60


class InvalidSession(PlatformError):
    """A missing, malformed, expired or forged token. Never says which — a caller learning
    "expired" versus "bad signature" learns how to probe."""

    code = ErrorCode.UNAUTHENTICATED
    status = 401
    message = "Your session has ended. Open the app again to continue."


def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _unb64(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


class SessionTokens:
    """Mints and verifies session tokens with the server's own secret."""

    def __init__(self, secret: str, *, ttl_seconds: int = TOKEN_TTL_SECONDS) -> None:
        if len(secret) < 32:
            # The same key derives principal ids. A short one means a client that guesses it can
            # both compute anyone's principal id and mint a token for it.
            raise RuntimeError("session secret must be at least 32 characters")
        self._secret = secret.encode()
        self._ttl = ttl_seconds

    def issue(self, principal: Principal) -> str:
        payload = {
            "p": principal.principal_id,
            "d": principal.installation_id,
            "s": principal.data_subject_id,
            "a": principal.app_id,
            "e": principal.entitlement.value,
            # The plan travels in the signed token so every endpoint measures against the
            # same value, and a client cannot name its own tier.
            "pl": principal.plan_id,
            "x": int(time.time()) + self._ttl,
        }
        body = _b64(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode())
        return f"{body}.{self._sign(body)}"

    def verify(self, token: str) -> Principal:
        """The principal this token names. Raises `InvalidSession` for anything else.

        The signature is checked BEFORE the payload is parsed, so a forged token cannot reach the
        JSON decoder — and compared with `compare_digest`, because a plain `==` on a signature
        leaks its bytes through timing.
        """
        if not token or "." not in token:
            raise InvalidSession("malformed token")
        body, _, signature = token.rpartition(".")
        # Compared as BYTES. `hmac.compare_digest` raises TypeError on str inputs containing
        # non-ASCII, so a token with one stray high byte was an unhandled 500 instead of a 401 —
        # which is both a crash an anonymous caller can trigger and a signal that distinguishes
        # "malformed" from "wrong", exactly what this class refuses to reveal.
        if not hmac.compare_digest(signature.encode("utf-8", "replace"), self._sign(body).encode()):
            raise InvalidSession("bad signature")
        try:
            payload = json.loads(_unb64(body))
        except Exception:
            raise InvalidSession("undecodable payload") from None

        if int(payload.get("x", 0)) < time.time():
            raise InvalidSession("expired")

        try:
            return Principal(
                app_id=payload["a"],
                principal_id=payload["p"],
                installation_id=payload["d"],
                data_subject_id=payload["s"],
                entitlement=Entitlement(payload["e"]),
                # Tokens minted before this field existed carry no plan; falling back to the
                # entitlement keeps them working until they expire rather than 401-ing
                # everyone mid-deploy.
                plan_id=payload.get("pl") or payload["e"],
            )
        except Exception:
            # A validly-signed token that will not rebuild is a deploy that changed the shape of
            # `Principal`. Treat it as expired so the client re-runs `/v1/session` rather than
            # getting stuck.
            log.warning("session token no longer matches the Principal shape; forcing re-issue")
            raise InvalidSession("stale token shape") from None

    def _sign(self, body: str) -> str:
        return _b64(hmac.new(self._secret, body.encode(), hashlib.sha256).digest())
