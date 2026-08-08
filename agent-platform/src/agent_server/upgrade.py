"""Forced upgrade — the server's ability to stop talking to a build it should not talk to.

`protocol_version` has existed since the first contract and nothing ever acted on it. That is fine
until the day it is not: a client with a safety bug, a client that mishandles a tool result, or a
client from before a breaking protocol change is a client you need to be able to switch off — and
without this the only lever is taking the whole service down.

**Two separate questions, deliberately not collapsed.**

*Can this build still work?* — the protocol version. A mismatch is not a matter of taste; the wire
format changed and the conversation cannot proceed.

*Should this build still be used?* — the minimum build. The protocol is fine, but the version has a
defect worth pushing people off. This is a soft signal by default, because forcing an upgrade on
someone with no wifi and a legitimate question is its own kind of harm.

**The client is told, always.** Every session response carries the upgrade state, so an app can show
a banner long before it is cut off — a forced upgrade that arrives as a sudden error is a support
ticket, while one that arrives as two weeks of nagging is a product decision.

Thresholds are config, not constants. The point of the lever is being able to pull it without a
deploy.
"""

from __future__ import annotations

import logging
import re
from enum import StrEnum

from agent_core.contracts import ErrorCode
from agent_server.core.errors import PlatformError

log = logging.getLogger("agent_server.upgrade")


class UpgradeRequired(PlatformError):
    """This build may no longer talk to this server."""

    code = ErrorCode.PROTOCOL_UNSUPPORTED
    status = 426
    message = "Please update the app to continue."


class UpgradeState(StrEnum):
    """What the client should tell the user, if anything."""

    #: Nothing to say.
    CURRENT = "current"
    #: Newer builds exist and this one should move, but it still works.
    ENCOURAGED = "encouraged"
    #: Below the minimum. Still served, so the user is not stranded mid-task, but the app should
    #: show a blocking prompt.
    REQUIRED = "required"
    #: Refused outright — the protocol no longer matches, so nothing useful can happen.
    BLOCKED = "blocked"


def _parse(build: str) -> tuple[int, ...]:
    """A comparable tuple from a build string.

    Deliberately forgiving. A build string arrives from a client, so it can be anything: `"1.2.3"`,
    `"42"`, `"1.2.3-beta"`, or empty. Non-numeric parts are dropped rather than raising, because a
    weird build string must not become a 500 — the worst it should do is compare as older, which
    fails toward telling the user to update.
    """
    parts = re.findall(r"\d+", build or "")
    return tuple(int(p) for p in parts[:4]) or (0,)


def compare_builds(build: str, minimum: str) -> bool:
    """Is `build` at least `minimum`? Missing components count as zero, so `1.2` < `1.2.1`."""
    a, b = _parse(build), _parse(minimum)
    width = max(len(a), len(b))
    return a + (0,) * (width - len(a)) >= b + (0,) * (width - len(b))


class UpgradePolicy:
    """Which builds are current, which are stale, and which are refused.

    `blocked_below` is separate from `minimum_build` because the two failures are different: a
    stale build is a nag, a protocol-incompatible one cannot be served at all. Conflating them
    means either nagging becomes an outage or an incompatible client gets a banner and a broken
    experience.
    """

    def __init__(
        self,
        *,
        protocol_version: int,
        minimum_build: str = "",
        blocked_below: str = "",
        latest_build: str = "",
    ) -> None:
        self.protocol_version = protocol_version
        self.minimum_build = minimum_build
        self.blocked_below = blocked_below
        self.latest_build = latest_build

    def evaluate(self, *, client_protocol: int, app_build: str) -> UpgradeState:
        """What this client should be told. Never raises — `check` decides the consequence."""
        if client_protocol != self.protocol_version:
            return UpgradeState.BLOCKED
        if self.blocked_below and not compare_builds(app_build, self.blocked_below):
            return UpgradeState.BLOCKED
        if self.minimum_build and not compare_builds(app_build, self.minimum_build):
            return UpgradeState.REQUIRED
        if self.latest_build and not compare_builds(app_build, self.latest_build):
            return UpgradeState.ENCOURAGED
        return UpgradeState.CURRENT

    def check(self, *, client_protocol: int, app_build: str) -> UpgradeState:
        """Evaluate and refuse if the build is BLOCKED.

        `REQUIRED` is deliberately still served. Cutting someone off mid-task to make a point about
        a version is its own harm; the app has the state and can show a blocking prompt at a moment
        that is not the middle of a question. `BLOCKED` is refused because there is nothing useful
        left to do — the wire format does not match, or the build is known-dangerous.
        """
        state = self.evaluate(client_protocol=client_protocol, app_build=app_build)
        if state is UpgradeState.BLOCKED:
            log.info("refused build %r on protocol %s", app_build, client_protocol)
            raise UpgradeRequired(f"build={app_build!r} protocol={client_protocol}")
        return state
