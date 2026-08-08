"""Plans and locales as data — the tests that keep them from becoming code again.

The failure both of these prevent is the same shape: a product decision welded into an enum or a
regex, so changing a price or adding a language means a deploy and an App Store review.
"""

from __future__ import annotations

import pytest

from agent_core.locales import (
    DEFAULT_LOCALE,
    LocaleCatalogue,
    LocaleError,
    LocalePack,
)
from agent_core.plans import DEFAULT_PLANS, FREE_PLAN_ID, Plan, PlanCatalogue

REQUIRED_RULES = frozenset({"personal_diagnosis", "myth_asserted_as_fact"})


def _locale(code: str, **kw) -> dict:
    base = {
        "code": code,
        "text_rules": {
            "personal_diagnosis": r"\byou\b.{0,40}\balopecia\b",
            "myth_asserted_as_fact": r"\bbiotin\b.{0,30}\bhelps\b",
        },
    }
    return base | kw


# --------------------------------------------------------------------------------------------
# Plans
# --------------------------------------------------------------------------------------------


def test_a_new_tier_is_a_row_not_a_code_change() -> None:
    """The headline property. Adding "plus" must need no enum edit, no comparison rewrite, and no
    client update."""
    catalogue = PlanCatalogue.from_config(
        [
            {"id": FREE_PLAN_ID, "rank": 0},
            {"id": "plus", "rank": 50, "daily_token_budget": 60_000},
            {"id": "pro", "rank": 100, "daily_token_budget": 200_000},
        ]
    )
    assert [p.id for p in catalogue] == ["free", "plus", "pro"]
    assert catalogue.meets("plus", minimum="free")
    assert not catalogue.meets("plus", minimum="pro")


def test_ranks_leave_gaps_so_a_tier_can_be_inserted_later() -> None:
    """Renumbering is how a min_plan check silently inverts."""
    assert DEFAULT_PLANS.get("pro_monthly").rank - DEFAULT_PLANS.free.rank >= 10


def test_an_unknown_plan_degrades_to_free_rather_than_raising() -> None:
    """A tier renamed between deploys must cost privileges, never access."""
    assert DEFAULT_PLANS.get("tier-that-was-renamed").id == FREE_PLAN_ID
    assert DEFAULT_PLANS.get(None).id == FREE_PLAN_ID
    assert DEFAULT_PLANS.get("").id == FREE_PLAN_ID


def test_a_catalogue_without_a_free_plan_is_rejected() -> None:
    with pytest.raises(ValueError, match="fall back to"):
        PlanCatalogue.from_config([{"id": "pro", "rank": 100}])


def test_duplicate_ids_and_products_are_rejected() -> None:
    with pytest.raises(ValueError, match="duplicate plan"):
        PlanCatalogue.from_config([{"id": "free", "rank": 0}, {"id": "free", "rank": 1}])
    with pytest.raises(ValueError, match="two plans claim product"):
        PlanCatalogue.from_config(
            [
                {"id": "free", "rank": 0},
                {"id": "a", "rank": 1, "product_id": "x"},
                {"id": "b", "rank": 2, "product_id": "x"},
            ]
        )


def test_a_store_product_maps_to_exactly_one_plan() -> None:
    """The join between a verified purchase and what it unlocks."""
    plan = DEFAULT_PLANS.for_product("harib.haircompass.pro.monthly")
    assert plan is not None and plan.id == "pro_monthly"
    # A product we do not sell is a real case worth surfacing, not silently granting.
    assert DEFAULT_PLANS.for_product("something.we.never.sold") is None


def test_the_trial_is_its_own_plan_with_its_own_budget() -> None:
    """Not a duration flag on pro. Every trial turn costs real money, so a trial is a different
    commercial object from the paid tier and needs its own cap — otherwise 90 days of full access
    is roughly $8 of API spend per trial user, most of whom will not convert."""
    trial = DEFAULT_PLANS.get("trial")
    pro = DEFAULT_PLANS.get("pro_monthly")
    assert trial.offers_trial and trial.trial_days == 14
    # Compare RATES, not the raw fields. `daily_token_budget` is spent over `budget_window_days`,
    # so the trial's 252k/week and pro's 198k/day are not the same unit — the old assertion put
    # them side by side and passed on a coincidence.
    trial_per_day = trial.daily_token_budget / trial.budget_window_days
    pro_per_day = pro.daily_token_budget / pro.budget_window_days
    assert 0 < trial_per_day < pro_per_day
    # Same features though — a trial that hides the product is not a trial.
    assert trial.features == pro.features


def test_the_trial_caps_by_week_and_by_total() -> None:
    """A daily cap does not bound a long trial: 3/day over 90 days is 270 turns, MORE than a paying
    user does in a month. The recurring window shapes usage; only the total bounds the cost."""
    trial = DEFAULT_PLANS.get("trial")
    assert trial.budget_window_days == 7
    assert trial.approximate_turns(total=False) == 14  # per week
    assert trial.approximate_turns() == 19  # over the whole trial
    assert trial.has_total_cap


def test_a_weekly_window_absorbs_burst_use() -> None:
    """A tracking app is used in bursts — after a wash, when a lab result arrives. A daily ration
    fights that pattern; a weekly window lets someone spend their allowance when they need it."""
    trial = DEFAULT_PLANS.get("trial")
    # A whole week's allowance is spendable in one sitting, by design.
    assert trial.daily_token_budget >= 10 * 18_000


def test_the_paid_plan_has_no_lifetime_ceiling() -> None:
    """A renewing subscription has no lifetime to budget — only a time-limited plan does."""
    assert not DEFAULT_PLANS.get("pro_monthly").has_total_cap
    assert DEFAULT_PLANS.get("pro_monthly").budget_window_days == 1


def test_the_trial_sits_between_lapsed_and_paid() -> None:
    """So a `min_plan` check written for pro correctly excludes a trial user, and one written for
    the base plan correctly includes them."""
    assert DEFAULT_PLANS.meets("trial", minimum="free")
    assert not DEFAULT_PLANS.meets("trial", minimum="pro_monthly")


def test_the_product_is_subscription_only_with_a_trial() -> None:
    """The commercial shape, asserted. Subscription-only is also the strongest CONSENT position
    available: with no free tier there is no tier where agreeing to share data could become the
    price of entry."""
    assert not DEFAULT_PLANS.has_free_tier
    assert DEFAULT_PLANS.subscription_only
    assert any(plan.offers_trial for plan in DEFAULT_PLANS)


def test_the_base_plan_is_the_lapsed_state_not_a_free_tier() -> None:
    """Someone whose trial ended or whose card failed must land somewhere DEFINED. Zero budget,
    zero tools, and the client renders a paywall — never an undefined state or an exception."""
    lapsed = DEFAULT_PLANS.free
    assert not lapsed.is_paid
    assert lapsed.daily_token_budget == 0
    assert lapsed.tools == frozenset()
    assert DEFAULT_PLANS.get("pro_monthly").is_paid


def test_a_freemium_catalogue_is_still_expressible() -> None:
    """Switching to freemium later must be config, not a rewrite — the whole point of plans as
    data. Same code path, different rows."""
    freemium = PlanCatalogue.from_config(
        [
            {"id": FREE_PLAN_ID, "rank": 0, "daily_token_budget": 20_000},
            {"id": "pro", "rank": 100, "daily_token_budget": 200_000},
        ],
        subscription_only=False,
    )
    assert freemium.has_free_tier
    assert freemium.free.is_paid  # a free tier WITH a small AI budget


def test_free_cannot_reach_the_expensive_strategies() -> None:
    """orchestrator_workers fans out to several model calls, so strategy tier IS a price tier."""
    assert DEFAULT_PLANS.free.max_strategy == "direct"


def test_tools_none_means_everything_the_pack_offers_not_everything_imaginable() -> None:
    pro = DEFAULT_PLANS.get("pro_monthly")
    assert pro.tools is None
    assert pro.allows_tool("anything")  # the pack's catalogue is still the outer bound
    assert not DEFAULT_PLANS.free.allows_tool("recall_memory")


def test_plans_are_frozen() -> None:
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        DEFAULT_PLANS.free.daily_token_budget = 999_999  # type: ignore[misc]


def test_only_the_trial_plan_offers_a_trial() -> None:
    """The lawful shape of "let them try before deciding": a time-limited plan with no consent
    bargain anywhere. Neither the lapsed state nor the paid tier carries a trial period — the
    trial IS a plan."""
    assert not DEFAULT_PLANS.free.offers_trial
    assert not DEFAULT_PLANS.get("pro_monthly").offers_trial
    assert [p.id for p in DEFAULT_PLANS if p.offers_trial] == ["trial"]


def test_trial_length_is_config_not_a_constant() -> None:
    """A promotion should be a config change, not a deploy."""
    catalogue = PlanCatalogue.from_config(
        [{"id": FREE_PLAN_ID, "rank": 0}, {"id": "pro", "rank": 100, "trial_days": 7}]
    )
    assert catalogue.get("pro").trial_days == 7


def test_a_plan_carries_no_price() -> None:
    """The real price lives in App Store Connect. Duplicating it here creates two sources of
    truth and one of them is wrong."""
    assert "price" not in Plan.model_fields


# --------------------------------------------------------------------------------------------
# Locales — the safety half
# --------------------------------------------------------------------------------------------


def test_a_locale_without_its_safety_rules_is_refused() -> None:
    """THE test. Adding Arabic without Arabic rules means the guards silently stop existing —
    every English test still passes while unguarded answers ship."""
    with pytest.raises(LocaleError, match="missing safety rules"):
        LocaleCatalogue.from_config(
            [_locale("en"), {"code": "ar", "text_rules": {}}],
            required_rules=REQUIRED_RULES,
        )


def test_a_partially_ruled_locale_is_also_refused() -> None:
    with pytest.raises(LocaleError, match="myth_asserted_as_fact"):
        LocaleCatalogue.from_config(
            [
                _locale("en"),
                {"code": "ar", "text_rules": {"personal_diagnosis": r"\byou\b"}},
            ],
            required_rules=REQUIRED_RULES,
        )


def test_a_malformed_pattern_fails_at_load_not_mid_turn() -> None:
    """A regex error inside a safety check would otherwise surface on a user's question, and the
    safe response to that is not obvious at 3am."""
    with pytest.raises(LocaleError, match="bad pattern"):
        LocaleCatalogue.from_config(
            [
                _locale("en"),
                _locale(
                    "ar",
                    text_rules={"personal_diagnosis": "([unclosed", "myth_asserted_as_fact": "ok"},
                ),
            ],
            required_rules=REQUIRED_RULES,
        )


def test_a_regional_variant_degrades_to_its_language_not_to_english() -> None:
    """A client asking for ar-OM should get Arabic, not English."""
    catalogue = LocaleCatalogue.from_config(
        [_locale("en"), _locale("ar")], required_rules=REQUIRED_RULES
    )
    assert catalogue.resolve("ar-OM").code == "ar"
    assert catalogue.resolve("ar_OM").code == "ar"
    assert catalogue.resolve("AR").code == "ar"


def test_an_unknown_language_falls_back_to_the_default() -> None:
    catalogue = LocaleCatalogue.from_config([_locale("en")], required_rules=REQUIRED_RULES)
    assert catalogue.resolve("ja").code == DEFAULT_LOCALE
    assert catalogue.resolve(None).code == DEFAULT_LOCALE


def test_rtl_is_server_supplied_so_a_new_rtl_language_is_a_row() -> None:
    assert LocalePack(code="ar").is_rtl
    assert LocalePack(code="ar-OM").is_rtl
    assert LocalePack(code="he").is_rtl
    assert not LocalePack(code="en").is_rtl


def test_a_catalogue_must_define_the_default_locale() -> None:
    with pytest.raises(LocaleError, match="must define"):
        LocaleCatalogue.from_config([_locale("ar")], required_rules=REQUIRED_RULES)


def test_rules_compile_with_their_stand_down_pattern_paired() -> None:
    """Debunking a myth must survive in every language, not just English."""
    pack = LocalePack.model_validate(
        _locale("en", text_rule_exceptions={"myth_asserted_as_fact": r"\bnot\b|\bno evidence\b"})
    )
    compiled = pack.compiled_rules()
    fire, unless = compiled["myth_asserted_as_fact"]
    assert fire.search("biotin helps hair")
    assert unless is not None and unless.search("no evidence biotin helps")
    assert compiled["personal_diagnosis"][1] is None
