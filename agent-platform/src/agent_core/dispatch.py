"""Device-tool dispatch — how the server asks a phone to do something, and what happens when the
network eats the answer.

Read `docs/DISPATCH.md` first if you are picking this up cold. The short version:

The loop runs on a server. Some tools can only run on the phone (the user's records, HealthKit,
the camera, the calendar). So a turn looks like: server thinks -> server asks the phone to do
something -> phone answers -> server thinks again. Each of those arrows is a network trip on a
mobile connection, and they add up fast enough to change how the product feels.

**The two decisions this module encodes.**

*Independent reads are dispatched together, mutations never are.* Five sequential reads on a phone
network is roughly an eight-second turn; the same five in parallel is roughly two. Reads are safe to
overlap because they have no side effects and no ordering — asking for the user's recent entries
does not change what their lab results say. Mutations get a step to themselves: two writes running
concurrently can interleave in ways nobody can reason about, and when one fails you cannot say what
state the device is in.

*A timed-out read may be retried; a timed-out mutation may not.* This asymmetry is the whole
correctness story. If "read the last 30 entries" times out, running it again is free. If "add this
procedure to the calendar" times out, the phone may have already done it and lost the answer on the
way back — retrying gives the user two calendar entries to delete by hand. So a mutation whose
answer never arrives becomes `UNKNOWN`, which is a terminal state that stops the turn and never
auto-retries.

Nothing here knows whether the phone is an iPhone or an Android, and nothing here knows whether the
server is a laptop on the same wifi or a container in a datacenter.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from agent_core.tools import Runtime, ToolRegistry, ToolSpec

#: How long a device has to answer one call before the server gives up on it. Deliberately short —
#: a phone that has not answered in 30s is usually backgrounded or off-network, and holding the turn
#: open longer only makes the user stare at a spinner for longer.
DEFAULT_DEADLINE_SECONDS = 30


class Base(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class CallStatus(StrEnum):
    """Where one tool call got to.

    The five terminal states are not decoration — the difference between `FAILED` and `UNKNOWN` is
    the difference between "safe to run again" and "we must never run this again".
    """

    PENDING = "pending"
    DISPATCHED = "dispatched"
    SUCCEEDED = "succeeded"
    #: Definitely did not happen. Safe to retry if the tool is a read.
    FAILED = "failed"
    #: The user said no, or policy said no. Never retried; retrying an explicit denial is how an
    #: agent nags a user into approving something.
    DENIED = "denied"
    #: The deadline passed on a tool that cannot have had an effect.
    EXPIRED = "expired"
    #: May or may not have happened, and we cannot tell. Terminal. Never auto-retried.
    UNKNOWN = "unknown"


TERMINAL = frozenset(
    {
        CallStatus.SUCCEEDED,
        CallStatus.FAILED,
        CallStatus.DENIED,
        CallStatus.EXPIRED,
        CallStatus.UNKNOWN,
    }
)


class ToolCall(Base):
    """One tool invocation the server wants performed.

    `id` is server-minted and is how every later message refers to this call. The client never
    invents one — a client-chosen id could collide with a real call and overwrite its result.

    `idempotency_key` is present only for mutating tools. It is what lets the *device* recognise a
    call it has already performed, which is the second half of the duplicate-calendar-entry defence:
    the server declines to retry, and if a retry somehow arrives anyway the device declines to
    repeat the effect.
    """

    id: str = Field(min_length=8, max_length=64)
    tool: str
    arguments: dict[str, Any] = Field(default_factory=dict)
    idempotency_key: str = ""
    deadline_seconds: int = Field(default=DEFAULT_DEADLINE_SECONDS, gt=0, le=300)


class ToolResult(Base):
    """What came back. Submitted by the client as its own idempotent request, keyed by `call_id`.

    `payload` is untrusted content, always, regardless of which tool produced it (ARCHITECTURE.md
    §5). The server labels its trust from the *dispatched tool's* declaration, never from anything
    in this message — a patched client cannot understate taint because it does not get a vote.
    """

    call_id: str
    status: CallStatus
    payload: dict[str, Any] | None = None
    #: Safe for a log, never for a prompt and never for a user. May contain device error text.
    error: str = ""


class DispatchStep(Base):
    """One wave of calls the server sends at once.

    `parallel=True` means the client may run every call concurrently and submit each result the
    moment it has it — a fast read must not wait behind a slow one. `parallel=False` steps always
    hold exactly one call.
    """

    calls: tuple[ToolCall, ...]
    parallel: bool

    def is_mutating(self) -> bool:
        return not self.parallel


class DispatchError(RuntimeError):
    """A dispatch plan that would be unsafe to execute. Raised before anything is sent."""


def plan(calls: tuple[ToolCall, ...], *, registry: ToolRegistry) -> tuple[DispatchStep, ...]:
    """Turn a model's tool calls into an ordered list of waves.

    Every non-mutating call the model asked for goes into one parallel wave. Every mutating call
    gets its own serial wave afterwards, in the order the model asked for them.

    **Reads go first, together.** That is not just an optimisation — it is also the safer ordering,
    because a mutation informed by fresh reads is better than one informed by stale ones.

    **Mutations are never speculative.** They are dispatched one at a time, and the loop gets to
    look at each result before the next is sent. An agent that fires three writes at once and then
    discovers the first should have stopped it has already done the damage.

    Raises rather than silently reordering if a mutating tool arrives without the idempotency key
    its declaration demands — sending it would put us one dropped packet away from a duplicate.
    """
    reads: list[ToolCall] = []
    writes: list[ToolCall] = []

    for call in calls:
        spec = registry.get(call.tool)
        if spec.mutates:
            if spec.requires_idempotency_key and not call.idempotency_key:
                raise DispatchError(
                    f"{call.tool}: mutating tool dispatched without an idempotency key — a retry "
                    "after a lost acknowledgement would repeat the effect"
                )
            writes.append(call)
        else:
            reads.append(call)

    steps: list[DispatchStep] = []
    if reads:
        steps.append(DispatchStep(calls=tuple(reads), parallel=True))
    steps.extend(DispatchStep(calls=(call,), parallel=False) for call in writes)
    return tuple(steps)


def device_calls(step: DispatchStep, *, registry: ToolRegistry) -> tuple[ToolCall, ...]:
    """The subset of a step that has to cross the network.

    Server-side tools in the same wave run in-process while the device calls are in flight, so a
    turn mixing both costs one round trip rather than two.
    """
    return tuple(c for c in step.calls if registry.get(c.tool).runtime is Runtime.DEVICE)


def retryable(spec: ToolSpec, status: CallStatus) -> bool:
    """Whether a call in this state may be sent again.

    The asymmetry that matters: a read that definitively did not happen is free to repeat, and a
    mutation is never free to repeat unless the tool itself is idempotent. `UNKNOWN` is never
    retryable for anything — by definition we do not know whether it ran, and guessing wrong on a
    write is the failure this whole module exists to prevent.
    """
    if status is CallStatus.UNKNOWN:
        return False
    if status in {CallStatus.DENIED, CallStatus.SUCCEEDED}:
        return False
    if status not in {CallStatus.FAILED, CallStatus.EXPIRED}:
        return False
    return not spec.mutates or spec.idempotent


def status_for_timeout(spec: ToolSpec) -> CallStatus:
    """What a call becomes when its deadline passes with no answer.

    A read cannot have changed anything, so silence means it did not happen: `EXPIRED`, retryable.
    A mutation may have completed on the device with the acknowledgement lost in transit, so silence
    means we genuinely do not know: `UNKNOWN`, terminal.
    """
    return CallStatus.UNKNOWN if spec.mutates and not spec.idempotent else CallStatus.EXPIRED


class StepCollector:
    """Gathers results for one dispatched step and says when it is done.

    Submissions are **idempotent**: a client that loses its connection mid-submit will resend, and
    the first answer for a call wins. Accepting a second answer would let a retry overwrite a real
    result with, say, a timeout — turning a success into a failure because the network hiccuped on
    the way back.
    """

    __slots__ = ("_expected", "_results")

    def __init__(self, step: DispatchStep) -> None:
        self._expected = {call.id for call in step.calls}
        if not self._expected:
            raise DispatchError("a dispatch step must contain at least one call")
        self._results: dict[str, ToolResult] = {}

    def submit(self, result: ToolResult) -> bool:
        """Record a result. Returns True if it was accepted, False if it was a duplicate.

        A result for a call this step never dispatched is rejected outright rather than stored: it
        is either a bug or a client trying to inject a result for something it was never asked to
        do.
        """
        if result.call_id not in self._expected:
            raise DispatchError(f"{result.call_id}: not a call in this step")
        if result.status not in TERMINAL:
            raise DispatchError(f"{result.call_id}: {result.status.value} is not a terminal state")
        if result.call_id in self._results:
            return False
        self._results[result.call_id] = result
        return True

    @property
    def complete(self) -> bool:
        return self._expected == set(self._results)

    @property
    def outstanding(self) -> frozenset[str]:
        return frozenset(self._expected - set(self._results))

    def results(self) -> tuple[ToolResult, ...]:
        """Results in a stable order, so identical turns produce identical prompts."""
        return tuple(sorted(self._results.values(), key=lambda r: r.call_id))

    def expire_outstanding(self, *, registry: ToolRegistry, calls: tuple[ToolCall, ...]) -> None:
        """Close out a step whose deadline passed, giving each missing call the right terminal
        state for its tool. Reads expire; mutations become unknown."""
        by_id = {call.id: call for call in calls}
        for call_id in self.outstanding:
            spec = registry.get(by_id[call_id].tool)
            self._results[call_id] = ToolResult(
                call_id=call_id,
                status=status_for_timeout(spec),
                error="deadline passed with no result",
            )
