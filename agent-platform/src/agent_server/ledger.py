"""The cost ledger — reserve before spending, reconcile after.

Why not just check a counter before the call: two turns for the same user can run concurrently, both
read "budget remaining", both pass, and both spend. A pre-call boolean is raceable by construction,
which is the defect the external review flagged in the ported router. So the sequence is:

    reserve(worst case)  ->  provider call  ->  settle(actual)

The reservation is deducted immediately and atomically, so a concurrent turn sees the money as
already spent. Settling refunds the difference. If a turn dies between reserve and settle, the
reservation stays deducted until it expires — the user is briefly over-charged against their quota
rather than the system being under-charged, which is the correct direction to fail.

`InMemoryLedger` is for development and tests. The Postgres implementation lands with persistence;
this interface is what it must satisfy, and the tests here define the contract.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from typing import Protocol, runtime_checkable
from uuid import uuid4

from agent_core.contracts import Usage
from agent_server.core.errors import QuotaExhausted


@dataclass(frozen=True, slots=True)
class Reservation:
    id: str
    principal_id: str
    day: date
    amount: int


@runtime_checkable
class CostLedger(Protocol):
    async def reserve(self, principal_id: str, amount: int) -> Reservation: ...
    async def settle(self, reservation: Reservation, usage: Usage) -> None: ...
    async def release(self, reservation: Reservation) -> None: ...
    async def spent_today(self, principal_id: str) -> int: ...


def _today() -> date:
    return datetime.now(UTC).date()


@dataclass
class InMemoryLedger(CostLedger):
    daily_budget: int
    _spent: dict[tuple[str, date], int] = field(default_factory=dict)
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def reserve(self, principal_id: str, amount: int) -> Reservation:
        if amount <= 0:
            raise ValueError("a reservation must be positive")
        day = _today()
        async with self._lock:
            key = (principal_id, day)
            current = self._spent.get(key, 0)
            if current + amount > self.daily_budget:
                raise QuotaExhausted(
                    f"principal={principal_id} spent={current} "
                    f"requested={amount} budget={self.daily_budget}"
                )
            self._spent[key] = current + amount
        return Reservation(id=uuid4().hex, principal_id=principal_id, day=day, amount=amount)

    async def settle(self, reservation: Reservation, usage: Usage) -> None:
        """Reconcile to actual. Actual above the reservation is kept in full rather than capped —
        the money was really spent, and hiding it would let a series of under-estimates walk past
        the daily budget."""
        actual = usage.input_tokens + usage.output_tokens
        delta = actual - reservation.amount
        async with self._lock:
            key = (reservation.principal_id, reservation.day)
            self._spent[key] = max(0, self._spent.get(key, 0) + delta)

    async def release(self, reservation: Reservation) -> None:
        """Give back the whole reservation — the call never reached the provider, so nothing was
        spent. Distinct from `settle`, which always records a real cost."""
        async with self._lock:
            key = (reservation.principal_id, reservation.day)
            self._spent[key] = max(0, self._spent.get(key, 0) - reservation.amount)

    async def spent_today(self, principal_id: str) -> int:
        async with self._lock:
            return self._spent.get((principal_id, _today()), 0)
