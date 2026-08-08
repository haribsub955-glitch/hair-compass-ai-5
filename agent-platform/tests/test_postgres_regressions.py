"""The four review findings that only a real Postgres can prove.

Skipped without `AGENT_TEST_DATABASE_URL`, so a laptop with no database still runs the suite green.
That is a deliberate trade and it has a cost: these are exactly the bugs that a pure-Python test
CANNOT catch, so a green local run is not evidence they are fixed. Run this against the deployment
before believing the budget holds.

Each test is written as the ATTACK, not the feature. "Does the ledger record spend?" passes on the
broken version; "can ten concurrent turns walk past the lifetime cap?" does not.
"""

from __future__ import annotations

import asyncio
import os
import uuid
from datetime import UTC, datetime, timedelta

import pytest

from agent_core.contracts import Entitlement, Principal
from agent_server.core.errors import QuotaExhausted
from agent_server.db.identity import IdentityStore
from agent_server.db.ledger import PostgresLedger
from agent_server.db.session import create_schema, make_engine, make_sessions

DATABASE_URL = os.environ.get("AGENT_TEST_DATABASE_URL", "")

pytestmark = pytest.mark.skipif(
    not DATABASE_URL, reason="set AGENT_TEST_DATABASE_URL to run the Postgres regressions"
)


@pytest.fixture
async def sessions():
    engine = make_engine(DATABASE_URL)
    await create_schema(engine)
    yield make_sessions(engine)
    await engine.dispose()


@pytest.fixture
def principal_id() -> str:
    """A fresh id per test.

    These run against a real, shared, PERSISTENT database — the deployment's own. So every
    identifier a test writes has to be unique per run, transaction ids included: a literal
    `txn-shared` passes once and then fails forever against the unique constraint it was written
    to prove. Derive them from this.
    """
    return f"test-{uuid.uuid4().hex[:12]}"


async def _register(sessions, principal_id: str) -> None:
    await IdentityStore(sessions).register(
        Principal(
            principal_id=principal_id,
            app_id="test",
            installation_id=f"dev-{principal_id}",
            data_subject_id=principal_id,
            entitlement=Entitlement.FREE,
        )
    )


async def _spend_on_day(sessions, principal_id: str, *, day, amount: int) -> None:
    """Write a spend row directly. Backdating through `reserve` is not possible and these tests
    need history that predates the current plan."""
    from sqlalchemy import text

    async with sessions() as session, session.begin():
        await session.execute(
            text(
                """
                INSERT INTO principal_daily_spend (principal_id, day, spent, updated_at)
                VALUES (:pid, :day, :amount, now())
                ON CONFLICT (principal_id, day) DO UPDATE
                   SET spent = principal_daily_spend.spent + :amount
                """
            ),
            {"pid": principal_id, "day": day, "amount": amount},
        )


# --------------------------------------------------------------------------------------------
# Finding 1: `plan_started_at` was read by the ledger and written by nothing.
#
# NULL for every principal, and the fallback compared `s.day` to itself — always true — so the
# lifetime cap silently measured ALL-TIME spend. A user who trialled, subscribed, lapsed and came
# back was charged for tokens from a plan they no longer held.
# --------------------------------------------------------------------------------------------


async def test_spend_from_a_previous_plan_is_not_counted_against_the_new_one(
    sessions, principal_id
) -> None:
    await _register(sessions, principal_id)
    identity = IdentityStore(sessions)

    # A trial's worth of history, then an upgrade.
    old_day = datetime.now(UTC).date() - timedelta(days=40)
    await _spend_on_day(sessions, principal_id, day=old_day, amount=500_000)
    assert await identity.set_plan(
        principal_id, plan_id="pro_monthly", subscription_txn_id=f"txn-A-{principal_id}"
    )

    ledger = PostgresLedger(sessions, daily_budget=200_000, total_budget=540_000)
    assert await ledger.spent_in_plan_period(principal_id) == 0, "old plan's spend leaked forward"
    await ledger.reserve(principal_id, 100_000)  # would raise if the 500k counted


async def test_re_registering_does_not_reset_the_trial_clock(sessions, principal_id) -> None:
    """The opposite failure: stamping `plan_started_at` on every session makes the lifetime cap
    unreachable, because the window restarts before it can ever bind."""
    await _register(sessions, principal_id)
    identity = IdentityStore(sessions)
    await identity.set_plan(principal_id, plan_id="trial")

    from sqlalchemy import text

    async def started_at():
        async with sessions() as session:
            return await session.scalar(
                text("SELECT plan_started_at FROM principals WHERE principal_id = :pid"),
                {"pid": principal_id},
            )

    first = await started_at()
    assert first is not None
    await asyncio.sleep(0.05)
    await identity.set_plan(principal_id, plan_id="trial")  # same plan, a later session
    assert await started_at() == first
    await identity.set_plan(principal_id, plan_id="pro_monthly")  # a real change
    assert await started_at() > first


# --------------------------------------------------------------------------------------------
# Finding 2: the window and lifetime caps were checked read-then-write.
#
# My first estimate of the damage was wrong too. I reasoned the overshoot was "one turn"; it is
# not — N concurrent requests all read the same total, all pass, and each then spends up to the
# DAILY budget. On a 540k lifetime cap with a 180k daily cap, a 30-turn trial is unbounded.
# --------------------------------------------------------------------------------------------


async def test_concurrent_turns_cannot_walk_past_the_lifetime_cap(sessions, principal_id) -> None:
    await _register(sessions, principal_id)
    await IdentityStore(sessions).set_plan(principal_id, plan_id="trial")

    ledger = PostgresLedger(sessions, daily_budget=180_000, total_budget=100_000, window_days=7)
    results = await asyncio.gather(
        *(ledger.reserve(principal_id, 30_000) for _ in range(10)), return_exceptions=True
    )
    granted = [r for r in results if not isinstance(r, BaseException)]
    unexpected = [
        r for r in results if isinstance(r, BaseException) and not isinstance(r, QuotaExhausted)
    ]
    assert not unexpected, unexpected
    assert len(granted) == 3, f"{len(granted)} turns got through a 100k cap at 30k each"
    assert await ledger.spent_in_plan_period(principal_id) == 90_000


async def test_concurrent_turns_cannot_walk_past_the_rolling_week(sessions, principal_id) -> None:
    await _register(sessions, principal_id)
    await IdentityStore(sessions).set_plan(principal_id, plan_id="trial")

    # Yesterday's spend counts against a 7-day window — a per-day statement alone would miss it.
    yesterday = datetime.now(UTC).date() - timedelta(days=1)
    await _spend_on_day(sessions, principal_id, day=yesterday, amount=40_000)

    ledger = PostgresLedger(sessions, daily_budget=60_000, window_days=7)
    results = await asyncio.gather(
        *(ledger.reserve(principal_id, 10_000) for _ in range(8)), return_exceptions=True
    )
    granted = [r for r in results if not isinstance(r, BaseException)]
    # Assert the refusals are QUOTA refusals. Counting "anything that raised" as a successful
    # denial makes the test pass when the ledger is simply broken — a connection error would read
    # as the cap working.
    unexpected = [
        r for r in results if isinstance(r, BaseException) and not isinstance(r, QuotaExhausted)
    ]
    assert not unexpected, unexpected
    assert len(granted) == 2, f"{len(granted)} turns got through a 60k week with 40k already spent"
    assert await ledger.spent_in_window(principal_id, days=7) == 60_000


# --------------------------------------------------------------------------------------------
# Finding 3: a StoreKit receipt is a bearer token, so nothing stopped two principals claiming one.
# --------------------------------------------------------------------------------------------


async def test_a_second_principal_cannot_claim_someone_elses_subscription(
    sessions, principal_id
) -> None:
    other = f"{principal_id}-b"
    await _register(sessions, principal_id)
    await _register(sessions, other)
    identity = IdentityStore(sessions)

    assert await identity.set_plan(
        principal_id, plan_id="pro_monthly", subscription_txn_id=f"txn-shared-{principal_id}"
    )
    assert not await identity.set_plan(
        other, plan_id="pro_monthly", subscription_txn_id=f"txn-shared-{principal_id}"
    )

    from sqlalchemy import text

    async with sessions() as session:
        entitlement = await session.scalar(
            text("SELECT entitlement FROM principals WHERE principal_id = :pid"), {"pid": other}
        )
    assert entitlement != "pro", "the replayed receipt still upgraded the second principal"


async def test_the_same_principal_may_re_present_its_own_receipt(sessions, principal_id) -> None:
    """Every launch re-presents the receipt. Idempotent, or the app breaks on second run."""
    await _register(sessions, principal_id)
    identity = IdentityStore(sessions)
    assert await identity.set_plan(
        principal_id, plan_id="pro_monthly", subscription_txn_id=f"txn-own-{principal_id}"
    )
    assert await identity.set_plan(
        principal_id, plan_id="pro_monthly", subscription_txn_id=f"txn-own-{principal_id}"
    )


# --------------------------------------------------------------------------------------------
# Finding 4: `grant()` treated a purpose as already-consented regardless of `crosses_border`.
#
# Someone who agreed to local-only processing and later agreed to a cross-border transfer hit the
# early return. The record then permanently said they had agreed only to the narrower thing —
# which, under PDPL, is a transfer with no consent behind it.
# --------------------------------------------------------------------------------------------


async def test_agreeing_to_a_cross_border_transfer_is_recorded_as_a_new_grant(
    sessions, principal_id
) -> None:
    await _register(sessions, principal_id)
    identity = IdentityStore(sessions)

    await identity.grant(
        principal_id, purpose="agent-analysis", policy_version="1.0", crosses_border=False
    )
    await identity.grant(
        principal_id, purpose="agent-analysis", policy_version="1.0", crosses_border=True
    )

    assert await identity.has_consent(
        principal_id, purpose="agent-analysis", crosses_border=True
    ), "the cross-border agreement was swallowed as a duplicate"
    assert await identity.has_consent(principal_id, purpose="agent-analysis", crosses_border=False)


async def test_a_local_only_grant_does_not_answer_the_cross_border_question(
    sessions, principal_id
) -> None:
    await _register(sessions, principal_id)
    identity = IdentityStore(sessions)
    await identity.grant(
        principal_id, purpose="memory-sync", policy_version="1.0", crosses_border=False
    )
    assert not await identity.has_consent(principal_id, purpose="memory-sync", crosses_border=True)


async def test_re_affirming_identical_terms_does_not_double_the_audit_trail(
    sessions, principal_id
) -> None:
    await _register(sessions, principal_id)
    identity = IdentityStore(sessions)
    for _ in range(3):
        await identity.grant(
            principal_id, purpose="agent-analysis", policy_version="1.0", crosses_border=False
        )

    from sqlalchemy import text

    async with sessions() as session:
        count = await session.scalar(
            text(
                "SELECT count(*) FROM consent_records "
                "WHERE principal_id = :pid AND purpose = 'agent-analysis'"
            ),
            {"pid": principal_id},
        )
    assert count == 1


# --------------------------------------------------------------------------------------------
# From the second review pass. Each of these is a control that existed and was not enforced.
# --------------------------------------------------------------------------------------------


async def test_an_unregistered_principal_cannot_reserve_at_all(sessions) -> None:
    """`SELECT ... FOR UPDATE` on zero rows locks NOTHING.

    The empty result was ignored, so concurrent reserves for a principal with no row serialised on
    nothing and walked past both aggregate caps — the exact race the lock was added to close, still
    open for anyone the registration path had not reached.
    """
    ledger = PostgresLedger(sessions, daily_budget=100_000, total_budget=100_000)
    with pytest.raises(QuotaExhausted):
        await ledger.reserve("test-never-registered", 1_000)


async def test_the_budget_comes_from_the_principals_own_plan(sessions, principal_id) -> None:
    """The caps were defined in `plans.py`, asserted in tests that passed the numbers by hand, and
    disabled in production because wiring only ever passed `daily_budget`."""
    from agent_core.plans import DEFAULT_PLANS
    from agent_server.billing import resolve_plan_limits

    await _register(sessions, principal_id)
    await IdentityStore(sessions).set_plan(principal_id, plan_id="trial")

    ledger = PostgresLedger(
        sessions,
        daily_budget=999_999_999,  # the fallback, which must NOT be what applies
        limits_for=lambda plan_id: resolve_plan_limits(DEFAULT_PLANS, plan_id),
    )
    trial = DEFAULT_PLANS.get("trial")
    with pytest.raises(QuotaExhausted):
        await ledger.reserve(principal_id, trial.daily_token_budget + 1)
    await ledger.reserve(principal_id, 1_000)  # inside the trial's allowance


async def test_a_plan_change_takes_effect_without_a_restart(sessions, principal_id) -> None:
    """Limits are read per reserve rather than cached, because a plan changes mid-session — a trial
    ending, a card failing — and a cached limit keeps granting the old allowance until the process
    restarts."""
    from agent_core.plans import DEFAULT_PLANS, FREE_PLAN_ID
    from agent_server.billing import resolve_plan_limits

    await _register(sessions, principal_id)
    identity = IdentityStore(sessions)
    await identity.set_plan(principal_id, plan_id="pro_monthly")
    ledger = PostgresLedger(
        sessions,
        daily_budget=1,
        limits_for=lambda plan_id: resolve_plan_limits(DEFAULT_PLANS, plan_id),
    )
    await ledger.reserve(principal_id, 50_000)

    await identity.set_plan(principal_id, plan_id=FREE_PLAN_ID)  # lapsed
    with pytest.raises(QuotaExhausted):
        await ledger.reserve(principal_id, 50_000)


async def test_the_schema_guard_notices_what_create_all_cannot_add(sessions) -> None:
    """`create_all` only CREATEs. A column or constraint added to an existing table is a metadata
    change and nothing else, which is how a deployed database ends up accepting one StoreKit
    receipt from any number of principals while every test passes against a fresh one."""
    from agent_server.db.session import make_engine, verify_schema

    engine = make_engine(DATABASE_URL)
    try:
        assert await verify_schema(engine) == []
    finally:
        await engine.dispose()


async def test_erasure_actually_removes_the_rows(sessions, principal_id) -> None:
    """Deletion against a real database, because the one that matters is the one that runs.

    Apple requires in-app account deletion and Google requires a web path too, so a `forget` that
    misses a table is not a rough edge — it is a compliance claim that is false.
    """
    from sqlalchemy import text

    await _register(sessions, principal_id)
    identity = IdentityStore(sessions)
    await identity.grant(
        principal_id, purpose="agent-analysis", policy_version="1.0", crosses_border=True
    )
    await identity.set_plan(
        principal_id, plan_id="pro_monthly", subscription_txn_id=f"gone-{principal_id}"
    )

    removed = await identity.forget(principal_id)
    assert removed["principals"] == 1

    async with sessions() as session:
        for table in ("principals", "devices", "consent_records"):
            left = await session.scalar(
                text(f"SELECT count(*) FROM {table} WHERE principal_id = :pid"),
                {"pid": principal_id},
            )
            assert left == 0, f"{table} still holds rows for an erased principal"


async def test_erasure_frees_the_subscription_for_a_genuine_re_purchase(
    sessions, principal_id
) -> None:
    """The unique constraint makes a receipt non-transferable, which must not also make it
    unusable forever. Deleting the account releases the claim — otherwise a user who erases their
    data and comes back cannot restore the subscription they are still paying for."""
    other = f"{principal_id}-again"
    txn = f"reclaim-{principal_id}"
    await _register(sessions, principal_id)
    await _register(sessions, other)
    identity = IdentityStore(sessions)

    assert await identity.set_plan(principal_id, plan_id="pro_monthly", subscription_txn_id=txn)
    assert not await identity.set_plan(other, plan_id="pro_monthly", subscription_txn_id=txn)

    await identity.forget(principal_id)
    assert await identity.set_plan(other, plan_id="pro_monthly", subscription_txn_id=txn)


async def test_consent_survives_only_until_it_is_withdrawn(sessions, principal_id) -> None:
    await _register(sessions, principal_id)
    identity = IdentityStore(sessions)
    await identity.grant(
        principal_id, purpose="memory-sync", policy_version="1.0", crosses_border=True
    )
    assert await identity.has_consent(principal_id, purpose="memory-sync", crosses_border=True)

    assert await identity.withdraw(principal_id, purpose="memory-sync") == 1
    assert not await identity.has_consent(principal_id, purpose="memory-sync", crosses_border=True)
    # Withdrawing again closes nothing — the grant is already closed, and a second row would make
    # the trail read as though the user was asked twice.
    assert await identity.withdraw(principal_id, purpose="memory-sync") == 0


# --------------------------------------------------------------------------------------------
# Attachments. The privacy claim is "the server never becomes a photo library" — these are the
# tests that make that true rather than aspirational.
# --------------------------------------------------------------------------------------------


def _jpeg(size: int = 64) -> bytes:
    """Minimal bytes that sniff as JPEG."""
    return b"\xff\xd8\xff" + b"\x00" * size


async def test_using_an_attachment_deletes_it_in_the_same_statement(sessions, principal_id) -> None:
    """No window in which a used photo waits for a cleanup job that might not run."""
    from sqlalchemy import text

    from agent_server.attachments import AttachmentStore

    store = AttachmentStore(sessions)
    stored = await store.put(principal_id=principal_id, data=_jpeg())

    taken = await store.take(principal_id=principal_id, ids=[stored["attachment_id"]])
    assert taken and taken[0][0] == "image/jpeg"

    async with sessions() as session:
        left = await session.scalar(
            text("SELECT count(*) FROM attachments WHERE attachment_id = :aid"),
            {"aid": stored["attachment_id"]},
        )
    assert left == 0, "the bytes outlived the turn that used them"


async def test_an_attachment_cannot_be_used_twice(sessions, principal_id) -> None:
    from agent_server.attachments import AttachmentRejected, AttachmentStore

    store = AttachmentStore(sessions)
    stored = await store.put(principal_id=principal_id, data=_jpeg())
    await store.take(principal_id=principal_id, ids=[stored["attachment_id"]])
    with pytest.raises(AttachmentRejected):
        await store.take(principal_id=principal_id, ids=[stored["attachment_id"]])


async def test_one_principals_photo_never_resolves_in_anothers_turn(sessions, principal_id) -> None:
    """The worst thing this module could do, so it gets its own test."""
    from agent_server.attachments import AttachmentRejected, AttachmentStore

    store = AttachmentStore(sessions)
    stored = await store.put(principal_id=principal_id, data=_jpeg())
    with pytest.raises(AttachmentRejected):
        await store.take(principal_id=f"{principal_id}-stranger", ids=[stored["attachment_id"]])
    # And it is still there for its actual owner — refused, not consumed by the attempt.
    assert await store.take(principal_id=principal_id, ids=[stored["attachment_id"]])


async def test_the_reaper_removes_what_nobody_used(sessions, principal_id) -> None:
    """The ledger's equivalent sat written-and-uncalled for weeks. This one is scheduled in
    lifespan, and this asserts it actually deletes."""
    from sqlalchemy import text

    from agent_server.attachments import AttachmentStore

    store = AttachmentStore(sessions)
    stored = await store.put(principal_id=principal_id, data=_jpeg())
    async with sessions() as session, session.begin():
        await session.execute(
            text(
                "UPDATE attachments SET created_at = now() - interval '2 hours'"
                " WHERE attachment_id = :aid"
            ),
            {"aid": stored["attachment_id"]},
        )

    assert await store.reap() >= 1
    async with sessions() as session:
        assert (
            await session.scalar(
                text("SELECT count(*) FROM attachments WHERE attachment_id = :aid"),
                {"aid": stored["attachment_id"]},
            )
            == 0
        )
