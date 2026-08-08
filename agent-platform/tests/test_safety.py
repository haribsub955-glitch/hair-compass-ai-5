"""The medical-claims boundary. These are the tests that matter most in the repo.

Written as "prove the unsafe thing is blocked", never "prove the safe thing works" — and the metric
that counts is **false accepts**: a permitted claim that should have been denied. A suite that only
measures overall pass rate will look green while leaking exactly the claims this product must not
make (ARCHITECTURE.md §9).
"""

from __future__ import annotations

import re

import pytest

from agent_core.contracts import Claim, ClaimCategory, SafetyDecision
from agent_core.safety import NEVER, SafetyPolicy, TextRule, evaluate
from agent_server.packs.hair_compass import (
    GATE_EFFICACY,
    GATE_HAS_HISTORY,
    OUTCOME_WINDOW_WEEKS,
    SAFETY_POLICY,
    gates_for,
)

ALL_GATES = frozenset({GATE_EFFICACY, GATE_HAS_HISTORY})


def _claim(category: ClaimCategory, *, uncertain: bool = False) -> Claim:
    return Claim(text=f"a {category.value} statement", category=category, uncertain=uncertain)


# --------------------------------------------------------------------------------------------
# Never-permitted claims
# --------------------------------------------------------------------------------------------


def test_diagnosis_is_denied_even_when_every_gate_is_open() -> None:
    """The headline rule. If this ever passes a diagnosis, the product's central promise is broken
    and App Store review has a reason to reject."""
    kept, verdict = evaluate(
        [_claim(ClaimCategory.DIAGNOSIS)], policy=SAFETY_POLICY, gates=ALL_GATES
    )
    assert kept == ()
    assert verdict.decision is SafetyDecision.FALLBACK
    assert "never permitted" in " ".join(verdict.reasons)


def test_diagnosis_cannot_be_unlocked_by_a_fabricated_gate() -> None:
    """A patched client controls the facts, so it controls the gates. It must still not be able to
    invent a gate that opens a NEVER rule."""
    kept, _ = evaluate(
        [_claim(ClaimCategory.DIAGNOSIS)],
        policy=SAFETY_POLICY,
        gates=frozenset({NEVER, GATE_EFFICACY, GATE_HAS_HISTORY, "admin"}),
    )
    assert kept == ()


# --------------------------------------------------------------------------------------------
# Conditional claims
# --------------------------------------------------------------------------------------------


def test_efficacy_is_denied_before_the_judging_window() -> None:
    kept, verdict = evaluate(
        [_claim(ClaimCategory.EFFICACY)], policy=SAFETY_POLICY, gates=frozenset({GATE_HAS_HISTORY})
    )
    assert kept == ()
    assert verdict.decision is SafetyDecision.FALLBACK


def test_efficacy_is_allowed_once_the_window_is_open() -> None:
    kept, verdict = evaluate(
        [_claim(ClaimCategory.EFFICACY)], policy=SAFETY_POLICY, gates=frozenset({GATE_EFFICACY})
    )
    assert len(kept) == 1
    assert verdict.decision is SafetyDecision.ALLOW


def test_trend_needs_history() -> None:
    kept, _ = evaluate([_claim(ClaimCategory.TREND)], policy=SAFETY_POLICY, gates=frozenset())
    assert kept == ()


@pytest.mark.parametrize(
    "category", [ClaimCategory.OBSERVATION, ClaimCategory.EDUCATION, ClaimCategory.ESCALATION]
)
def test_unconditional_categories_survive_with_no_gates(category: ClaimCategory) -> None:
    """Escalation especially: "worth raising with a clinician" must survive every rule, because
    suppressing it is the one failure mode with real-world downside."""
    kept, verdict = evaluate([_claim(category)], policy=SAFETY_POLICY, gates=frozenset())
    assert len(kept) == 1
    assert verdict.decision is SafetyDecision.ALLOW


# --------------------------------------------------------------------------------------------
# Uncertainty and mixed responses
# --------------------------------------------------------------------------------------------


def test_a_claim_the_model_flagged_uncertain_is_dropped() -> None:
    kept, _ = evaluate(
        [_claim(ClaimCategory.OBSERVATION, uncertain=True)],
        policy=SAFETY_POLICY,
        gates=ALL_GATES,
    )
    assert kept == ()


def test_a_mixed_response_is_redacted_not_discarded() -> None:
    """Partial failure must not throw away the good claims — the user still gets their observations,
    just not the impermissible diagnosis."""
    kept, verdict = evaluate(
        [_claim(ClaimCategory.OBSERVATION), _claim(ClaimCategory.DIAGNOSIS)],
        policy=SAFETY_POLICY,
        gates=ALL_GATES,
    )
    assert len(kept) == 1
    assert kept[0].category is ClaimCategory.OBSERVATION
    assert verdict.decision is SafetyDecision.REDACT


def test_an_empty_response_falls_back_rather_than_serving_nothing() -> None:
    kept, verdict = evaluate([], policy=SAFETY_POLICY, gates=ALL_GATES)
    assert kept == ()
    assert verdict.decision is SafetyDecision.FALLBACK


def test_verdict_always_records_the_policy_version() -> None:
    """Two differently-judged responses must be distinguishable in the audit log."""
    _, verdict = evaluate(
        [_claim(ClaimCategory.OBSERVATION)], policy=SAFETY_POLICY, gates=ALL_GATES
    )
    assert verdict.verifier_version == SAFETY_POLICY.version


def test_a_policy_without_a_version_is_rejected_at_construction() -> None:
    with pytest.raises(ValueError):
        SafetyPolicy(version="", requires={})


# --------------------------------------------------------------------------------------------
# Gate derivation from hostile facts — every failure must CLOSE a gate
# --------------------------------------------------------------------------------------------


def test_missing_facts_open_no_gates() -> None:
    assert gates_for({}) == frozenset()


@pytest.mark.parametrize(
    "facts",
    [
        {"entry_count": "many", "treatments": "lots"},
        {"entry_count": None, "treatments": None},
        {"treatments": [{"weeks_elapsed": "99"}]},
        {"treatments": ["not-a-dict"]},
        {"treatments": {"weeks_elapsed": 99}},
        {"entry_count": 3.9, "treatments": [{"weeks_elapsed": 99.9}]},
    ],
)
def test_malformed_or_hostile_facts_never_open_a_gate(facts: dict[str, object]) -> None:
    """Wrong types must fail closed. A client that sends `weeks_elapsed: "99"` as a string is either
    broken or probing; either way it must not unlock efficacy claims."""
    assert gates_for(facts) == frozenset()


def test_history_gate_needs_at_least_three_entries() -> None:
    assert gates_for({"entry_count": 2}) == frozenset()
    assert gates_for({"entry_count": 3}) == frozenset({GATE_HAS_HISTORY})


def test_efficacy_gate_opens_exactly_at_the_window() -> None:
    below = {"treatments": [{"weeks_elapsed": OUTCOME_WINDOW_WEEKS - 1}]}
    at = {"treatments": [{"weeks_elapsed": OUTCOME_WINDOW_WEEKS}]}
    assert GATE_EFFICACY not in gates_for(below)
    assert GATE_EFFICACY in gates_for(at)


# --------------------------------------------------------------------------------------------
# TextRule mechanics — the layer that catches a mis-tagged claim
# --------------------------------------------------------------------------------------------


def test_a_text_rule_denies_regardless_of_the_category_the_model_chose() -> None:
    """The whole point of this layer: a rule that only fired on the tag the model picked would be
    defeated by picking a different tag."""
    rule = TextRule(name="r", pattern=re.compile("forbidden"), reason="test")
    for category in ClaimCategory:
        assert rule.denies(Claim(text="a forbidden thing", category=category))


def test_applies_to_narrows_a_rule_to_specific_categories() -> None:
    rule = TextRule(
        name="r",
        pattern=re.compile("forbidden"),
        reason="test",
        applies_to=frozenset({ClaimCategory.EDUCATION}),
    )
    assert rule.denies(Claim(text="forbidden", category=ClaimCategory.EDUCATION))
    assert not rule.denies(Claim(text="forbidden", category=ClaimCategory.OBSERVATION))


def test_unless_stands_a_rule_down() -> None:
    rule = TextRule(
        name="r",
        pattern=re.compile("biotin"),
        reason="test",
        unless=re.compile("does not"),
    )
    assert rule.denies(Claim(text="biotin helps", category=ClaimCategory.EDUCATION))
    assert not rule.denies(Claim(text="biotin does not help", category=ClaimCategory.EDUCATION))


def test_text_rules_run_before_category_rules() -> None:
    """A claim denied by text is refused for the text reason, not the category reason — so the audit
    log names the rule that actually fired."""
    policy = SafetyPolicy(
        version="t/1",
        requires={},
        text_rules=(TextRule(name="banned", pattern=re.compile("banned"), reason="because"),),
    )
    kept, verdict = evaluate(
        [Claim(text="a banned sentence", category=ClaimCategory.OBSERVATION)],
        policy=policy,
        gates=frozenset(),
    )
    assert kept == ()
    assert "banned: because" in verdict.reasons


def test_a_text_rule_reason_never_quotes_the_claim() -> None:
    """Claim text is model output derived from user data. It belongs in the response, not in an
    audit reason (§9 — metadata-only audit)."""
    kept, verdict = evaluate(
        [Claim(text="Your thinning is androgenetic alopecia.", category=ClaimCategory.EDUCATION)],
        policy=SAFETY_POLICY,
        gates=ALL_GATES,
    )
    assert kept == ()
    assert "thinning" not in " ".join(verdict.reasons)


def test_one_qualifying_treatment_among_many_opens_the_gate() -> None:
    facts = {
        "treatments": [
            {"weeks_elapsed": 2},
            {"weeks_elapsed": OUTCOME_WINDOW_WEEKS + 10},
            {"weeks_elapsed": 5},
        ]
    }
    assert GATE_EFFICACY in gates_for(facts)
