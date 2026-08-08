"""Where each capability runs — declared as data, so migration is a table edit.

The agent will start life with its loop running on a laptop over LAN and end it running in a
datacenter. Nothing in the loop may know the difference. That is only true if placement is never
expressed as an `if` — it has to be a declaration the wiring reads, with implementations behind one
interface each (CLAUDE.md §AR).

Three placements, and the middle one is the whole point:

* `DEVICE`  — must run on the phone. An OS API, private data at rest, or something needed offline.
* `SERVER`  — must run on the server. A secret, money, an authority decision, or IP.
* `EITHER`  — genuinely relocatable. Placement is a deployment choice, not a property.

The invariants below are enforced by tests rather than by convention, because the failure they
prevent is silent: a capability quietly marked `EITHER` that turns out to hold an API key ships that
key in a binary, and nothing about the code looks wrong. `handles_secret` and `decides_authority`
are declared per capability precisely so a wrong placement is a test failure and not an incident.

Platform note: nothing here names iOS or Android. The same declaration serves both, and the split
that matters (device vs server) is identical on each.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from enum import StrEnum


class Placement(StrEnum):
    DEVICE = "device"
    SERVER = "server"
    EITHER = "either"


class Side(StrEnum):
    """Which process is asking. `resolve` refuses a side that a placement forbids."""

    DEVICE = "device"
    SERVER = "server"


class PlacementError(RuntimeError):
    """A capability was wired somewhere its declaration forbids. Always fatal at startup — a
    misplacement discovered at runtime has already leaked whatever it was protecting."""


@dataclass(frozen=True, slots=True)
class Capability:
    """One thing the agent can do, and where it is allowed to do it.

    The three booleans are not documentation — they drive the invariants:

    * `handles_secret` — touches a provider key, signing key, or database credential. Forces SERVER.
      A secret on a device is a published secret; obfuscation only changes how long it takes.
    * `decides_authority` — its answer grants or denies something (entitlement, quota, policy tier).
      Forces SERVER, because a patched client controls anything it computes.
    * `holds_personal_data` — user records. Not a constraint by itself, but it is what the residency
      review reads (ARCHITECTURE.md §10), so it must be truthful.
    """

    name: str
    placement: Placement
    reason: str
    handles_secret: bool = False
    decides_authority: bool = False
    holds_personal_data: bool = False

    def __post_init__(self) -> None:
        if not self.reason:
            raise PlacementError(f"{self.name}: a placement needs a stated reason")
        if self.handles_secret and self.placement is not Placement.SERVER:
            raise PlacementError(
                f"{self.name}: handles a secret, so it cannot be {self.placement.value}"
            )
        if self.decides_authority and self.placement is not Placement.SERVER:
            raise PlacementError(
                f"{self.name}: decides authority, so it cannot be {self.placement.value}"
            )

    def allows(self, side: Side) -> bool:
        if self.placement is Placement.EITHER:
            return True
        return self.placement.value == side.value


class PlacementMap:
    """The declared placement of every capability.

    One table. Migration edits it and nothing else."""

    __slots__ = ("_by_name",)

    def __init__(self, capabilities: Iterable[Capability]) -> None:
        self._by_name: dict[str, Capability] = {}
        for capability in capabilities:
            if capability.name in self._by_name:
                raise PlacementError(f"{capability.name}: declared twice")
            self._by_name[capability.name] = capability

    def __iter__(self):
        return iter(self._by_name.values())

    def __len__(self) -> int:
        return len(self._by_name)

    def get(self, name: str) -> Capability:
        try:
            return self._by_name[name]
        except KeyError:
            raise PlacementError(f"{name}: no placement declared") from None

    def require(self, name: str, side: Side) -> Capability:
        """Assert a capability may run here. Called at wiring time, so a misplacement is a startup
        crash rather than a surprise on some later request."""
        capability = self.get(name)
        if not capability.allows(side):
            raise PlacementError(
                f"{name}: declared {capability.placement.value}, cannot run on the {side.value}"
                f" — {capability.reason}"
            )
        return capability

    def on(self, side: Side) -> tuple[Capability, ...]:
        return tuple(c for c in self if c.allows(side))


#: The platform's placement table. Every row states its reason, because the reason is the thing a
#: future reader needs in order to decide whether a move is safe.
PLATFORM_PLACEMENT = PlacementMap(
    [
        # --- server: money, secrets, authority -------------------------------------------------
        Capability(
            name="model_adapter",
            placement=Placement.SERVER,
            handles_secret=True,
            reason="holds the provider API key",
        ),
        Capability(
            name="cost_ledger",
            placement=Placement.SERVER,
            decides_authority=True,
            reason="spending limits a client could otherwise raise for itself",
        ),
        Capability(
            name="entitlement",
            placement=Placement.SERVER,
            decides_authority=True,
            reason="paid access, verified against store server records not a client claim",
        ),
        Capability(
            name="action_gate_policy",
            placement=Placement.SERVER,
            decides_authority=True,
            reason="a patched client would return a permissive policy for itself",
        ),
        Capability(
            name="tool_catalog",
            placement=Placement.SERVER,
            decides_authority=True,
            reason="which tools exist is an authorization decision; the client may only subtract",
        ),
        # --- server: intellectual property -----------------------------------------------------
        Capability(
            name="agent_loop",
            placement=Placement.SERVER,
            reason="the loop is the product; shipping it in a binary publishes it",
        ),
        Capability(
            name="prompt_pack",
            placement=Placement.SERVER,
            reason="prompts are IP, and server-held means improving them needs no store release",
        ),
        Capability(
            name="skills",
            placement=Placement.SERVER,
            reason="procedural IP; a signed read-only cache is the offline compromise",
        ),
        Capability(
            name="playbooks",
            placement=Placement.SERVER,
            reason="procedural IP, same as skills",
        ),
        Capability(
            name="safety_verifier",
            placement=Placement.SERVER,
            decides_authority=True,
            reason="decides what may be shown; a client could otherwise approve its own output",
        ),
        Capability(
            name="audit_log",
            placement=Placement.SERVER,
            reason="compliance record; metadata only, never raw payloads",
        ),
        Capability(
            name="run_state",
            placement=Placement.SERVER,
            holds_personal_data=True,
            reason="needed to resume a run; held for the life of the run, then discarded",
        ),
        # --- device: personal, offline, OS-bound -----------------------------------------------
        Capability(
            name="memory_store",
            placement=Placement.DEVICE,
            holds_personal_data=True,
            reason="the user's own records; what never leaves is never transferred (PDPL)",
        ),
        Capability(
            name="transcript",
            placement=Placement.DEVICE,
            holds_personal_data=True,
            reason="device is authoritative; the server keeps a copy only while a run is live",
        ),
        Capability(
            name="artifact_store",
            placement=Placement.DEVICE,
            holds_personal_data=True,
            reason="photo bytes stay put; a signed upload happens only when a turn needs one",
        ),
        Capability(
            name="notifications",
            placement=Placement.DEVICE,
            reason="OS-level scheduling exists nowhere else",
        ),
        Capability(
            name="health_source",
            placement=Placement.DEVICE,
            holds_personal_data=True,
            reason="HealthKit and Health Connect are device APIs",
        ),
        Capability(
            name="secure_storage",
            placement=Placement.DEVICE,
            reason="Keychain and Keystore hold the session token; nothing else may",
        ),
        # --- either: genuinely relocatable ------------------------------------------------------
        Capability(
            name="consent_record",
            placement=Placement.EITHER,
            holds_personal_data=True,
            reason="device copy drives display and withdrawal; the server copy is authoritative",
        ),
        Capability(
            name="feature_flags",
            placement=Placement.EITHER,
            reason="server-delivered, device-cached so a cold start still renders",
        ),
    ]
)
