"""Five users, five devices, one process, all at once.

This file exists because the single-device case hides everything that matters. One agent, one phone,
one turn works fine with a design that would corrupt every turn the moment a second user arrives.

Three failures are under test, in descending severity:

1. **Cross-user tool results.** User B's phone answering user A's tool call would put B's lab
   values into A's prompt and A's answer. This is the security property of the whole multi-user
   design.
2. **Crossed device routing.** Each turn's calls must reach *that turn's* phone. Getting this wrong
   does not error — it silently returns the wrong user's data, which is worse.
3. **Shared budgets.** One heavy user must not exhaust everyone else's quota.
"""

from __future__ import annotations

import asyncio

import pytest

from agent_core.contracts import Entitlement, Principal
from agent_core.conversation import ModelTurn, StopReason
from agent_core.dispatch import CallStatus, DispatchStep, ToolCall, ToolResult
from agent_server.adapters.llm.fake import FakeAdapter
from agent_server.agent import Agent
from agent_server.ledger import InMemoryLedger
from agent_server.packs.hair_compass_tools import TOOLS
from agent_server.runs import RemoteDeviceExecutor, RunError, RunRegistry

TOOLSET = ("recall_memory", "read_recent_entries")


def principal(n: int) -> Principal:
    return Principal(
        app_id="hair-compass",
        principal_id=f"p{n}",
        installation_id=f"i{n}",
        data_subject_id=f"d{n}",
        entitlement=Entitlement.PRO,
    )


class IdentifiablePhone:
    """Returns data stamped with its owner, so a crossed result is detectable rather than subtle."""

    def __init__(self, owner: int, delay: float = 0.0) -> None:
        self.owner = owner
        self._delay = delay
        self.seen: list[str] = []

    async def execute(self, step: DispatchStep) -> tuple[ToolResult, ...]:
        if self._delay:
            await asyncio.sleep(self._delay)
        self.seen.extend(c.tool for c in step.calls)
        return tuple(
            ToolResult(
                call_id=c.id,
                status=CallStatus.SUCCEEDED,
                payload={"owner": self.owner, "entries": self.owner * 10},
            )
            for c in step.calls
        )


def agent(ledger: InMemoryLedger) -> Agent:
    return Agent(
        adapter=FakeAdapter().script(
            [
                ModelTurn(
                    stop_reason=StopReason.TOOL_USE,
                    tool_calls=(ToolCall(id="c_0000000001", tool="recall_memory"),),
                ),
                ModelTurn(text="done", stop_reason=StopReason.END_TURN),
            ]
        ),
        registry=TOOLS,
        ledger=ledger,
        server_tools={},
        system_prompt="s",
        max_output_tokens=64,
    )


# --------------------------------------------------------------------------------------------
# Concurrency
# --------------------------------------------------------------------------------------------


async def test_five_users_run_concurrently_without_crossing_devices() -> None:
    """Each turn's tool calls must reach that turn's phone. Staggered delays force the turns to
    genuinely overlap rather than accidentally serialising."""
    ledger = InMemoryLedger(daily_budget=5_000_000)
    shared = agent(ledger)  # ONE agent instance, as in production
    phones = [IdentifiablePhone(owner=n, delay=0.02 * (5 - n)) for n in range(5)]

    results = await asyncio.gather(
        *(
            shared.run(
                principal=principal(n),
                device=phones[n],
                user_text="how am I doing?",
                allowed_tools=TOOLSET,
            )
            for n in range(5)
        )
    )

    assert all(r.served for r in results)
    # Every phone was asked exactly once, and only for its own turn.
    assert [p.seen for p in phones] == [["recall_memory"]] * 5
    for n, result in enumerate(results):
        fed_back = [m for m in result.messages if m.tool_results]
        owners = {r.payload["owner"] for m in fed_back for r in m.tool_results if r.payload}
        assert owners == {n}, f"user {n} saw another user's data: {owners}"


async def test_one_agent_instance_holds_no_per_user_state() -> None:
    """If the agent held a device or a principal, the assertion above would pass by luck. This
    asserts the structural property directly."""
    shared = agent(InMemoryLedger(daily_budget=5_000_000))
    held = {k: v for k, v in vars(shared).items()}
    for name in ("_device", "_principal", "_messages", "_trace", "_run"):
        assert name not in held, f"Agent holds per-turn state: {name}"


async def test_budgets_are_per_user_not_per_process() -> None:
    """A heavy user must not exhaust everyone else's quota."""
    ledger = InMemoryLedger(daily_budget=5_000_000)
    shared = agent(ledger)
    await asyncio.gather(
        *(
            shared.run(
                principal=principal(n),
                device=IdentifiablePhone(owner=n),
                user_text="how am I doing?",
                allowed_tools=TOOLSET,
            )
            for n in range(5)
        )
    )
    spent = [await ledger.spent_today(f"p{n}") for n in range(5)]
    assert all(s > 0 for s in spent)
    assert len(set(spent)) == 1, "identical work should cost each user the same"


async def test_one_user_exhausting_their_quota_does_not_affect_anyone_else() -> None:
    """The isolation that matters: a heavy user hits their own ceiling, nobody else notices."""
    ledger = InMemoryLedger(daily_budget=100_000)
    shared = agent(ledger)
    await ledger.reserve("p0", 100_000)  # p0 has spent their whole day
    results = await asyncio.gather(
        *(
            shared.run(
                principal=principal(n),
                device=IdentifiablePhone(owner=n),
                user_text="how am I doing?",
                allowed_tools=TOOLSET,
            )
            for n in range(3)
        )
    )
    assert results[0].iterations == 0, "p0 should have been stopped by their own budget"
    assert all(r.iterations == 2 for r in results[1:]), "other users were affected"


# --------------------------------------------------------------------------------------------
# Result routing and ownership — the security property
# --------------------------------------------------------------------------------------------


async def test_a_result_is_routed_to_the_run_that_issued_the_call() -> None:
    runs = RunRegistry()
    run_a = await runs.open(principal(1))
    run_b = await runs.open(principal(2))
    step_a = DispatchStep(calls=(ToolCall(id="call_aaaa", tool="recall_memory"),), parallel=True)
    step_b = DispatchStep(calls=(ToolCall(id="call_bbbb", tool="recall_memory"),), parallel=True)
    await runs.begin_step(run_a, step_a)
    await runs.begin_step(run_b, step_b)

    await runs.submit(
        principal=principal(1),
        result=ToolResult(call_id="call_aaaa", status=CallStatus.SUCCEEDED, payload={"who": "a"}),
    )
    assert run_a.collector is not None and run_a.collector.complete
    assert run_b.collector is not None and not run_b.collector.complete


async def test_one_users_phone_cannot_answer_another_users_tool_call() -> None:
    """THE multi-user security test. Without the ownership check, user 2's phone could inject
    fabricated lab values into user 1's prompt and user 1's answer."""
    runs = RunRegistry()
    run = await runs.open(principal(1))
    await runs.begin_step(
        run, DispatchStep(calls=(ToolCall(id="call_aaaa", tool="recall_memory"),), parallel=True)
    )
    with pytest.raises(RunError):
        await runs.submit(
            principal=principal(2),
            result=ToolResult(
                call_id="call_aaaa", status=CallStatus.SUCCEEDED, payload={"ferritin": 999}
            ),
        )
    assert run.collector is not None and not run.collector.complete


async def test_a_principal_from_another_app_cannot_answer_either() -> None:
    """`principal_id` alone is not enough — two apps on one deployment can mint the same id."""
    runs = RunRegistry()
    owner = Principal(
        app_id="hair-compass",
        principal_id="p1",
        installation_id="i1",
        data_subject_id="d1",
        entitlement=Entitlement.PRO,
    )
    impostor = owner.model_copy(update={"app_id": "other-app"})
    run = await runs.open(owner)
    await runs.begin_step(
        run, DispatchStep(calls=(ToolCall(id="call_aaaa", tool="recall_memory"),), parallel=True)
    )
    with pytest.raises(RunError):
        await runs.submit(
            principal=impostor,
            result=ToolResult(call_id="call_aaaa", status=CallStatus.SUCCEEDED),
        )


async def test_an_unknown_call_id_is_refused_without_confirming_whether_it_exists() -> None:
    """Same error for 'never existed' and 'not yours', so a prober learns nothing."""
    runs = RunRegistry()
    run = await runs.open(principal(1))
    await runs.begin_step(
        run, DispatchStep(calls=(ToolCall(id="call_aaaa", tool="recall_memory"),), parallel=True)
    )
    with pytest.raises(RunError, match="no such call"):
        await runs.submit(
            principal=principal(1),
            result=ToolResult(call_id="call_zzzz", status=CallStatus.SUCCEEDED),
        )
    with pytest.raises(RunError, match="no such call"):
        await runs.submit(
            principal=principal(2),
            result=ToolResult(call_id="call_aaaa", status=CallStatus.SUCCEEDED),
        )


async def test_a_duplicate_submission_is_ignored_not_rejected() -> None:
    runs = RunRegistry()
    run = await runs.open(principal(1))
    await runs.begin_step(
        run, DispatchStep(calls=(ToolCall(id="call_aaaa", tool="recall_memory"),), parallel=True)
    )
    result = ToolResult(call_id="call_aaaa", status=CallStatus.SUCCEEDED, payload={"n": 1})
    assert await runs.submit(principal=principal(1), result=result)
    assert not await runs.submit(principal=principal(1), result=result)


async def test_closing_a_run_releases_its_call_ids() -> None:
    """A leaked call id would route the next turn's results into a dead run."""
    runs = RunRegistry()
    run = await runs.open(principal(1))
    await runs.begin_step(
        run, DispatchStep(calls=(ToolCall(id="call_aaaa", tool="recall_memory"),), parallel=True)
    )
    await runs.close(run)
    assert await runs.count() == 0
    with pytest.raises(RunError):
        await runs.submit(
            principal=principal(1),
            result=ToolResult(call_id="call_aaaa", status=CallStatus.SUCCEEDED),
        )


# --------------------------------------------------------------------------------------------
# The remote executor, end to end
# --------------------------------------------------------------------------------------------


async def test_a_remote_device_turn_completes_when_the_phone_answers() -> None:
    runs = RunRegistry()
    run = await runs.open(principal(1))
    executor = RemoteDeviceExecutor(run=run, runs=runs, tools=TOOLS, timeout_seconds=2.0)
    step = DispatchStep(calls=(ToolCall(id="call_aaaa", tool="recall_memory"),), parallel=True)

    # A real client answers with the id the SERVER sent, which is namespaced by run.
    async def phone_answers() -> None:
        await asyncio.sleep(0.01)
        await runs.submit(
            principal=principal(1),
            result=ToolResult(
                call_id=f"{run.id}:call_aaaa", status=CallStatus.SUCCEEDED, payload={"n": 1}
            ),
        )

    results, _ = await asyncio.gather(executor.execute(step), phone_answers())
    assert results[0].status is CallStatus.SUCCEEDED
    # ...and gets the model's original id back, so the provider can match it to its tool_use block.
    assert results[0].call_id == "call_aaaa"


async def test_a_silent_phone_expires_reads_and_marks_mutations_unknown() -> None:
    """The retry asymmetry, surviving the trip through the registry (docs/DISPATCH.md)."""
    runs = RunRegistry()
    run = await runs.open(principal(1))
    executor = RemoteDeviceExecutor(run=run, runs=runs, tools=TOOLS, timeout_seconds=0.05)
    step = DispatchStep(
        calls=(
            ToolCall(id="call_read", tool="recall_memory"),
            ToolCall(id="call_writ", tool="add_calendar_event", idempotency_key="k1"),
        ),
        parallel=True,
    )
    results = {r.call_id: r.status for r in await executor.execute(step)}
    assert results["call_read"] is CallStatus.EXPIRED
    assert results["call_writ"] is CallStatus.UNKNOWN


async def test_concurrent_turns_reusing_the_same_model_call_id_do_not_collide() -> None:
    """Regression: five turns whose model emitted identical call ids. The registry used to let the
    later run silently take ownership, and the earlier four hung to their deadline.

    Reproduced on a real deployment, not in theory — 8x404 then 2x200 in the server log.
    """
    runs = RunRegistry()
    step = DispatchStep(calls=(ToolCall(id="c_read_entries", tool="recall_memory"),), parallel=True)

    async def one(n: int) -> tuple[ToolResult, ...]:
        run = await runs.open(principal(n))
        executor = RemoteDeviceExecutor(run=run, runs=runs, tools=TOOLS, timeout_seconds=2.0)

        async def phone(dispatched: DispatchStep) -> None:
            # Answer with the id the SERVER sent, which is what a real client does.
            await runs.submit(
                principal=principal(n),
                result=ToolResult(
                    call_id=dispatched.calls[0].id,
                    status=CallStatus.SUCCEEDED,
                    payload={"owner": n},
                ),
            )

        executor._on_dispatch = phone
        return await executor.execute(step)

    results = await asyncio.gather(*(one(n) for n in range(5)))
    for n, got in enumerate(results):
        assert got[0].status is CallStatus.SUCCEEDED, f"turn {n} hung"
        assert got[0].payload == {"owner": n}
        # The model's original id comes back, not the namespaced wire id.
        assert got[0].call_id == "c_read_entries"


async def test_a_duplicate_live_call_id_fails_loudly_rather_than_overwriting() -> None:
    """Defence in depth behind the namespacing: if a collision ever reaches the registry it must
    raise, not silently re-point the id at a different run."""
    runs = RunRegistry()
    run_a = await runs.open(principal(1))
    run_b = await runs.open(principal(2))
    step = DispatchStep(calls=(ToolCall(id="same_call", tool="recall_memory"),), parallel=True)
    await runs.begin_step(run_a, step)
    with pytest.raises(RunError, match="already owned"):
        await runs.begin_step(run_b, step)
