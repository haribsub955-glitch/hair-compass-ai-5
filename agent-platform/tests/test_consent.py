"""Consent purposes — the tests that keep the model lawful.

The design pressure these resist is real and commercial: "make free users agree so we can use their
data". Every test below exists because that instinct, implemented directly, produces consent that
is void under PDPL and GDPR — and a void consent is worse than none, because you relied on it.
"""

from __future__ import annotations

import pytest

from agent_core.consent import DEFAULT_PURPOSES, ConsentError, Purpose, PurposeRegistry
from agent_core.plans import DEFAULT_PLANS


def meets(held, *, minimum):
    return DEFAULT_PLANS.meets(held, minimum=minimum)


# --------------------------------------------------------------------------------------------
# The lawfulness properties
# --------------------------------------------------------------------------------------------


def test_optional_purposes_are_optional_for_every_plan() -> None:
    """THE test. A free user and a paid user must be able to decline the same things.

    Making an optional purpose mandatory for one tier is precisely the 'consent not freely given'
    pattern both regimes name.
    """
    for plan_id in ("free", "pro_monthly"):
        for purpose in DEFAULT_PURPOSES.optional_for(plan_id, meets=meets):
            assert not purpose.necessary, f"{purpose.id} is mandatory for {plan_id}"


def test_model_improvement_is_never_required_of_anyone() -> None:
    """The purpose most likely to be quietly promoted to mandatory, because it is the one with
    commercial value. It must stay declinable for free and paid alike."""
    improvement = DEFAULT_PURPOSES.get("model-improvement")
    assert improvement is not None
    assert not improvement.necessary
    assert improvement.min_plan is None  # asked of everyone, required of nobody


def test_a_lapsed_user_is_asked_for_nothing() -> None:
    """Someone whose trial ended can use nothing, so there is nothing to consent to. Asking them
    anyway would be collecting a consent with no purpose behind it."""
    assert DEFAULT_PURPOSES.required_for("free", meets=meets) == ()


def test_subscription_only_removes_the_pay_or_okay_problem_entirely() -> None:
    """With no free tier, nothing is ever traded for consent: everyone pays the same money for the
    same features, and every optional purpose is declinable by everyone."""
    assert not DEFAULT_PLANS.has_free_tier
    for purpose in DEFAULT_PURPOSES.optional_for("pro_monthly", meets=meets):
        assert not purpose.necessary, f"{purpose.id} would be a condition of a paid service"


def test_a_paid_tier_has_a_necessary_purpose_and_that_is_legitimate() -> None:
    """Sending a question to a server-side model in order to get an answer is not a favour the
    user grants — it IS the feature. Declining makes the feature unavailable, not the app."""
    required = DEFAULT_PURPOSES.required_for("pro_monthly", meets=meets)
    assert [p.id for p in required] == ["agent-analysis"]
    assert required[0].withdrawal_disables_feature


def test_memory_sync_is_optional_even_though_it_is_convenient() -> None:
    """The honesty test for `necessary`: if you can imagine shipping the feature with it switched
    off, it is not necessary. The assistant works reading memories from the device."""
    sync = DEFAULT_PURPOSES.get("memory-sync")
    assert sync is not None and not sync.necessary


def test_cross_border_is_its_own_flag_not_folded_into_necessary() -> None:
    """PDPL wants explicit consent for the transfer, separate from the consent to process."""
    for purpose in DEFAULT_PURPOSES:
        if purpose.crosses_border:
            assert "crosses_border" in Purpose.model_fields


def test_a_necessary_purpose_must_be_explained() -> None:
    """A purpose the user cannot decline without losing a feature must at least say what it does.
    An unexplained mandatory purpose is not informed consent."""
    with pytest.raises(ConsentError, match="no description"):
        PurposeRegistry.from_config([{"id": "sneaky", "necessary": True}])


def test_every_purpose_carries_a_policy_version() -> None:
    """A grant against an older version must not carry — otherwise 'they agreed' stops meaning
    anything the moment the wording moves."""
    for purpose in DEFAULT_PURPOSES:
        assert purpose.policy_version


# --------------------------------------------------------------------------------------------
# Registry mechanics
# --------------------------------------------------------------------------------------------


def test_purposes_are_scoped_by_plan_not_by_who_is_paying() -> None:
    free_ids = {p.id for p in DEFAULT_PURPOSES.applicable_to("free", meets=meets)}
    pro_ids = {p.id for p in DEFAULT_PURPOSES.applicable_to("pro_monthly", meets=meets)}
    # The free tier is asked LESS, and only because it does less.
    assert free_ids < pro_ids
    assert "model-improvement" in free_ids  # asked of everyone


def test_adding_a_purpose_is_config() -> None:
    registry = PurposeRegistry.from_config(
        [
            {"id": "a", "description": "d", "necessary": True},
            {"id": "b", "description": "d"},
        ]
    )
    assert len(registry) == 2
    assert [p.id for p in registry.required_for("free", meets=meets)] == ["a"]


def test_duplicate_purposes_are_rejected() -> None:
    with pytest.raises(ConsentError, match="duplicate purpose"):
        PurposeRegistry.from_config([{"id": "a"}, {"id": "a"}])


def test_purposes_are_frozen() -> None:
    from pydantic import ValidationError

    purpose = DEFAULT_PURPOSES.get("model-improvement")
    assert purpose is not None
    with pytest.raises(ValidationError):
        purpose.necessary = True  # type: ignore[misc]
