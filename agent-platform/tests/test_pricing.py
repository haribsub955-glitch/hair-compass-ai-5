"""The payment scheme: 3 days free → 14-day trial → monthly, switchable to yearly.

The three periods are three different mechanisms and the tests are mostly about not conflating
them:

* **3 days free** is OURS. StoreKit allows one introductory offer per subscription group per Apple
  ID, and the 14-day trial is it — so this runs on the server's clock, before any payment method
  exists, and is therefore farmable by reinstalling.
* **14 days** is Apple's introductory offer. Apple owns eligibility, which is what makes it
  reinstall-proof where the taster is not.
* **monthly and yearly** are two products in one subscription group. Switching between them is an
  Apple crossgrade, not an upgrade through tiers.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from agent_core.contracts import Entitlement, Principal
from agent_core.plans import DEFAULT_PLANS, FREE_PLAN_ID, TOKENS_PER_TURN
from agent_server.auth import VerifyingPrincipalSource
from agent_server.billing import FakeVerifier, PlanResolver

MONTHLY = "harib.haircompass.pro.monthly"
YEARLY = "harib.haircompass.pro.yearly"


# --------------------------------------------------------------------------------------------
# The shape of the catalogue
# --------------------------------------------------------------------------------------------


def test_the_three_periods_are_three_distinct_plans() -> None:
    taster, trial = DEFAULT_PLANS.get("taster"), DEFAULT_PLANS.get("trial")
    assert taster.available_for_days == 3
    assert taster.granted_without_receipt
    assert trial.trial_days == 14
    # The trial is Apple's, so it is NOT granted without a receipt — that distinction is the whole
    # reason there are two of them.
    assert not trial.granted_without_receipt


def test_the_trial_converts_to_monthly_and_also_covers_yearly() -> None:
    """One Apple introductory offer covers a whole subscription group. A single destination could
    not express "converts to monthly, and the same person may switch to yearly"."""
    assert DEFAULT_PLANS.trial_for("pro_monthly").id == "trial"
    assert DEFAULT_PLANS.trial_for("pro_yearly").id == "trial"


def test_monthly_and_yearly_are_the_same_product_at_two_prices() -> None:
    """A yearly plan that also bought more capability would be two changes at once, and the one
    people want is the discount. Metering them differently short-changes the monthly subscriber."""
    monthly, yearly = DEFAULT_PLANS.get("pro_monthly"), DEFAULT_PLANS.get("pro_yearly")
    assert monthly.daily_token_budget == yearly.daily_token_budget
    assert monthly.features == yearly.features
    assert monthly.max_strategy == yearly.max_strategy
    assert monthly.subscription_group == yearly.subscription_group == "pro"


def test_the_group_is_ordered_with_monthly_first() -> None:
    """The paywall pre-selects the first one, and a paywall that pre-selects the bigger commitment
    reads as a trick."""
    assert [p.id for p in DEFAULT_PLANS.group("pro")] == ["pro_monthly", "pro_yearly"]


def test_each_product_maps_to_exactly_one_plan() -> None:
    assert DEFAULT_PLANS.for_product(MONTHLY).id == "pro_monthly"
    assert DEFAULT_PLANS.for_product(YEARLY).id == "pro_yearly"
    assert DEFAULT_PLANS.for_product("something.else") is None


def test_the_ladder_ranks_in_the_order_someone_moves_through_it() -> None:
    ids = [p.id for p in DEFAULT_PLANS]
    assert ids == [FREE_PLAN_ID, "taster", "trial", "pro_monthly", "pro_yearly"]
    assert DEFAULT_PLANS.meets("taster", minimum="taster")
    assert not DEFAULT_PLANS.meets("taster", minimum="trial")
    # A yearly subscriber satisfies anything gated on monthly. Otherwise paying MORE would unlock
    # less, which is the kind of bug a rank comparison exists to make impossible.
    assert DEFAULT_PLANS.meets("pro_yearly", minimum="pro_monthly")


# --------------------------------------------------------------------------------------------
# Budgets — the numbers that decide whether this loses money
# --------------------------------------------------------------------------------------------


def test_the_taster_is_small_because_it_is_farmable() -> None:
    """Nothing stable exists to key it to before a receipt: the principal id comes from the
    installation id, which changes on reinstall. The defence is the size of the prize."""
    taster = DEFAULT_PLANS.get("taster")
    assert taster.approximate_turns() == 5
    assert taster.total_token_budget == 5 * TOKENS_PER_TURN
    # Spendable in one sitting on day one, which is what a curious new user actually does.
    assert taster.daily_token_budget == 2 * TOKENS_PER_TURN


def test_the_trial_is_bounded_by_its_total_not_only_its_week() -> None:
    """A weekly cap alone does not bound a 14-day trial — two windows would be 28 turns. The total
    is what caps the exposure."""
    trial = DEFAULT_PLANS.get("trial")
    assert trial.budget_window_days == 7
    two_windows = 2 * trial.daily_token_budget
    assert trial.total_token_budget < two_windows
    assert trial.approximate_turns() == 19


def test_total_exposure_rises_with_commitment() -> None:
    """The right axis is TOTAL, not per-day.

    The taster needs no payment method at all, so it is the one an attacker reaches first and the
    one whose worst case must be smallest — about $0.45 against the trial's $1.70. Per-day rates
    are deliberately the SAME (2 turns a day either side), so the app does not feel meaner the
    moment someone hands over a card; what the trial buys is runway, not speed.
    """
    taster, trial = DEFAULT_PLANS.get("taster"), DEFAULT_PLANS.get("trial")
    assert taster.total_token_budget < trial.total_token_budget

    per_day = lambda plan: plan.daily_token_budget / plan.budget_window_days  # noqa: E731
    assert per_day(trial) >= per_day(taster)
    # And a paying subscriber gets more per day than either, or paying buys nothing.
    assert per_day(DEFAULT_PLANS.get("pro_monthly")) > per_day(trial)


def test_a_paid_plan_has_no_lifetime_cap() -> None:
    """A renewing subscription has no lifetime to budget — only a time-limited plan does."""
    for plan_id in ("pro_monthly", "pro_yearly"):
        assert not DEFAULT_PLANS.get(plan_id).has_total_cap
    for plan_id in ("taster", "trial"):
        assert DEFAULT_PLANS.get(plan_id).has_total_cap


# --------------------------------------------------------------------------------------------
# Granting the taster
# --------------------------------------------------------------------------------------------


class FakeIdentity:
    """Records what `register`/`set_plan` were told, and answers `standing`."""

    def __init__(self, *, created_at=None, has_subscribed: bool = False) -> None:
        self.created_at = created_at
        self.has_subscribed = has_subscribed
        self.plans: list[str] = []

    async def register(self, principal) -> None: ...

    async def set_plan(self, principal_id, *, plan_id, subscription_txn_id=None) -> bool:
        self.plans.append(plan_id)
        return True

    async def standing(self, principal_id):
        return self.created_at, self.has_subscribed


def _source(identity=None, *, in_trial: bool = False) -> VerifyingPrincipalSource:
    return VerifyingPrincipalSource(
        secret="s" * 40,
        plans=PlanResolver(DEFAULT_PLANS, FakeVerifier(in_trial=in_trial)),
        catalogue=DEFAULT_PLANS,
        identity=identity,
    )


async def _plan_for(identity, *, token: str = "") -> str:
    await _source(identity).principal_for(
        app_id="hair-compass", installation_id="dev-1", subscription_token=token
    )
    return identity.plans[-1]


async def test_a_brand_new_install_gets_the_taster_without_any_receipt() -> None:
    identity = FakeIdentity(created_at=None)  # no row yet: this is first contact
    assert await _plan_for(identity) == "taster"


async def test_the_taster_still_applies_on_day_two() -> None:
    identity = FakeIdentity(created_at=datetime.now(UTC) - timedelta(days=2))
    assert await _plan_for(identity) == "taster"


async def test_the_taster_expires_after_three_days() -> None:
    identity = FakeIdentity(created_at=datetime.now(UTC) - timedelta(days=3, hours=1))
    assert await _plan_for(identity) == FREE_PLAN_ID


async def test_a_lapsed_subscriber_does_not_get_the_free_days_again() -> None:
    """The condition that is easy to forget. Without it, someone whose card fails is handed the
    introductory freebie on every session for as long as they keep not paying."""
    identity = FakeIdentity(created_at=datetime.now(UTC), has_subscribed=True)
    assert await _plan_for(identity) == FREE_PLAN_ID


async def test_a_valid_receipt_beats_the_taster() -> None:
    """Someone who subscribed on day one gets what they paid for, not the free period."""
    identity = FakeIdentity(created_at=datetime.now(UTC))
    assert await _plan_for(identity, token=f"{MONTHLY}:txn-1") == "pro_monthly"


async def test_apples_trial_flag_wins_over_both() -> None:
    identity = FakeIdentity(created_at=datetime.now(UTC))
    await _source(identity, in_trial=True).principal_for(
        app_id="hair-compass", installation_id="dev-1", subscription_token=f"{MONTHLY}:txn-2"
    )
    assert identity.plans[-1] == "trial"


async def test_a_yearly_receipt_resolves_to_the_yearly_plan() -> None:
    identity = FakeIdentity(created_at=datetime.now(UTC))
    assert await _plan_for(identity, token=f"{YEARLY}:txn-3") == "pro_yearly"


async def test_switching_monthly_to_yearly_keeps_the_same_subscription() -> None:
    """An Apple crossgrade keeps the original transaction id and changes the product, which is why
    the uniqueness constraint is on the transaction and not the product."""
    identity = FakeIdentity(created_at=datetime.now(UTC))
    source = _source(identity)
    for product in (MONTHLY, YEARLY):
        await source.principal_for(
            app_id="hair-compass", installation_id="dev-1", subscription_token=f"{product}:same-txn"
        )
    assert identity.plans == ["pro_monthly", "pro_yearly"]


async def test_no_store_grants_no_taster() -> None:
    """A taster that cannot be timed is a taster that never expires."""
    principal = await _source(None).principal_for(
        app_id="hair-compass", installation_id="dev-1", subscription_token=""
    )
    assert principal.entitlement is Entitlement.FREE


# --------------------------------------------------------------------------------------------
# What the paywall is told
# --------------------------------------------------------------------------------------------


def test_the_offer_names_both_products_and_both_free_periods() -> None:
    from agent_server.api import _offer

    offer = _offer()
    assert offer["free_days"] == 3
    assert offer["trial_days"] == 14
    assert offer["default_product"] == MONTHLY
    assert [p["id"] for p in offer["products"]] == [MONTHLY, YEARLY]


def test_the_offer_carries_no_prices() -> None:
    """App Store Connect is the only thing that knows what a given user in a given country actually
    pays. A second copy server-side means one of them is wrong, usually the one on screen."""
    from agent_server.api import _offer

    assert not any("price" in key for key in _offer())
    assert not any("price" in key for product in _offer()["products"] for key in product)


@pytest.mark.parametrize("plan_id", ["taster", "trial", "pro_monthly", "pro_yearly"])
def test_every_plan_that_can_run_the_agent_can_consent_to_it(plan_id) -> None:
    """A free period that grants access to a product the user cannot lawfully be asked about is
    not a free period, it is a compliance gap."""
    from agent_core.consent import DEFAULT_PURPOSES

    applicable = DEFAULT_PURPOSES.applicable_to(plan_id, meets=DEFAULT_PLANS.meets)
    assert any(p.id == "agent-analysis" for p in applicable), plan_id


# --------------------------------------------------------------------------------------------
# Named testers — the narrow tool for the job the blunt flag was doing
# --------------------------------------------------------------------------------------------


def _settings(**kw):
    from agent_server.core.config import Settings

    base = {
        "database_url": "postgresql+asyncpg://a:b@db:5432/x",
        "secret_key": "k" * 32,
    }
    return Settings(**{**base, **kw})


def test_tester_grants_parse_to_a_plan_per_installation() -> None:
    config = _settings(tester_grants="dev-abc=pro_monthly, dev-def=trial")
    assert config.testers == {"dev-abc": "pro_monthly", "dev-def": "trial"}


def test_a_malformed_pair_costs_that_tester_their_access_not_the_deployment() -> None:
    """A typo in a tester list should not stop the server from starting."""
    assert _settings(tester_grants="dev-abc=pro_monthly,garbage,=x,y=").testers == {
        "dev-abc": "pro_monthly"
    }


def test_grants_stop_at_the_expiry_date() -> None:
    """The whole point of the expiry: a temporary arrangement that never ends is a permanent one."""
    live = _settings(tester_grants="dev-abc=pro_monthly", tester_grants_until="2999-01-01")
    dead = _settings(tester_grants="dev-abc=pro_monthly", tester_grants_until="2020-01-01")
    assert live.testers and not dead.testers


def test_an_unparseable_expiry_is_treated_as_expired() -> None:
    """Failing the other way turns a typo into an unbounded grant."""
    assert not _settings(tester_grants="dev-abc=pro_monthly", tester_grants_until="soon").testers


def test_testers_are_refused_in_production() -> None:
    """Staging is where testers belong. Production selling to real customers must not also be
    handing out free plans by installation id."""
    problems = _settings(
        app_env="prod",
        tester_grants="dev-abc=pro_monthly",
        apple_bundle_id="b",
        apple_root_cert_dir="/c",
        llm_provider="anthropic",
    ).validate_for_environment()
    assert any("TESTER_GRANTS" in p for p in problems)


async def test_a_named_tester_gets_their_plan_and_it_is_audited() -> None:
    from agent_server.audit import NullAuditLog

    identity, audit = FakeIdentity(created_at=datetime.now(UTC)), NullAuditLog()
    source = VerifyingPrincipalSource(
        secret="s" * 40,
        plans=PlanResolver(DEFAULT_PLANS, FakeVerifier()),
        catalogue=DEFAULT_PLANS,
        identity=identity,
        audit=audit,
        testers={"friends-phone": "pro_monthly"},
    )
    await source.principal_for(
        app_id="hair-compass", installation_id="friends-phone", subscription_token=""
    )
    assert identity.plans[-1] == "pro_monthly"
    assert dict(audit.events)["subscription.tester_grant"]["plan"] == "pro_monthly"


async def test_a_tester_is_not_cut_off_after_the_taster_expires() -> None:
    """Checked before the taster deliberately — a tester whose access silently became three days
    would report the paywall as a bug."""
    identity = FakeIdentity(created_at=datetime.now(UTC) - timedelta(days=30))
    source = VerifyingPrincipalSource(
        secret="s" * 40,
        plans=PlanResolver(DEFAULT_PLANS, FakeVerifier()),
        catalogue=DEFAULT_PLANS,
        identity=identity,
        testers={"friends-phone": "pro_monthly"},
    )
    await source.principal_for(
        app_id="hair-compass", installation_id="friends-phone", subscription_token=""
    )
    assert identity.plans[-1] == "pro_monthly"


async def test_someone_not_on_the_list_gets_no_special_treatment() -> None:
    identity = FakeIdentity(created_at=datetime.now(UTC) - timedelta(days=30))
    source = VerifyingPrincipalSource(
        secret="s" * 40,
        plans=PlanResolver(DEFAULT_PLANS, FakeVerifier()),
        catalogue=DEFAULT_PLANS,
        identity=identity,
        testers={"friends-phone": "pro_monthly"},
    )
    await source.principal_for(
        app_id="hair-compass", installation_id="a-stranger", subscription_token=""
    )
    assert identity.plans[-1] == FREE_PLAN_ID


# --------------------------------------------------------------------------------------------
# Photos are a paid feature. The free period shows the product; photos are a reason to subscribe.
# --------------------------------------------------------------------------------------------


def test_the_free_period_does_not_include_photos() -> None:
    """Images are by far the most expensive thing a turn can carry, and the taster is the only
    tier with no payment method behind it."""
    from agent_core.plans import PHOTO_FEATURE

    assert not DEFAULT_PLANS.get("taster").allows_feature(PHOTO_FEATURE)
    assert not DEFAULT_PLANS.get(FREE_PLAN_ID).allows_feature(PHOTO_FEATURE)


def test_every_paid_tier_including_the_trial_does_include_photos() -> None:
    """The trial has a card on file, so the constraint there is conversion rather than abuse."""
    from agent_core.plans import PHOTO_FEATURE

    for plan_id in ("trial", "pro_monthly", "pro_yearly"):
        assert DEFAULT_PLANS.get(plan_id).allows_feature(PHOTO_FEATURE), plan_id


def test_the_taster_keeps_everything_else() -> None:
    """Only photos are withheld. A free period that quietly drops half the product is not a
    demonstration of the product."""
    taster = DEFAULT_PLANS.get("taster")
    assert taster.allows_feature("deep_analysis")
    assert taster.allows_feature("weekly_report")
    assert taster.tools is None  # every tool, same as paid


async def test_a_taster_turn_carrying_a_photo_is_refused_before_consent_is_considered() -> None:
    """ "Your plan does not include this" is a more useful answer than "you have not agreed to it" —
    telling someone to grant consent for something they still could not use is a dead end."""
    from tests.test_privacy import FakeIdentity

    from agent_server.core.errors import NotEntitled
    from agent_server.runs import RunRegistry
    from agent_server.turns import TurnService

    taster = Principal(
        app_id="hair-compass",
        principal_id="p_taster",
        installation_id="dev-taster",
        data_subject_id="d_taster",
        entitlement=Entitlement.PRO,
        plan_id="taster",
    )
    identity = FakeIdentity()
    # BOTH consents on file, so the plan is unambiguously the thing being refused.
    for purpose in ("agent-analysis", "photo-analysis"):
        await identity.grant(
            taster.principal_id, purpose=purpose, policy_version="1.0", crosses_border=True
        )
    service = TurnService(agent=None, runs=RunRegistry(), identity=identity, plans=DEFAULT_PLANS)

    # Text still works on the taster — this is not a lockout.
    await service.authorize(taster)

    with pytest.raises(NotEntitled):
        await service.authorize(taster, attachments=1)
