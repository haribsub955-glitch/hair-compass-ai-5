"""Dispatch invariants. See docs/DISPATCH.md for why each of these exists.

Written as "prove the unsafe thing is blocked". Each test names the failure it prevents, because
the rules here look like arbitrary strictness until you know which bug produced them.
"""

from __future__ import annotations

import pytest

from agent_core.dispatch import (
    CallStatus,
    DispatchError,
    DispatchStep,
    StepCollector,
    ToolCall,
    ToolResult,
    device_calls,
    plan,
    retryable,
    status_for_timeout,
)
from agent_core.tools import Runtime, ToolRegistry, ToolSpec
from agent_server.packs.hair_compass_tools import TOOLS


def _call(tool: str, call_id: str = "", **kw) -> ToolCall:
    return ToolCall(id=call_id or f"call-{tool}"[:64].ljust(8, "0"), tool=tool, **kw)


def _read(name: str) -> ToolSpec:
    return ToolSpec(name=name, description="d", schema={}, runtime=Runtime.DEVICE, effects=("r",))


def _write(name: str, *, idempotent: bool = False) -> ToolSpec:
    return ToolSpec(
        name=name,
        description="d",
        schema={},
        runtime=Runtime.DEVICE,
        effects=("w",),
        mutates=True,
        idempotent=idempotent,
        requires_idempotency_key=not idempotent,
    )


# --------------------------------------------------------------------------------------------
# Planning: reads overlap, mutations do not
# --------------------------------------------------------------------------------------------


def test_independent_reads_become_one_parallel_wave() -> None:
    """The latency decision. Five sequential reads on a phone network is ~2s of pure transit; the
    same five in parallel is ~400ms."""
    calls = tuple(
        _call(name, call_id=f"c{i:08d}")
        for i, name in enumerate(
            ["recall_memory", "read_recent_entries", "read_lab_results", "read_health_signals"]
        )
    )
    steps = plan(calls, registry=TOOLS)
    assert len(steps) == 1
    assert steps[0].parallel
    assert len(steps[0].calls) == 4


def test_each_mutation_gets_its_own_serial_wave() -> None:
    """Concurrent writes interleave unpredictably, and a partial failure leaves a state nobody can
    reconstruct. Serial also means the loop sees each result before the next call goes out."""
    calls = (
        _call("log_entry", call_id="c00000001", idempotency_key="k1"),
        _call("add_calendar_event", call_id="c00000002", idempotency_key="k2"),
    )
    steps = plan(calls, registry=TOOLS)
    assert len(steps) == 2
    assert all(not step.parallel and len(step.calls) == 1 for step in steps)


def test_reads_are_dispatched_before_writes() -> None:
    """Faster, and also more correct: a mutation informed by fresh reads beats one informed by
    stale ones."""
    calls = (
        _call("log_entry", call_id="c00000001", idempotency_key="k1"),
        _call("recall_memory", call_id="c00000002"),
    )
    steps = plan(calls, registry=TOOLS)
    assert steps[0].parallel
    assert steps[0].calls[0].tool == "recall_memory"
    assert steps[1].calls[0].tool == "log_entry"


def test_mutation_order_is_preserved() -> None:
    calls = (
        _call("add_calendar_event", call_id="c00000001", idempotency_key="k1"),
        _call("log_entry", call_id="c00000002", idempotency_key="k2"),
    )
    steps = plan(calls, registry=TOOLS)
    assert [s.calls[0].tool for s in steps] == ["add_calendar_event", "log_entry"]


def test_a_mutation_without_its_idempotency_key_is_never_dispatched() -> None:
    """Sending it would put us one dropped packet away from a duplicate calendar entry. Caught
    before anything reaches the network."""
    with pytest.raises(DispatchError, match="without an idempotency key"):
        plan((_call("add_calendar_event", call_id="c00000001"),), registry=TOOLS)


def test_an_empty_call_list_plans_to_nothing() -> None:
    assert plan((), registry=TOOLS) == ()


def test_server_tools_ride_along_in_the_read_wave() -> None:
    """A turn mixing device reads and server reads costs one round trip, not two — the server tool
    runs in-process while the device calls are in flight."""
    calls = (
        _call("recall_memory", call_id="c00000001"),
        _call("search_evidence", call_id="c00000002"),
    )
    steps = plan(calls, registry=TOOLS)
    assert len(steps) == 1
    crossing = device_calls(steps[0], registry=TOOLS)
    assert [c.tool for c in crossing] == ["recall_memory"]


# --------------------------------------------------------------------------------------------
# The retry asymmetry — the correctness heart
# --------------------------------------------------------------------------------------------


def test_a_timed_out_read_expires_and_may_be_retried() -> None:
    """A read cannot have changed anything, so silence means it did not happen."""
    spec = _read("r")
    assert status_for_timeout(spec) is CallStatus.EXPIRED
    assert retryable(spec, CallStatus.EXPIRED)


def test_a_timed_out_mutation_becomes_unknown_and_is_never_retried() -> None:
    """THE bug this module exists to prevent: the phone added the calendar event, the ACK was lost,
    and a retry gives the user two entries to delete by hand."""
    spec = _write("w")
    assert status_for_timeout(spec) is CallStatus.UNKNOWN
    assert not retryable(spec, CallStatus.UNKNOWN)


def test_an_idempotent_mutation_is_exempt() -> None:
    """Repeating it is harmless by definition — that is what idempotent means."""
    spec = _write("w", idempotent=True)
    assert status_for_timeout(spec) is CallStatus.EXPIRED
    assert retryable(spec, CallStatus.EXPIRED)


def test_unknown_is_never_retryable_for_anything() -> None:
    for spec in (_read("r"), _write("w"), _write("w2", idempotent=True)):
        assert not retryable(spec, CallStatus.UNKNOWN), spec.name


def test_a_denial_is_never_retried() -> None:
    """Retrying an explicit refusal is how an agent nags a user into approving something."""
    assert not retryable(_read("r"), CallStatus.DENIED)


def test_a_definite_failure_is_retryable_for_a_read_but_not_a_write() -> None:
    assert retryable(_read("r"), CallStatus.FAILED)
    assert not retryable(_write("w"), CallStatus.FAILED)


def test_a_success_is_not_retried() -> None:
    assert not retryable(_read("r"), CallStatus.SUCCEEDED)


# --------------------------------------------------------------------------------------------
# Result collection — submissions are themselves retryable
# --------------------------------------------------------------------------------------------


def _step() -> DispatchStep:
    return DispatchStep(
        calls=(_call("recall_memory", "c00000001"), _call("read_lab_results", "c00000002")),
        parallel=True,
    )


def test_the_first_result_for_a_call_wins() -> None:
    """A client that loses its connection mid-submit will resend. Accepting the second answer would
    let a retry overwrite a real success with a timeout — degrading a turn because the network
    hiccuped AFTER the work was done correctly."""
    collector = StepCollector(_step())
    assert collector.submit(
        ToolResult(call_id="c00000001", status=CallStatus.SUCCEEDED, payload={"n": 1})
    )
    assert not collector.submit(ToolResult(call_id="c00000001", status=CallStatus.FAILED))
    assert collector.results()[0].status is CallStatus.SUCCEEDED


def test_a_result_for_a_call_this_step_never_dispatched_is_rejected() -> None:
    """Either a bug or a client injecting a result for something it was never asked to do."""
    collector = StepCollector(_step())
    with pytest.raises(DispatchError, match="not a call in this step"):
        collector.submit(ToolResult(call_id="c99999999", status=CallStatus.SUCCEEDED))


def test_a_non_terminal_status_is_rejected() -> None:
    """`pending` and `dispatched` are server-side bookkeeping. A client reporting one would leave
    the step permanently incomplete."""
    collector = StepCollector(_step())
    with pytest.raises(DispatchError, match="not a terminal state"):
        collector.submit(ToolResult(call_id="c00000001", status=CallStatus.DISPATCHED))


def test_a_step_is_incomplete_until_every_call_answers() -> None:
    collector = StepCollector(_step())
    collector.submit(ToolResult(call_id="c00000001", status=CallStatus.SUCCEEDED))
    assert not collector.complete
    assert collector.outstanding == frozenset({"c00000002"})
    collector.submit(ToolResult(call_id="c00000002", status=CallStatus.FAILED))
    assert collector.complete


def test_results_come_back_in_a_stable_order() -> None:
    """Identical turns must produce identical prompts, or caching and diffing both break."""
    collector = StepCollector(_step())
    collector.submit(ToolResult(call_id="c00000002", status=CallStatus.SUCCEEDED))
    collector.submit(ToolResult(call_id="c00000001", status=CallStatus.SUCCEEDED))
    assert [r.call_id for r in collector.results()] == ["c00000001", "c00000002"]


def test_expiring_a_step_gives_each_missing_call_the_right_terminal_state() -> None:
    """A wave that half-answered: the read expires (retryable), the write becomes unknown."""
    registry = ToolRegistry([_read("r"), _write("w")])
    calls = (_call("r", "c00000001"), _call("w", "c00000002", idempotency_key="k"))
    step = DispatchStep(calls=calls, parallel=True)
    collector = StepCollector(step)
    collector.expire_outstanding(registry=registry, calls=calls)
    by_id = {r.call_id: r.status for r in collector.results()}
    assert by_id["c00000001"] is CallStatus.EXPIRED
    assert by_id["c00000002"] is CallStatus.UNKNOWN
    assert collector.complete


def test_expiring_does_not_overwrite_a_result_that_already_arrived() -> None:
    registry = ToolRegistry([_read("r"), _write("w")])
    calls = (_call("r", "c00000001"), _call("w", "c00000002", idempotency_key="k"))
    collector = StepCollector(DispatchStep(calls=calls, parallel=True))
    collector.submit(ToolResult(call_id="c00000002", status=CallStatus.SUCCEEDED))
    collector.expire_outstanding(registry=registry, calls=calls)
    by_id = {r.call_id: r.status for r in collector.results()}
    assert by_id["c00000002"] is CallStatus.SUCCEEDED


def test_an_empty_step_is_rejected() -> None:
    with pytest.raises(DispatchError, match="at least one call"):
        StepCollector(DispatchStep(calls=(), parallel=True))


# --------------------------------------------------------------------------------------------
# Wire hygiene
# --------------------------------------------------------------------------------------------


def test_a_tool_result_carries_no_authority_fields() -> None:
    """The client reports what happened. It never reports what it was allowed to do — taint and
    tiering come from the dispatched tool's server-side declaration (ARCHITECTURE.md §5)."""
    for forbidden in ("taints", "effects", "entitlement", "tier", "trusted"):
        assert forbidden not in ToolResult.model_fields


def test_deadlines_are_bounded() -> None:
    with pytest.raises(ValueError):
        ToolCall(id="c00000001", tool="recall_memory", deadline_seconds=0)
    with pytest.raises(ValueError):
        ToolCall(id="c00000001", tool="recall_memory", deadline_seconds=301)
