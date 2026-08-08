"""The tool registry — what the agent can do, where each one runs, and who may run it.

Two things here are load-bearing and easy to get wrong.

**Where a tool runs is a declaration, not a call site.** `runtime=DEVICE` means the server suspends
the step and asks the phone; `runtime=SERVER` means it runs in-process. The loop never branches on
it — the dispatcher reads it. That is what lets the loop move from a laptop to a datacenter without
being edited.

**The client may only ever subtract.** A phone can truthfully say "I cannot do OCR on this OS
version". It can never say "I am allowed to do this", because a patched binary would say whatever
unlocks the most. So the effective tool set is an intersection whose last term is the client's, and
that term can only remove (ARCHITECTURE.md §7).

Platform neutrality is a constraint, not an aspiration: `Platform` carries Android from the first
commit, and a test enumerates exactly which tools an Android client would lose so the gap is visible
rather than discovered during a port.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any

from agent_core.contracts import Entitlement


class Runtime(StrEnum):
    DEVICE = "device"
    SERVER = "server"


class Platform(StrEnum):
    IOS = "ios"
    ANDROID = "android"
    TEST = "test"


ALL_PLATFORMS = frozenset({Platform.IOS, Platform.ANDROID, Platform.TEST})


class ToolError(RuntimeError):
    """A malformed tool declaration. Raised at import time — a bad tool must never reach a turn."""


@dataclass(frozen=True, slots=True)
class ToolSpec:
    """One tool the model may call.

    `effects` is what the Action Gate tiers on. **Never the tool's name** — the desktop agent
    learned this the expensive way: `write_note(name='report.html')` produces a carrier artifact
    exactly as `create_document` does, so tiering by name under-protects whatever is named
    innocuously. Effects describe what actually happens.

    `taints` marks a tool whose output carries user- or document-supplied text into the prompt. The
    server applies it from *this* declaration, based on which tool it dispatched — never from
    anything the client says about the result, which a patched client would understate.

    `idempotent` is not a nicety. A device tool that mutates something and is retried after a lost
    acknowledgement will do it twice — "add this procedure to the calendar" becoming two calendar
    entries is a real bug with a real user complaint attached. Non-idempotent mutating tools are
    required to carry a key.
    """

    name: str
    description: str
    schema: dict[str, Any]
    runtime: Runtime
    effects: tuple[str, ...] = ()
    taints: bool = False
    mutates: bool = False
    idempotent: bool = False
    requires_idempotency_key: bool = False
    min_entitlement: Entitlement = Entitlement.FREE
    platforms: frozenset[Platform] = field(default=ALL_PLATFORMS)
    min_protocol: int = 1

    def __post_init__(self) -> None:
        if not self.name or not self.description:
            raise ToolError(f"{self.name or '<unnamed>'}: needs a name and a description")
        if self.mutates and not (self.idempotent or self.requires_idempotency_key):
            raise ToolError(
                f"{self.name}: mutates but is neither idempotent nor keyed — a retry after a lost "
                "acknowledgement would repeat the effect"
            )
        if self.runtime is Runtime.SERVER and self.taints:
            # Server tools read our own catalogs. If one ever carries third-party text into a
            # prompt it needs the same treatment as device output, and that deserves a decision
            # rather than a default.
            raise ToolError(
                f"{self.name}: a server tool marked taints needs an explicit review — server "
                "output is trusted by default and this breaks that assumption"
            )

    def available_on(self, platform: Platform) -> bool:
        return platform in self.platforms


class ToolRegistry:
    """The server's catalog. Authoritative — the client never adds to it."""

    __slots__ = ("_by_name",)

    def __init__(self, tools: Iterable[ToolSpec]) -> None:
        self._by_name: dict[str, ToolSpec] = {}
        for tool in tools:
            if tool.name in self._by_name:
                raise ToolError(f"{tool.name}: declared twice")
            self._by_name[tool.name] = tool

    def __iter__(self):
        return iter(self._by_name.values())

    def __len__(self) -> int:
        return len(self._by_name)

    def get(self, name: str) -> ToolSpec:
        try:
            return self._by_name[name]
        except KeyError:
            raise ToolError(f"{name}: not in the catalog") from None

    def resolve(
        self,
        *,
        platform: Platform,
        entitlement: Entitlement,
        protocol_version: int,
        client_advertised: frozenset[str] | None = None,
        pack_allowlist: frozenset[str] | None = None,
    ) -> tuple[ToolSpec, ...]:
        """The effective tool set for one turn.

            pack allowlist  ∩  entitlement  ∩  platform  ∩  protocol  ∩  client-advertised
                                                                          (subtractive only)

        `client_advertised` is applied last and can only remove. `None` means the client said
        nothing, which is treated as "everything the server would otherwise offer" — a silent client
        loses nothing, and a lying one gains nothing.
        """
        tools = []
        for tool in self._by_name.values():
            if pack_allowlist is not None and tool.name not in pack_allowlist:
                continue
            if not _entitled(entitlement, tool.min_entitlement):
                continue
            if not tool.available_on(platform):
                continue
            if protocol_version < tool.min_protocol:
                continue
            # Device tools depend on client code, so a client that does not advertise one does not
            # have it. Server tools are ours and are never withheld on a client's say-so.
            if (
                client_advertised is not None
                and tool.runtime is Runtime.DEVICE
                and tool.name not in client_advertised
            ):
                continue
            tools.append(tool)
        return tuple(sorted(tools, key=lambda t: t.name))


_ENTITLEMENT_ORDER = {Entitlement.FREE: 0, Entitlement.PRO: 1}


def _entitled(held: Entitlement, required: Entitlement) -> bool:
    return _ENTITLEMENT_ORDER[held] >= _ENTITLEMENT_ORDER[required]
