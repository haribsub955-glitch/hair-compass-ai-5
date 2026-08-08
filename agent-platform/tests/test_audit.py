"""The audit log, and the two things it must never do: leak content, or fail a turn.

The screening tests carry the weight. An audit log that records what was said is not an audit log,
it is a second copy of the personal data with a longer retention than the original — and the rule
was a docstring until this module made it a function.
"""

from __future__ import annotations

import asyncio

import pytest

from agent_core.conversation import ModelTurn, StopReason
from agent_server.audit import (
    MAX_DETAIL_KEYS,
    MAX_VALUE_CHARS,
    REDACTED,
    AuditEventName,
    NullAuditLog,
    PostgresAuditLog,
    _screen,
)

# --------------------------------------------------------------------------------------------
# Screening — metadata in, content out
# --------------------------------------------------------------------------------------------


def test_a_sentence_never_reaches_the_audit_table() -> None:
    """The exact failure this exists to prevent: a well-meaning call site passing the user's
    question, or the model's answer, as a 'reason'."""
    screened = _screen(
        {
            "reason": "The user asked whether their receding hairline is androgenetic alopecia",
            "answer": "Based on your photos I would say this looks like a Norwood 3 pattern",
        }
    )
    assert screened == {"reason": REDACTED, "answer": REDACTED}


def test_identifiers_versions_and_enums_pass_through() -> None:
    """Screening that rejects everything is as useless as screening that rejects nothing — the
    log has to still answer 'what happened'."""
    screened = _screen(
        {
            "decision": "finalize",
            "tool": "read_entries",
            "policy_version": "1.0",
            "plan": "trial",
            "verifier": "hair-safety-3",
            "sha": "a3f9c2e18b40",
        }
    )
    assert REDACTED not in screened.values()
    assert screened["decision"] == "finalize"


def test_numbers_and_flags_are_never_touched() -> None:
    screened = _screen({"input_tokens": 15234, "iterations": 3, "answered": True, "cost": 0.42})
    assert screened == {"input_tokens": 15234, "iterations": 3, "answered": True, "cost": 0.42}


def test_our_own_decision_phrases_survive_but_arbitrary_prose_does_not() -> None:
    """`out of scope` is ours and is worth recording. Anything prose-shaped that is NOT on the
    allow-list is the user's or the model's, and cannot be told apart from content."""
    assert _screen({"reason": "out of scope"})["reason"] == "out of scope"
    assert _screen({"reason": "out of scope entirely, sorry"})["reason"] == REDACTED


def test_a_long_identifier_is_refused_even_without_spaces() -> None:
    """A base64 payload has no spaces. Length is the other half of the screen."""
    assert _screen({"blob": "x" * (MAX_VALUE_CHARS + 1)})["blob"] == REDACTED


def test_nested_structures_are_refused_outright() -> None:
    """A nested dict is how an entire request body ends up in an audit row. No legitimate audit
    fact needs one, so this is refused rather than walked."""
    assert _screen({"envelope": {"entries": [1, 2, 3]}})["envelope"] == REDACTED
    assert _screen({"photos": ["a.jpg", "b.jpg"]})["photos"] == REDACTED


def test_a_refused_value_keeps_its_key() -> None:
    """'There was a rejected field here' is information. A missing key is indistinguishable from a
    call site that never set it."""
    assert "reason" in _screen({"reason": "a whole sentence about something"})


def test_too_many_keys_is_truncated_visibly() -> None:
    screened = _screen({f"k{i}": i for i in range(MAX_DETAIL_KEYS + 5)})
    assert screened["_truncated"] == 5


# --------------------------------------------------------------------------------------------
# The writer — never fatal, never silently empty
# --------------------------------------------------------------------------------------------


class _ExplodingSessions:
    """A database that refuses every write. The realistic outage: connections exhausted, disk full,
    or the audit table dropped by a bad migration."""

    def __call__(self):
        raise RuntimeError("database is down")


async def test_a_dead_database_does_not_raise_into_the_caller() -> None:
    audit = PostgresAuditLog(_ExplodingSessions())
    audit.start()
    audit.record(AuditEventName.TURN_COMPLETED, principal_id="p1", detail={"iterations": 2})
    await audit._queue.join()
    assert audit.dropped == 1
    assert audit.written == 0
    await audit.stop()


async def test_a_full_queue_drops_and_counts_rather_than_growing_without_bound() -> None:
    """An unbounded queue in front of a stalled consumer is a memory leak with extra steps. The
    counter is what stops the drop being silent."""
    audit = PostgresAuditLog(_ExplodingSessions())
    # No drainer started, so nothing is consumed.
    for _ in range(audit._queue.maxsize + 5):
        audit.record(AuditEventName.TURN_STARTED, principal_id="p1")
    assert audit.dropped == 5


def test_recording_is_synchronous_so_a_failure_path_can_audit_itself() -> None:
    """`record` is deliberately not async. An `await` inside an `except` block is one more thing
    that can fail while handling a failure."""
    audit = NullAuditLog()
    assert not asyncio.iscoroutinefunction(audit.record)
    audit.record(AuditEventName.TURN_FAILED, principal_id="p1", detail={"error": "TimeoutError"})
    assert audit.events[0][0] == AuditEventName.TURN_FAILED


def test_the_event_vocabulary_is_not_free_text() -> None:
    """String literals at call sites drift — `turn.complete` here, `turn_completed` there — and a
    query answering 'how many turns failed' then misses half of them."""
    names = [v for k, v in vars(AuditEventName).items() if k.isupper()]
    assert len(names) == len(set(names))
    assert all("." in name for name in names)


# --------------------------------------------------------------------------------------------
# Call sites — the events a turn must leave behind
# --------------------------------------------------------------------------------------------


@pytest.fixture
def audit() -> NullAuditLog:
    return NullAuditLog()


async def test_a_turn_records_start_and_completion(audit) -> None:
    from tests.test_agent import P1, FakeAdapter, Phone, _agent

    adapter = FakeAdapter().script([ModelTurn(text="Doing fine.", stop_reason=StopReason.END_TURN)])
    await _agent(adapter, audit=audit).run(
        principal=P1, device=Phone(), user_text="how am I doing?", allowed_tools=()
    )
    events = [name for name, _ in audit.events]
    assert AuditEventName.TURN_STARTED in events
    assert AuditEventName.TURN_COMPLETED in events


async def test_a_completed_turn_records_the_numbers_and_none_of_the_words(audit) -> None:
    """Token counts and a decision answer 'what did this cost and why did it stop'. The answer
    itself is the user's data and belongs only in the response."""
    from tests.test_agent import P1, FakeAdapter, Phone, _agent

    secret = "Your hairline suggests a Norwood 3 pattern"
    adapter = FakeAdapter().script([ModelTurn(text=secret, stop_reason=StopReason.END_TURN)])
    await _agent(adapter, audit=audit).run(
        principal=P1, device=Phone(), user_text="what do you see?", allowed_tools=()
    )
    completed = dict(audit.events)[AuditEventName.TURN_COMPLETED]
    assert completed["answered"] is True
    assert isinstance(completed["output_tokens"], int)
    assert "Norwood" not in str(audit.events)


async def test_an_out_of_scope_question_is_recorded_without_the_question(audit) -> None:
    """The rate of this event is the only way to tell an abuse attempt from a scope gate that is
    too tight for real users — and neither reason justifies storing what they asked."""
    from tests.test_agent import P1, FakeAdapter, Phone, _agent

    from agent_server.packs import hair_compass as pack

    policy = pack.SCOPE_POLICY
    adapter = FakeAdapter().script(
        [ModelTurn(text="never reached", stop_reason=StopReason.END_TURN)]
    )
    await _agent(adapter, audit=audit, scope_policy=policy).run(
        principal=P1,
        device=Phone(),
        user_text="What is the capital of France?",
        allowed_tools=(),
    )
    recorded = dict(audit.events).get(AuditEventName.SCOPE_REFUSED)
    assert recorded is not None
    assert "France" not in str(audit.events)
