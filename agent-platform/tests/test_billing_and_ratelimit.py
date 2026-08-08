"""Subscription verification and rate limiting — the two things standing between a LAN toy and a
publicly reachable paid service.

Both are written as attacks that must fail. "Does a valid subscription work?" goes green on a
server that grants Pro to everyone, which is exactly what `DevPrincipalSource` did.
"""

from __future__ import annotations

import asyncio

import pytest

from agent_core.plans import DEFAULT_PLANS, FREE_PLAN_ID
from agent_server.billing import (
    FakeVerifier,
    PlanResolver,
    VerificationError,
    VerifiedSubscription,
    resolve_plan_limits,
)
from agent_server.ratelimit import (
    Limit,
    RateLimited,
    RateLimiter,
    RequestGuard,
)

PRO_PRODUCT = "harib.haircompass.pro.monthly"


def resolver(*, in_trial: bool = False) -> PlanResolver:
    return PlanResolver(DEFAULT_PLANS, FakeVerifier(in_trial=in_trial))


# --------------------------------------------------------------------------------------------
# Subscription verification
# --------------------------------------------------------------------------------------------


async def test_no_token_gets_the_base_plan_not_a_paid_one() -> None:
    """The hole this closes: DevPrincipalSource handed Pro to everyone."""
    plan_id, sub = await resolver().resolve(None)
    assert plan_id == FREE_PLAN_ID
    assert sub is None


async def test_an_unverifiable_token_degrades_rather_than_raising() -> None:
    """A billing hiccup must land someone on the paywall, never in an error state where the app is
    unusable and they cannot see how to fix it."""
    plan_id, _ = await resolver().resolve("not-a-token")
    assert plan_id == FREE_PLAN_ID


async def test_a_verified_purchase_grants_exactly_the_plan_that_claims_the_product() -> None:
    plan_id, sub = await resolver().resolve(f"{PRO_PRODUCT}:txn-1")
    assert plan_id == "pro_monthly"
    assert sub is not None and sub.original_transaction_id == "txn-1"


async def test_a_product_no_plan_claims_grants_nothing() -> None:
    """A verified purchase for something we do not sell. Real case — a product exists in App Store
    Connect that no plan claims — and it must not silently grant the nearest thing."""
    plan_id, sub = await resolver().resolve("com.someone.else.product:txn-2")
    assert plan_id == FREE_PLAN_ID
    assert sub is not None  # verified, just not ours


async def test_apples_trial_flag_grants_the_trial_plan_not_the_paid_one() -> None:
    """Trial eligibility is Apple's answer, never a local clock — a local one hands a fresh trial
    to anyone who reinstalls. Different plan means a different budget."""
    plan_id, _ = await resolver(in_trial=True).resolve(f"{PRO_PRODUCT}:txn-3")
    assert plan_id == "trial"
    assert DEFAULT_PLANS.get(plan_id).total_token_budget > 0


async def test_an_expired_subscription_is_not_active() -> None:
    from datetime import UTC, datetime, timedelta

    expired = VerifiedSubscription(
        product_id=PRO_PRODUCT,
        original_transaction_id="txn-4",
        expires_at=datetime.now(UTC) - timedelta(days=1),
    )
    assert not expired.is_active
    live = expired.model_copy(update={"expires_at": datetime.now(UTC) + timedelta(days=1)})
    assert live.is_active
    # A non-renewing purchase has no expiry and stays valid.
    assert expired.model_copy(update={"expires_at": None}).is_active


async def test_the_fake_verifier_refuses_to_exist_in_production() -> None:
    """A verifier that can be told what to return must be unreachable from prod. That is the
    difference between a paywall and a suggestion."""
    with pytest.raises(RuntimeError, match="cannot run in prod"):
        FakeVerifier(is_prod=True)


async def test_a_malformed_token_raises_rather_than_returning_something() -> None:
    with pytest.raises(VerificationError):
        await FakeVerifier().verify("")


def test_plan_limits_come_from_one_place() -> None:
    """So no caller reconstructs a plan's numbers by hand — the bug that produces is a budget
    enforced in one place and forgotten in another."""
    limits = resolve_plan_limits(DEFAULT_PLANS, "trial")
    trial = DEFAULT_PLANS.get("trial")
    assert limits["daily_budget"] == trial.daily_token_budget
    assert limits["total_budget"] == trial.total_token_budget
    assert limits["window_days"] == trial.budget_window_days


# --------------------------------------------------------------------------------------------
# Rate limiting
# --------------------------------------------------------------------------------------------


async def test_a_flood_from_one_key_is_stopped() -> None:
    limiter = RateLimiter(Limit(count=5, seconds=60))
    for _ in range(5):
        await limiter.check("k")
    with pytest.raises(RateLimited):
        await limiter.check("k")


async def test_one_key_being_throttled_does_not_affect_another() -> None:
    limiter = RateLimiter(Limit(count=2, seconds=60))
    await limiter.check("a")
    await limiter.check("a")
    with pytest.raises(RateLimited):
        await limiter.check("a")
    await limiter.check("b")  # unaffected


async def test_the_window_slides_rather_than_resetting_on_a_boundary() -> None:
    """A fixed window permits 2x the limit across the two seconds either side of its reset. That
    burst is exactly what the limit existed to prevent."""
    limiter = RateLimiter(Limit(count=3, seconds=1))
    for _ in range(3):
        await limiter.check("k")
    with pytest.raises(RateLimited):
        await limiter.check("k")
    await asyncio.sleep(1.05)
    await limiter.check("k")  # the old hits have slid out


async def test_idle_keys_are_swept_so_the_map_cannot_grow_forever() -> None:
    """An unauthenticated endpoint would otherwise hand an attacker a memory leak for free."""
    limiter = RateLimiter(Limit(count=10, seconds=1))
    for i in range(50):
        await limiter.check(f"key-{i}")
    assert limiter.tracked_keys == 50
    await asyncio.sleep(2.1)
    await limiter.check("trigger-the-sweep")
    assert limiter.tracked_keys < 50


async def test_address_and_principal_limits_are_independent() -> None:
    """Per-principal survives an IP change, so a phone roaming wifi-to-cellular is not punished and
    one account cannot be multiplied by rotating addresses. Per-address catches the flood that
    happens BEFORE a principal exists."""
    guard = RequestGuard(
        principal_limit=Limit(count=2, seconds=60), address_limit=Limit(count=100, seconds=60)
    )
    await guard.check_address("1.2.3.4")
    await guard.check_principal("p1")
    await guard.check_principal("p1")
    with pytest.raises(RateLimited):
        await guard.check_principal("p1")
    # Same address, different principal: fine.
    await guard.check_principal("p2")


async def test_a_missing_address_does_not_crash_the_guard() -> None:
    """A proxy that strips the client address must degrade to principal-only limiting, not 500."""
    guard = RequestGuard()
    await guard.check_address(None)


def test_a_nonsense_limit_is_rejected() -> None:
    with pytest.raises(ValueError):
        Limit(count=0, seconds=60)
    with pytest.raises(ValueError):
        Limit(count=10, seconds=0)


# --------------------------------------------------------------------------------------------
# Subscription validity beyond expiry — the second review pass.
#
# Expiry alone was the whole check. A refunded subscription keeps its `expiresDate` (Apple signals
# the refund through `revocationDate`), so a user could refund and keep paid access for the rest of
# a period they no longer paid for.
# --------------------------------------------------------------------------------------------


def _sub(**kw) -> VerifiedSubscription:
    from datetime import UTC, datetime, timedelta

    base = {
        "product_id": PRO_PRODUCT,
        "original_transaction_id": "txn-x",
        "expires_at": datetime.now(UTC) + timedelta(days=30),
    }
    return VerifiedSubscription(**{**base, **kw})


def test_a_refunded_subscription_is_not_active_despite_a_future_expiry() -> None:
    from datetime import UTC, datetime

    assert _sub().is_active
    assert not _sub(revoked_at=datetime.now(UTC)).is_active


def test_a_superseded_upgrade_is_not_active_despite_a_future_expiry() -> None:
    """The transaction the user moved OFF stays signed and unexpired. Replaying it must grant
    nothing, or an upgrade becomes two entitlements."""
    assert not _sub(is_upgraded=True).is_active


def test_a_revoked_non_renewing_purchase_is_not_active_either() -> None:
    """No expiry used to mean 'valid forever' unconditionally — including after a refund."""
    from datetime import UTC, datetime

    assert _sub(expires_at=None).is_active
    assert not _sub(expires_at=None, revoked_at=datetime.now(UTC)).is_active
