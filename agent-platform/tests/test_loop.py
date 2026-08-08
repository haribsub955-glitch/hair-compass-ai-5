"""The loop's decision function. Pure, so it can be tested exhaustively.

Order is the property under test as much as any individual outcome: safety terminals must dominate
whatever the model wanted. Most of these are "the model asked for X, but Y was true, so Y wins".
"""

from __future__ import annotations

import pytest

from agent_core.loop import (
    DEFAULT_MAX_ITERATIONS,
    MAX_EMPTY,
    MAX_RESUMES,
    Decision,
    Frame,
    LoopState,
    decide,
)


def d(**kw) -> Decision:
    return decide(LoopState(**{"frame": Frame.FINAL, **kw})).decision


# --------------------------------------------------------------------------------------------
# Terminals dominate
# --------------------------------------------------------------------------------------------


@pytest.mark.parametrize("frame", list(Frame))
def test_cancellation_beats_everything(frame: Frame) -> None:
    assert d(frame=frame, cancelled=True) is Decision.HARD_STOP


@pytest.mark.parametrize("frame", list(Frame))
def test_an_unknown_device_outcome_beats_everything_except_cancellation(frame: Frame) -> None:
    """The model may be mid-sentence about how well the booking went. It does not get to continue
    from a state nobody can observe (docs/DISPATCH.md)."""
    assert d(frame=frame, unknown_result=True) is Decision.HARD_STOP


def test_a_refusal_hard_stops() -> None:
    assert d(frame=Frame.REFUSED) is Decision.HARD_STOP


def test_a_refusal_is_not_retried_by_continuing() -> None:
    assert d(frame=Frame.REFUSED, consecutive_empty=0) is not Decision.CONTINUE


@pytest.mark.parametrize("frame", [Frame.TOOL_CALLS, Frame.FINAL, Frame.TRUNCATED])
def test_a_budget_breach_stops_but_still_serves(frame: Frame) -> None:
    """STOP, not HARD_STOP — we already paid for what we have, so the user gets it."""
    assert d(frame=frame, budget_breached=True) is Decision.STOP


def test_the_iteration_cap_stops_a_runaway() -> None:
    assert d(frame=Frame.TOOL_CALLS, iteration=DEFAULT_MAX_ITERATIONS) is Decision.STOP


def test_a_custom_iteration_cap_is_honoured() -> None:
    assert d(frame=Frame.TOOL_CALLS, iteration=2, max_iterations=2) is Decision.STOP
    assert d(frame=Frame.TOOL_CALLS, iteration=1, max_iterations=2) is Decision.DISPATCH


def test_terminal_precedence_is_fixed() -> None:
    """All four true at once: cancellation wins, because it is the user's explicit instruction."""
    assert (
        d(
            frame=Frame.TOOL_CALLS,
            cancelled=True,
            unknown_result=True,
            budget_breached=True,
            iteration=99,
        )
        is Decision.HARD_STOP
    )
    assert (
        decide(LoopState(frame=Frame.TOOL_CALLS, cancelled=True, budget_breached=True)).reason
        == "cancelled"
    )


# --------------------------------------------------------------------------------------------
# Ordinary flow
# --------------------------------------------------------------------------------------------


def test_tool_calls_dispatch() -> None:
    assert d(frame=Frame.TOOL_CALLS) is Decision.DISPATCH


def test_a_final_answer_that_passes_the_gate_finalizes() -> None:
    assert d(frame=Frame.FINAL, gate_passed=True) is Decision.FINALIZE


def test_a_final_answer_that_fails_the_gate_continues() -> None:
    """The model thinks it is done; the gate decides whether it is."""
    assert d(frame=Frame.FINAL, gate_passed=False) is Decision.CONTINUE


def test_a_failing_gate_with_no_room_left_stops_rather_than_serving() -> None:
    assert (
        d(frame=Frame.FINAL, gate_passed=False, iteration=DEFAULT_MAX_ITERATIONS - 1)
        is Decision.STOP
    )


# --------------------------------------------------------------------------------------------
# Truncation and emptiness are bounded
# --------------------------------------------------------------------------------------------


def test_a_truncated_response_is_continued() -> None:
    assert d(frame=Frame.TRUNCATED, resume_count=0) is Decision.CONTINUE


def test_repeated_truncation_gives_up_and_serves_what_it_has() -> None:
    """A model that keeps hitting the ceiling is producing something too long to be useful, and
    each continuation costs money."""
    assert d(frame=Frame.TRUNCATED, resume_count=MAX_RESUMES) is Decision.STOP


def test_one_empty_response_is_retried() -> None:
    assert d(frame=Frame.EMPTY, consecutive_empty=1) is Decision.CONTINUE


def test_repeated_empty_responses_hard_stop() -> None:
    """One is a hiccup; two is a pattern, and there is nothing to serve."""
    assert d(frame=Frame.EMPTY, consecutive_empty=MAX_EMPTY) is Decision.HARD_STOP


# --------------------------------------------------------------------------------------------
# Purity
# --------------------------------------------------------------------------------------------


def test_the_same_state_always_produces_the_same_decision() -> None:
    state = LoopState(frame=Frame.TOOL_CALLS, iteration=3)
    assert {decide(state).decision for _ in range(50)} == {Decision.DISPATCH}


def test_every_decision_carries_a_reason_safe_to_log() -> None:
    """Reasons are shown to users and written to logs, so none may contain model output."""
    for frame in Frame:
        for flags in ({}, {"cancelled": True}, {"budget_breached": True}, {"unknown_result": True}):
            result = decide(LoopState(frame=frame, **flags))
            assert result.reason and len(result.reason) < 120


def test_state_is_frozen() -> None:
    state = LoopState(frame=Frame.FINAL)
    with pytest.raises(AttributeError):
        state.frame = Frame.EMPTY  # type: ignore[misc]
