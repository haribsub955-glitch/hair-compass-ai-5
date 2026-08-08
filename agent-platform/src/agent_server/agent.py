"""The agent runner — drives `decide()` until the turn ends.

This is the thing that actually *is* the agent. Everything else is scaffolding around it:

    ask the model
      -> it wants tools?  plan the dispatch, run server tools here, ask the device for the rest
      -> feed the results back
      -> ask again
      -> until decide() says stop

Two properties are deliberate and easy to lose in a refactor.

**The runner makes no decisions.** It observes (what the model returned, what the tools said, what
the ledger allows), builds a `LoopState` from those observations, and does what `decide()` says.
Every `if` about whether to continue lives in `agent_core/loop.py`, where it is pure and
exhaustively tested. If a policy question ever appears here, it belongs there.

**Device execution is an interface.** `DeviceExecutor` is how tool calls reach a phone. In tests it
is a fake; in the HTTP server it suspends the turn and waits for the client to submit results. The
runner cannot tell the difference, which is why the same code path serves a laptop on LAN and a
container in production.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable
from uuid import uuid4

from agent_core.contracts import Principal, SafetyDecision, SafetyVerdict, Usage
from agent_core.conversation import Message, ModelTurn, Role, StopReason
from agent_core.dispatch import CallStatus, DispatchStep, ToolCall, ToolResult, device_calls, plan
from agent_core.loop import Decision, Frame, LoopDecision, LoopState, decide
from agent_core.safety import SafetyPolicy, screen_text
from agent_core.scope import ScopePolicy
from agent_core.scope import check as scope_check
from agent_core.tools import Runtime, ToolRegistry
from agent_server.adapters.llm.base import ModelAdapter, ProviderRefusal
from agent_server.audit import AuditEventName, AuditLog, NullAuditLog
from agent_server.core.errors import ProviderUnavailable, QuotaExhausted
from agent_server.ledger import CostLedger


@runtime_checkable
class DeviceExecutor(Protocol):
    """How a dispatch step reaches the phone. One await, however long the round trip takes."""

    async def execute(self, step: DispatchStep) -> tuple[ToolResult, ...]: ...


@runtime_checkable
class ServerToolHandler(Protocol):
    """A tool that runs in-process. Its output is trusted; a device tool's never is."""

    async def __call__(self, call: ToolCall) -> ToolResult: ...


class TurnTrace:
    """What happened, in order — for the log, the audit row, and for a human debugging a bad turn.

    Records shapes and statuses, never payloads. Tool results are the user's personal data and model
    output is derived from it; neither belongs in a trace that gets logged (ARCHITECTURE.md §9).
    """

    def __init__(self) -> None:
        self.steps: list[str] = []

    def add(self, line: str) -> None:
        self.steps.append(line)

    def __str__(self) -> str:
        return "\n".join(self.steps)


class TurnResult:
    def __init__(
        self,
        *,
        text: str,
        usage: Usage,
        decision: LoopDecision,
        iterations: int,
        trace: TurnTrace,
        messages: tuple[Message, ...],
        safety: SafetyVerdict | None = None,
    ) -> None:
        self.text = text
        self.usage = usage
        self.decision = decision
        self.iterations = iterations
        self.trace = trace
        self.messages = messages
        self.safety = safety

    @property
    def served(self) -> bool:
        """False means the app must render its own deterministic result instead.

        Two ways to get there: the loop hard-stopped, or the safety layer stripped everything.
        Both mean the same thing to the client — use your own deterministic summary.
        """
        if self.decision.decision is Decision.HARD_STOP:
            return False
        return not (self.safety and self.safety.decision is SafetyDecision.FALLBACK)


def _frame_for(turn: ModelTurn) -> Frame:
    """Classify a model response by its shape, never by reading its prose."""
    if turn.stop_reason is StopReason.REFUSAL:
        return Frame.REFUSED
    if turn.tool_calls:
        return Frame.TOOL_CALLS
    if turn.stop_reason is StopReason.MAX_TOKENS:
        return Frame.TRUNCATED
    if not turn.text.strip():
        return Frame.EMPTY
    return Frame.FINAL


def _accumulate(total: Usage, delta: Usage) -> Usage:
    return Usage(
        input_tokens=total.input_tokens + delta.input_tokens,
        output_tokens=total.output_tokens + delta.output_tokens,
        cached_input_tokens=total.cached_input_tokens + delta.cached_input_tokens,
        provider=delta.provider or total.provider,
        model=delta.model or total.model,
        price_version=delta.price_version or total.price_version,
    )


class Agent:
    """One configured agent, shared by every user of the process.

    **Nothing per-user or per-turn is held here.** That is what makes one instance safe for
    hundreds of concurrent turns: the adapter, the tool catalogue, the ledger and the policies are
    all read-only configuration, and everything that varies — who is asking, which phone is
    answering, what the conversation is — lives in `run()`'s locals.

    `device` is the one that has to be argued for. It was originally a constructor argument, which
    is subtly and completely wrong: an executor bound to the agent is ONE phone shared by every
    user of the process, so the second concurrent user's tool calls would be sent to the first
    user's device. It belongs on `run()`, per turn, alongside the principal.
    """

    def __init__(
        self,
        *,
        adapter: ModelAdapter,
        registry: ToolRegistry,
        ledger: CostLedger,
        server_tools: dict[str, ServerToolHandler],
        system_prompt: str,
        safety_policy: SafetyPolicy | None = None,
        scope_policy: ScopePolicy | None = None,
        audit: AuditLog | None = None,
        max_output_tokens: int = 1024,
        max_iterations: int | None = None,
    ) -> None:
        self._adapter = adapter
        self._registry = registry
        self._ledger = ledger
        self._server_tools = server_tools
        self._system = system_prompt
        self._safety = safety_policy
        self._scope = scope_policy
        # Defaulted rather than optional so every call site below can emit unconditionally. An
        # `if self._audit is not None` around each one is how half of them end up missing.
        self._audit = audit or NullAuditLog()
        self._max_output = max_output_tokens
        self._max_iterations = max_iterations

    async def run(
        self,
        *,
        principal: Principal,
        device: DeviceExecutor,
        user_text: str,
        allowed_tools: tuple[str, ...],
        images: tuple[tuple[str, str], ...] = (),
        max_output_tokens: int | None = None,
        max_iterations: int | None = None,
    ) -> TurnResult:
        """One turn for one user on one device.

        `principal` is the whole object rather than a bare id, so tenancy travels with the turn:
        the ledger meters against `principal_id`, and anything added later that needs to know which
        app or which data subject this is already has it. Passing only an id was how the app
        boundary got lost on the way in.
        """
        trace = TurnTrace()
        principal_id = principal.principal_id
        # Per-CALL, falling back to the instance defaults. One Agent serves every concurrent turn,
        # so a plan's limits cannot live on the instance — that is why the per-plan caps in the
        # catalogue were being ignored on the streaming path.
        max_output = max_output_tokens or self._max_output
        iteration_cap = max_iterations or self._max_iterations
        # Correlates every event this turn emits. Not the run id: a run can outlive a turn, and the
        # question an audit answers is "what happened in THIS turn".
        turn_id = uuid4().hex[:16]
        self._audit.record(
            AuditEventName.TURN_STARTED,
            principal_id=principal_id,
            device_id=principal.installation_id,
            turn_id=turn_id,
            detail={"app_id": principal.app_id, "tools_offered": len(allowed_tools)},
        )

        # --- scope, before anything costs anything ------------------------------------------
        # Deliberately the first thing that happens: an off-product question must not reserve
        # budget, must not reach the provider, and must not consume a device round trip.
        if self._scope is not None:
            verdict = scope_check(user_text, policy=self._scope)
            if not verdict.in_scope:
                trace.add("[0] out of scope -> refused before any spend")
                # The cheapest event in the system and one of the most useful: a rising rate here
                # is either an abuse attempt or a scope gate that is too tight for real users, and
                # the two are indistinguishable without a count.
                self._audit.record(
                    AuditEventName.SCOPE_REFUSED,
                    principal_id=principal_id,
                    device_id=principal.installation_id,
                    turn_id=turn_id,
                    detail={"reason": "out of scope"},
                )
                return TurnResult(
                    text=verdict.reason,
                    usage=Usage(),
                    decision=LoopDecision(Decision.STOP, "out of scope"),
                    iterations=0,
                    trace=trace,
                    messages=(Message(role=Role.USER, text=user_text, images=images),),
                    safety=SafetyVerdict(
                        decision=SafetyDecision.ALLOW, verifier_version="scope-gate"
                    ),
                )

        # Images ride on the FIRST user message and are not repeated on later ones. Re-sending them
        # each iteration would re-bill the image tokens on every tool round trip, which on a
        # multi-step turn is the difference between one photo and five.
        messages: list[Message] = [Message(role=Role.USER, text=user_text, images=images)]
        tools = tuple(self._registry.get(name) for name in allowed_tools)
        total = Usage()
        iteration = 0
        resume_count = 0
        consecutive_empty = 0
        unknown_result = False
        last_decision = LoopDecision(Decision.FINALIZE, "nothing to do")

        while True:
            # --- money before thinking. Reserve worst-case, settle to actual. -----------------
            worst_case = self._estimate(messages) + max_output
            try:
                reservation = await self._ledger.reserve(principal_id, worst_case)
            except QuotaExhausted:
                state = self._state(
                    Frame.FINAL, iteration, budget_breached=True, resume_count=resume_count
                )
                last_decision = decide(state)
                trace.add(f"[{iteration}] budget -> {last_decision.decision.value}")
                self._audit.record(
                    AuditEventName.QUOTA_EXHAUSTED,
                    principal_id=principal_id,
                    device_id=principal.installation_id,
                    turn_id=turn_id,
                    detail={"requested": worst_case, "iteration": iteration},
                )
                break

            try:
                turn, usage = await self._adapter.converse(
                    system=self._system,
                    messages=tuple(messages),
                    tools=tools,
                    max_output_tokens=max_output,
                )
            except ProviderRefusal:
                await self._ledger.settle(reservation, Usage(input_tokens=worst_case // 2))
                last_decision = decide(self._state(Frame.REFUSED, iteration))
                trace.add(f"[{iteration}] refused -> {last_decision.decision.value}")
                break
            except Exception as exc:
                await self._ledger.release(reservation)
                self._audit.record(
                    AuditEventName.TURN_FAILED,
                    principal_id=principal_id,
                    device_id=principal.installation_id,
                    turn_id=turn_id,
                    # The exception TYPE, never its message: a provider error string can carry the
                    # request that caused it, which is exactly what must not land here.
                    detail={"error": type(exc).__name__, "iteration": iteration},
                )
                raise ProviderUnavailable(str(exc)) from None

            await self._ledger.settle(reservation, usage)
            total = _accumulate(total, usage)
            iteration += 1

            frame = _frame_for(turn)
            consecutive_empty = consecutive_empty + 1 if frame is Frame.EMPTY else 0
            trace.add(
                f"[{iteration}] model -> {frame.value}"
                + (f" ({len(turn.tool_calls)} tool calls)" if turn.tool_calls else "")
                + f"  [{usage.input_tokens}in/{usage.output_tokens}out]"
            )

            state = self._state(
                frame,
                iteration,
                max_iterations=iteration_cap,
                unknown_result=unknown_result,
                resume_count=resume_count,
                consecutive_empty=consecutive_empty,
            )
            last_decision = decide(state)

            if last_decision.decision is Decision.DISPATCH:
                messages.append(
                    Message(role=Role.ASSISTANT, text=turn.text, tool_calls=turn.tool_calls)
                )
                results, unknown_result = await self._dispatch(turn.tool_calls, device, trace)
                messages.append(Message(role=Role.USER, tool_results=results))
                if unknown_result:
                    # Decide here rather than looping, so we do not pay for a model call whose
                    # answer we already know we cannot use. The model would happily narrate "I've
                    # booked it for you" from a result nobody can observe.
                    last_decision = decide(
                        self._state(Frame.TOOL_CALLS, iteration, unknown_result=True)
                    )
                    trace.add(f"    -> {last_decision.decision.value}: {last_decision.reason}")
                    break
                continue

            if last_decision.decision is Decision.CONTINUE:
                if frame is Frame.TRUNCATED:
                    resume_count += 1
                    messages.append(Message(role=Role.ASSISTANT, text=turn.text))
                    messages.append(Message(role=Role.USER, text="Continue."))
                trace.add(f"    -> continue: {last_decision.reason}")
                continue

            messages.append(Message(role=Role.ASSISTANT, text=turn.text))
            trace.add(f"    -> {last_decision.decision.value}: {last_decision.reason}")
            break

        text = next((m.text for m in reversed(messages) if m.role is Role.ASSISTANT and m.text), "")
        if last_decision.decision is Decision.HARD_STOP:
            text = ""

        # --- the guardrail, applied to whatever the model actually produced ------------------
        # The last thing that happens before an answer leaves. The system prompt *asks* the model
        # not to diagnose, not to push a myth and not to recommend starting a prescription;
        # this is what makes it so. It runs on every path that serves text.
        safety: SafetyVerdict | None = None
        if self._safety is not None and text:
            text, safety = screen_text(text, policy=self._safety)
            if safety.decision is not SafetyDecision.ALLOW:
                trace.add(f"    safety -> {safety.decision.value}: {'; '.join(safety.reasons)}")
                # Rule ids, not the text they matched. Knowing WHICH rule fired is what makes a
                # false-positive report actionable; the sentence itself is the user's data.
                self._audit.record(
                    AuditEventName.SAFETY_BLOCKED,
                    principal_id=principal_id,
                    device_id=principal.installation_id,
                    turn_id=turn_id,
                    detail={
                        "decision": safety.decision.value,
                        "rules": len(safety.reasons),
                        "verifier": safety.verifier_version,
                    },
                )

        self._audit.record(
            AuditEventName.TURN_COMPLETED,
            principal_id=principal_id,
            device_id=principal.installation_id,
            turn_id=turn_id,
            detail={
                "decision": last_decision.decision.value,
                "iterations": iteration,
                "input_tokens": total.input_tokens,
                "output_tokens": total.output_tokens,
                "answered": bool(text),
            },
        )
        return TurnResult(
            text=text,
            usage=total,
            decision=last_decision,
            iterations=iteration,
            trace=trace,
            messages=tuple(messages),
            safety=safety,
        )

    # -----------------------------------------------------------------------------------------

    def _state(self, frame: Frame, iteration: int, **kw) -> LoopState:
        cap = kw.pop("max_iterations", None) or self._max_iterations
        base = {"max_iterations": cap} if cap else {}
        return LoopState(frame=frame, iteration=iteration, **base, **kw)

    async def _dispatch(
        self, calls: tuple[ToolCall, ...], device: DeviceExecutor, trace: TurnTrace
    ) -> tuple[tuple[ToolResult, ...], bool]:
        """Run every call the model asked for, wave by wave.

        Reads go out together; each mutation gets its own wave (docs/DISPATCH.md). Server tools run
        in-process while the device calls for the same wave are in flight, so a mixed wave costs one
        round trip rather than two.
        """
        collected: list[ToolResult] = []
        unknown = False

        for step in plan(calls, registry=self._registry):
            crossing = device_calls(step, registry=self._registry)
            local = tuple(c for c in step.calls if c not in crossing)
            kind = "parallel" if step.parallel else "serial"
            trace.add(
                f"    dispatch {kind}: {len(local)} server + {len(crossing)} device"
                + (f"  ({', '.join(c.tool for c in step.calls)})" if step.calls else "")
            )

            for call in local:
                handler = self._server_tools.get(call.tool)
                if handler is None:
                    collected.append(
                        ToolResult(
                            call_id=call.id,
                            status=CallStatus.FAILED,
                            error=f"no server handler for {call.tool}",
                        )
                    )
                    continue
                collected.append(await handler(call))

            if crossing:
                device_step = DispatchStep(calls=crossing, parallel=step.parallel)
                results = await device.execute(device_step)
                collected.extend(results)
                if any(r.status is CallStatus.UNKNOWN for r in results):
                    unknown = True
                    trace.add("    !! a device action's outcome is unknown — stopping")
                    break

        return tuple(collected), unknown

    def _estimate(self, messages: list[Message]) -> int:
        """Rough token count for the reservation. Over-estimating is safe (it is refunded on
        settle); under-estimating lets concurrent turns slip past the cap, so this rounds up."""
        chars = len(self._system) + sum(
            len(m.text)
            + sum(len(str(c.arguments)) for c in m.tool_calls)
            + sum(len(str(r.payload)) for r in m.tool_results if r.payload)
            for m in messages
        )
        return chars // 3


def new_call_id() -> str:
    return f"c_{uuid4().hex[:16]}"


__all__ = [
    "Agent",
    "DeviceExecutor",
    "Runtime",
    "ServerToolHandler",
    "TurnResult",
    "TurnTrace",
    "new_call_id",
]
