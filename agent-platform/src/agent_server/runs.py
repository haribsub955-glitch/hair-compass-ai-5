"""In-flight turns, and how a result from one phone finds its way back to the right one.

With a single device this is invisible: the agent calls `device.execute(step)` and awaits. With
many devices it is the whole problem. Five users are mid-turn; five phones are each running tool
calls; results arrive over HTTP in whatever order the network delivers them. Something has to
answer "which turn was this for, and is this phone allowed to answer it?"

**The two properties that matter, and only the second is obvious.**

*Routing* — a result carries a `call_id`, and the registry knows which run issued it. That is
bookkeeping; get it wrong and turns hang.

*Ownership* — a result is accepted only from the principal whose run issued the call. Get this
wrong and one user's phone can inject tool results into another user's turn: fabricated lab values,
fabricated memories, all of it landing in someone else's prompt and someone else's answer. This is
the multi-user security property of the whole design, and it is one line of check that has to be
right (ARCHITECTURE.md §5 — a client value is never trusted, and *which* client sent it is a
server-derived fact, never a claim in the body).

Everything here is per-process, which is correct for now and wrong later: two containers cannot see
each other's runs. The fix is the same one already scheduled for the ledger — Postgres — and the
interface below is what that implementation has to satisfy.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from uuid import uuid4

from agent_core.contracts import Principal
from agent_core.dispatch import DispatchStep, StepCollector, ToolCall, ToolResult
from agent_core.tools import ToolRegistry


class RunError(RuntimeError):
    """A submission that could not be honoured. Never leaks whose run it was."""


@dataclass
class Run:
    """One turn in flight."""

    id: str
    principal: Principal
    #: Set while a dispatch step is outstanding; None between steps.
    collector: StepCollector | None = None
    calls: tuple[ToolCall, ...] = ()
    ready: asyncio.Event = field(default_factory=asyncio.Event)

    @property
    def owner_key(self) -> tuple[str, str]:
        """What must match for a submission to be accepted. Both halves matter: `principal_id`
        alone would let one app's principal answer another app's run in a multi-app deployment."""
        return (self.principal.app_id, self.principal.principal_id)


class RunRegistry:
    """Every turn currently waiting on a device, across every user.

    One instance per process, shared by every request. All mutation happens under one lock because
    the critical sections are microseconds long and the alternative — per-run locks — buys nothing
    at this scale and costs a class of deadlock.
    """

    __slots__ = ("_lock", "_owner_of_call", "_runs")

    def __init__(self) -> None:
        self._runs: dict[str, Run] = {}
        #: call_id -> run_id. How a bare result finds its turn.
        self._owner_of_call: dict[str, str] = {}
        self._lock = asyncio.Lock()

    async def open(self, principal: Principal) -> Run:
        run = Run(id=f"r_{uuid4().hex[:20]}", principal=principal)
        async with self._lock:
            self._runs[run.id] = run
        return run

    async def close(self, run: Run) -> None:
        """Drop the run and every call id it owned. Called in a `finally`, so a turn that raises
        does not leak its call ids into the next one's routing table."""
        async with self._lock:
            self._runs.pop(run.id, None)
            for call_id in [c for c, r in self._owner_of_call.items() if r == run.id]:
                self._owner_of_call.pop(call_id, None)

    async def begin_step(self, run: Run, step: DispatchStep) -> None:
        async with self._lock:
            for call in step.calls:
                existing = self._owner_of_call.get(call.id)
                if existing is not None and existing != run.id:
                    # Two live runs claiming one call id. Silently overwriting is what this used to
                    # do, and it cost four of five concurrent turns: the later run took ownership,
                    # the earlier ones' phones were correctly refused, and those turns hung to
                    # their deadline. Fail loudly instead — a collision here is a bug upstream, and
                    # `RemoteDeviceExecutor` namespaces ids precisely so it cannot happen.
                    raise RunError(f"call id {call.id!r} is already owned by another live run")
            run.collector = StepCollector(step)
            run.calls = step.calls
            run.ready.clear()
            for call in step.calls:
                self._owner_of_call[call.id] = run.id

    async def submit(self, *, principal: Principal, result: ToolResult) -> bool:
        """Record a result from a device. Returns False for a duplicate, which is not an error.

        The ownership check is the point of this method. A phone submits a `call_id`; the registry
        finds whose run issued it and refuses unless the authenticated principal matches. An
        attacker who guesses a call id still cannot answer a stranger's turn.
        """
        async with self._lock:
            run_id = self._owner_of_call.get(result.call_id)
            run = self._runs.get(run_id) if run_id else None
            if run is None or run.collector is None:
                # Unknown, already finished, or never ours. Deliberately the same error either way:
                # distinguishing them would confirm to a prober that a call id exists.
                raise RunError("no such call")
            if (principal.app_id, principal.principal_id) != run.owner_key:
                raise RunError("no such call")
            accepted = run.collector.submit(result)
            if run.collector.complete:
                run.ready.set()
            return accepted

    async def await_step(
        self, run: Run, *, registry: ToolRegistry, timeout_seconds: float
    ) -> tuple[ToolResult, ...]:
        """Wait for every call in the current step, or expire the stragglers.

        On timeout each missing call gets the terminal status its *tool* deserves — a read expires
        and may be retried, a mutation becomes UNKNOWN and never will (docs/DISPATCH.md). That
        decision is not made here; it is `expire_outstanding`'s, which reads the tool declarations.
        """
        collector = run.collector
        if collector is None:
            raise RunError("no step in flight")
        try:
            await asyncio.wait_for(run.ready.wait(), timeout=timeout_seconds)
        except TimeoutError:
            collector.expire_outstanding(registry=registry, calls=run.calls)
        results = collector.results()
        async with self._lock:
            run.collector = None
            for call in run.calls:
                self._owner_of_call.pop(call.id, None)
            run.calls = ()
        return results

    async def count(self) -> int:
        async with self._lock:
            return len(self._runs)


class RemoteDeviceExecutor:
    """A `DeviceExecutor` backed by a real phone on the other end of an HTTP connection.

    Created per turn, bound to one run, so the agent's own code stays identical whether the device
    is this, a fake in a test, or an in-process stub. That substitutability is why `device` belongs
    on `run()` rather than on the `Agent` — an executor bound to the agent would be one phone
    shared by every user of the process.
    """

    __slots__ = ("_on_dispatch", "_registry", "_run", "_timeout", "_tools")

    def __init__(
        self,
        *,
        run: Run,
        runs: RunRegistry,
        tools: ToolRegistry,
        timeout_seconds: float = 30.0,
        on_dispatch: Callable[[DispatchStep], Awaitable[None]] | None = None,
    ) -> None:
        self._run = run
        self._registry = runs
        self._tools = tools
        self._timeout = timeout_seconds
        self._on_dispatch = on_dispatch

    async def execute(self, step: DispatchStep) -> tuple[ToolResult, ...]:
        """Namespace the call ids, register, tell the phone, then wait.

        **The ids on the wire are the server's, not the model's.** A model picks its own tool-call
        ids, and nothing stops two concurrent turns picking the same one — a scripted fake did
        exactly that and cost four of five concurrent turns, because each `begin_step` overwrote the
        previous run's ownership. (The ownership check held, so no data crossed; the other four
        turns simply hung to their deadline.) Prefixing with the run id makes a collision
        impossible by construction, which is the same "server-derived, never supplied" rule applied
        to everything else here.

        Results are mapped back to the model's original ids before returning, because the provider
        matches a `tool_result` to its `tool_use` block by that id — the namespacing must not leak
        into the transcript.

        Registration happens **before** the phone is told. The other order has a real race: a fast
        client can submit a result before the registry knows the call exists, and the submission is
        refused as "no such call" while the turn hangs for no reason visible in a log.
        """
        wire_of_model = {call.id: f"{self._run.id}:{call.id}"[:64] for call in step.calls}
        model_of_wire = {wire: model for model, wire in wire_of_model.items()}
        wire_step = DispatchStep(
            calls=tuple(
                call.model_copy(update={"id": wire_of_model[call.id]}) for call in step.calls
            ),
            parallel=step.parallel,
        )

        await self._registry.begin_step(self._run, wire_step)
        if self._on_dispatch is not None:
            await self._on_dispatch(wire_step)
        results = await self._registry.await_step(
            self._run, registry=self._tools, timeout_seconds=self._timeout
        )
        return tuple(
            result.model_copy(update={"call_id": model_of_wire.get(result.call_id, result.call_id)})
            for result in results
        )
