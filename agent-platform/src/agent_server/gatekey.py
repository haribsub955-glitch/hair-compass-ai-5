"""A pre-shared key on the front door — the whole deployment, not one endpoint.

**What this is for.** The server is about to be reachable from the internet so one external tester
can drive it from a phone. `/v1/session` currently authenticates nothing, so anyone who finds the
hostname gets free turns on a provider key that costs real money, and can take over accounts by
guessing an installation id. Device binding is the proper fix and needs a client change on a Mac.

Until then this is the door: no key, no server. Not a replacement for the auth work — a wall in
front of it while it is built.

**Deliberately dumb, and that is the point.** One shared secret in a header, compared in constant
time, checked before routing. No sessions, no rotation ceremony, no user model. It answers exactly
one question — "was this request made by someone we gave a key to" — and a cleverer design would
be a second authentication system to get wrong beside the first.

**It stacks with Cloudflare Access rather than replacing it.** Access gates at the edge on identity
and never sees a request the tunnel refuses; this gates at the origin and survives the tunnel being
misconfigured, bypassed, or replaced. Either alone is a single point of failure; together, a
mistake in one is not an exposure.

**Off by default.** An empty `ACCESS_KEYS` disables it entirely, so a laptop and the test suite are
untouched. `validate_for_environment` refuses a live deployment without one, because "internet
exposed with no front door" is precisely the state this exists to make impossible.
"""

from __future__ import annotations

import hmac
import logging

from agent_core.contracts import ErrorCode
from agent_server.core.errors import PlatformError

log = logging.getLogger("agent_server.gatekey")

#: The header carrying it. `X-` prefixed because it is ours and not a standard.
ACCESS_KEY_HEADER = "X-Access-Key"


class AccessDenied(PlatformError):
    """No key, or the wrong one. Says nothing else — a caller who can tell "no key" from "wrong
    key" learns that keys are what this wants, which is a free hint."""

    code = ErrorCode.UNAUTHENTICATED
    status = 401
    message = "Not available."


class GateKeys:
    """Named pre-shared keys. The name exists so a key can be identified in the audit log and
    withdrawn individually — a single anonymous secret cannot be revoked for one holder."""

    __slots__ = ("_by_key",)

    def __init__(self, raw: str) -> None:
        # `name=secret` pairs. Malformed entries are dropped rather than raising: a typo should
        # cost that holder their access, not stop the server from starting.
        self._by_key: dict[str, str] = {}
        for item in raw.split(","):
            name, _, secret = item.partition("=")
            name, secret = name.strip(), secret.strip()
            if not name or len(secret) < 24:
                # Short secrets are refused outright. A guessable front door is worse than none,
                # because it looks like a control while inviting exactly one brute-force loop.
                if item.strip():
                    log.warning(
                        "ignoring access key %r: missing name or secret under 24 chars", name
                    )
                continue
            self._by_key[secret] = name

    def __bool__(self) -> bool:
        return bool(self._by_key)

    @property
    def names(self) -> tuple[str, ...]:
        return tuple(sorted(self._by_key.values()))

    def holder(self, presented: str | None) -> str:
        """The name behind this key. Raises `AccessDenied` for anything else.

        Compared in constant time against every key, and the loop does not exit early on a match —
        a timing difference between "first key" and "last key" leaks which holder you are, and the
        set is small enough that scanning it all costs nothing.
        """
        if not self._by_key:
            return ""
        if not presented:
            raise AccessDenied("no key presented")

        offered = presented.encode()
        found = ""
        for secret, name in self._by_key.items():
            if hmac.compare_digest(offered, secret.encode()):
                found = name
        if not found:
            raise AccessDenied("key not recognised")
        return found
