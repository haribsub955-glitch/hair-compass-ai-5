"""The cost ledger. The test that matters is the concurrency one.

The external review's finding was that a pre-call `budget_ok` boolean is raceable: two turns read
"there's room", both proceed, both spend. `test_concurrent_reservations_cannot_exceed_the_budget`
is that exact scenario, and it is why `reserve` deducts rather than merely checks.
"""

from __future__ import annotations

import asyncio

import pytest

from agent_core.contracts import Usage
from agent_server.core.errors import QuotaExhausted
from agent_server.ledger import InMemoryLedger


async def test_reserve_deducts_immediately_so_a_concurrent_turn_sees_it_gone() -> None:
    ledger = InMemoryLedger(daily_budget=1000)
    await ledger.reserve("p1", 600)
    assert await ledger.spent_today("p1") == 600


async def test_concurrent_reservations_cannot_exceed_the_budget() -> None:
    """Ten turns race for a budget that fits six. Exactly six may win."""
    ledger = InMemoryLedger(daily_budget=600)
    results = await asyncio.gather(
        *(ledger.reserve("p1", 100) for _ in range(10)), return_exceptions=True
    )
    granted = [r for r in results if not isinstance(r, BaseException)]
    refused = [r for r in results if isinstance(r, QuotaExhausted)]
    assert len(granted) == 6
    assert len(refused) == 4
    assert await ledger.spent_today("p1") == 600


async def test_settle_refunds_the_unused_reservation() -> None:
    ledger = InMemoryLedger(daily_budget=1000)
    reservation = await ledger.reserve("p1", 500)
    await ledger.settle(reservation, Usage(input_tokens=80, output_tokens=20))
    assert await ledger.spent_today("p1") == 100


async def test_settle_keeps_an_overrun_rather_than_capping_it() -> None:
    """The money was really spent. Capping to the reservation would let a run of under-estimates
    walk past the daily budget unnoticed."""
    ledger = InMemoryLedger(daily_budget=10_000)
    reservation = await ledger.reserve("p1", 100)
    await ledger.settle(reservation, Usage(input_tokens=400, output_tokens=200))
    assert await ledger.spent_today("p1") == 600


async def test_release_gives_back_everything_when_the_call_never_happened() -> None:
    ledger = InMemoryLedger(daily_budget=1000)
    reservation = await ledger.reserve("p1", 500)
    await ledger.release(reservation)
    assert await ledger.spent_today("p1") == 0


async def test_budgets_do_not_leak_between_principals() -> None:
    ledger = InMemoryLedger(daily_budget=500)
    await ledger.reserve("p1", 500)
    await ledger.reserve("p2", 500)  # must not be blocked by p1
    assert await ledger.spent_today("p1") == 500
    assert await ledger.spent_today("p2") == 500


async def test_exhausted_quota_raises_rather_than_silently_truncating() -> None:
    ledger = InMemoryLedger(daily_budget=100)
    with pytest.raises(QuotaExhausted):
        await ledger.reserve("p1", 101)


async def test_a_non_positive_reservation_is_a_programming_error() -> None:
    ledger = InMemoryLedger(daily_budget=100)
    with pytest.raises(ValueError):
        await ledger.reserve("p1", 0)
