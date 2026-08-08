"""One test per bug the external review of `f05bf1f` actually found.

These are here so the fixes cannot be quietly undone. Each name states the *defect*, not the
feature — a test called `test_trial_resolution_works` goes green on the broken version too, which
is how a regression suite becomes decoration.

The four DB-level findings need a real Postgres and live in `test_postgres_regressions.py`; these
are the ones that are pure.
"""

from __future__ import annotations

import asyncio

from agent_core.plans import DEFAULT_PLANS, FREE_PLAN_ID, PlanCatalogue
from agent_server.billing import FakeVerifier, PlanResolver
from agent_server.ratelimit import Limit, RateLimiter

# --------------------------------------------------------------------------------------------
# Finding: the trial plan was picked with `next(p for p in catalogue if p.offers_trial)`.
#
# Correct for exactly one trial, silently wrong for two — it grants whichever tier iterates first
# (rank order), which for a cheap and an expensive product means the wrong allowance with no error
# anywhere. It surfaces as a support ticket, not a stack trace.
# --------------------------------------------------------------------------------------------

TWO_PRODUCTS = PlanCatalogue.from_config(
    [
        {"id": FREE_PLAN_ID, "rank": 0, "daily_token_budget": 0},
        {
            # No `product_id`: Apple's introductory offer is on the SAME product as the paid tier,
            # which is exactly why the trial has to name its destination instead of claiming one.
            "id": "basic-trial",
            "rank": 10,
            "daily_token_budget": 10_000,
            "trial_days": 14,
            "trial_of": ["basic"],
        },
        {
            "id": "basic",
            "rank": 20,
            "product_id": "app.basic.monthly",
            "daily_token_budget": 50_000,
        },
        {
            "id": "premium-trial",
            "rank": 30,
            "daily_token_budget": 40_000,
            "trial_days": 30,
            "trial_of": ["premium"],
        },
        {
            "id": "premium",
            "rank": 40,
            "product_id": "app.premium.monthly",
            "daily_token_budget": 200_000,
        },
    ]
)


def test_a_second_product_with_its_own_trial_does_not_steal_the_first_ones() -> None:
    assert DEFAULT_PLANS.trial_for("pro_monthly").id == "trial"
    assert TWO_PRODUCTS.trial_for("basic").id == "basic-trial"
    assert TWO_PRODUCTS.trial_for("premium").id == "premium-trial"


def test_a_paid_plan_with_no_trial_of_its_own_gets_none_rather_than_someone_elses() -> None:
    """The dangerous shape is a *plausible* wrong answer. Returning `None` sends the caller down
    the "grant the paid plan" path, which is at worst generous by one tier; returning another
    product's trial hands out the wrong budget and looks correct in the logs."""
    catalogue = PlanCatalogue.from_config(
        [
            {"id": FREE_PLAN_ID, "rank": 0, "daily_token_budget": 0},
            {
                "id": "a-trial",
                "rank": 10,
                "daily_token_budget": 1,
                "trial_days": 7,
                "trial_of": ["a"],
            },
            {"id": "a", "rank": 20, "daily_token_budget": 10},
            {"id": "b", "rank": 30, "daily_token_budget": 10},
        ]
    )
    assert catalogue.trial_for("b") is None
    # …and an unnamed single trial still resolves, so a one-product catalogue needs no ceremony.
    single = PlanCatalogue.from_config(
        [
            {"id": FREE_PLAN_ID, "rank": 0, "daily_token_budget": 0},
            {"id": "t", "rank": 10, "daily_token_budget": 1, "trial_days": 7, "trial_of": []},
            {"id": "paid", "rank": 20, "daily_token_budget": 10},
        ]
    )
    assert single.trial_for("paid").id == "t"


async def test_a_premium_trial_receipt_does_not_resolve_to_the_basic_trials_budget() -> None:
    """End to end through the resolver — the path a real receipt takes."""
    resolver = PlanResolver(TWO_PRODUCTS, FakeVerifier(in_trial=True))
    plan_id, _ = await resolver.resolve("app.premium.monthly:txn-9")
    assert plan_id == "premium-trial"
    assert TWO_PRODUCTS.get(plan_id).daily_token_budget == 40_000


# --------------------------------------------------------------------------------------------
# NOT a regression test — an invariant test, and labelled as one.
#
# The review also claimed `RateLimiter.check` reading the clock before taking the lock let stale
# timestamps land out of order and jam the expiry loop. Checked against the unfixed code: both of
# these went green, so the bug was not real — `asyncio.Lock` wakes waiters FIFO. The clock moved
# inside the lock regardless, and this pins the invariant so a future swap to a non-FIFO primitive
# fails here instead of silently throttling a phone forever.
# --------------------------------------------------------------------------------------------


async def test_a_burst_of_concurrent_checks_leaves_the_window_able_to_expire() -> None:
    limiter = RateLimiter(Limit(count=200, seconds=1))
    await asyncio.gather(*(limiter.check("k") for _ in range(60)))

    hits = list(limiter._windows["k"].hits)
    assert hits == sorted(hits), "timestamps landed out of order; expiry would stall"

    await asyncio.sleep(1.05)
    await limiter.check("k")
    assert len(limiter._windows["k"].hits) == 1
