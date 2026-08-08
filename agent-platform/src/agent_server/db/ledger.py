"""The Postgres cost ledger — the same `CostLedger` contract, but it survives a restart.

`InMemoryLedger` had one defect that only shows in production: **budgets reset when the process
does.** A user who burned their daily quota gets a fresh one on the next deploy. That is a money
leak, not a rough edge, and it is why this table exists before any of the others.

The interesting part is `reserve`. A budget check that reads then writes is raceable — two turns
both see room, both spend, and the cap is a suggestion. The in-memory version papered over that
with an `asyncio.Lock`, which works inside one process and not at all across two.

Here it is one statement:

    INSERT … VALUES (amount)
    ON CONFLICT (principal_id, day) DO UPDATE
       SET spent = spend.spent + amount
     WHERE spend.spent + amount <= budget
    RETURNING spent

Postgres evaluates that atomically. Either a row comes back and the money is held, or nothing comes
back and the budget is gone. No lock, correct across any number of processes, and it stays correct
on Supabase because it is ordinary Postgres.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping
from datetime import UTC, date, datetime
from uuid import uuid4

from sqlalchemy import delete, select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from agent_core.contracts import Usage
from agent_server.core.errors import QuotaExhausted
from agent_server.db.models import DailySpend, Reservation
from agent_server.ledger import CostLedger
from agent_server.ledger import Reservation as ReservationHandle

#: An unsettled reservation older than this is assumed orphaned — the turn that made it died
#: between reserving and settling. Held money that nobody will ever settle is indistinguishable
#: from spent money, so it has to be reclaimable.
ORPHAN_AFTER_SECONDS = 15 * 60


def _today() -> date:
    return datetime.now(UTC).date()


class PostgresLedger(CostLedger):
    """Durable, multi-process-safe implementation of the same protocol the tests already define."""

    def __init__(
        self,
        sessions: async_sessionmaker[AsyncSession],
        *,
        daily_budget: int,
        total_budget: int = 0,
        window_days: int = 1,
        limits_for: Callable[[str], Mapping[str, int]] | None = None,
    ) -> None:
        """The three budget arguments are the FALLBACK, used when `limits_for` is absent.

        `limits_for` maps a plan id to that plan's limits, and is how a per-principal budget is
        enforced at all. Without it the ledger holds one budget for every user, which is what the
        server actually shipped: the trial's 7-day window and 540k lifetime cap were defined in
        `plans.py`, asserted in tests that passed the numbers by hand, and disabled everywhere else
        because wiring only ever passed `daily_budget`.
        """
        self._sessions = sessions
        self._limits_for = limits_for
        #: The recurring allowance, spent over `window_days`.
        self.daily_budget = daily_budget
        #: 1 = a daily cap enforced by one atomic statement. >1 = a rolling window, checked
        #: read-then-write. Rolling rather than calendar weeks on purpose: a Monday reset is
        #: gameable at the boundary (spend the whole allowance Sunday night, again Monday morning).
        self.window_days = window_days
        #: Lifetime ceiling for the current plan period. `0` disables it — a renewing subscription
        #: has no lifetime to budget, only a time-limited plan does.
        self.total_budget = total_budget

    async def _limits(self, principal_id: str) -> tuple[int, int, int]:
        """This principal's (daily, total, window_days), from their plan.

        Read per reserve rather than cached: a plan can change mid-session — a trial ending, a
        subscription lapsing — and a cached limit would keep granting the old allowance until the
        process restarted.
        """
        if self._limits_for is None:
            return self.daily_budget, self.total_budget, self.window_days
        async with self._sessions() as session:
            plan_id = await session.scalar(
                text("SELECT entitlement FROM principals WHERE principal_id = :pid"),
                {"pid": principal_id},
            )
        limits = self._limits_for(plan_id or "")
        return (
            int(limits["daily_budget"]),
            int(limits["total_budget"]),
            int(limits["window_days"]),
        )

    async def reserve(self, principal_id: str, amount: int) -> ReservationHandle:
        if amount <= 0:
            raise ValueError("a reservation must be positive")
        daily_budget, total_budget, window_days = await self._limits(principal_id)
        if amount > daily_budget:
            # Would never fit even on an untouched day. Rejecting here keeps the atomic statement
            # below meaning exactly one thing: "the budget is already spent".
            raise QuotaExhausted(
                f"principal={principal_id} requested={amount} budget={daily_budget}"
            )

        day = _today()
        statement = text(
            """
            INSERT INTO principal_daily_spend (principal_id, day, spent, updated_at)
            VALUES (:principal_id, :day, :amount, now())
            ON CONFLICT (principal_id, day) DO UPDATE
               SET spent = principal_daily_spend.spent + :amount,
                   updated_at = now()
             WHERE principal_daily_spend.spent + :amount <= :budget
            RETURNING spent
            """
        )

        async with self._sessions() as session, session.begin():
            # Serialise every reserve for THIS principal, and only this one.
            #
            # The window and lifetime caps span rows, so they cannot ride on the single-row atomic
            # statement below. Checking them read-then-write was wrong — and my estimate of HOW
            # wrong was also wrong. I reasoned the overshoot was "one turn"; measured against a
            # real Postgres it was six. N concurrent requests all read the same total, all pass,
            # and each then spends up to the DAILY budget, so a 540k lifetime cap behind a 180k
            # daily cap does not bound a trial at all.
            #
            # A row lock on the principal makes all three checks one critical section. It costs one
            # lock per reserve and blocks only that user's own concurrent turns, which the model
            # call already serialises in practice.
            locked = (
                await session.execute(
                    text("SELECT 1 FROM principals WHERE principal_id = :pid FOR UPDATE"),
                    {"pid": principal_id},
                )
            ).first()
            if locked is None:
                # `FOR UPDATE` on zero rows locks NOTHING, and the empty result used to be ignored
                # — so concurrent reserves for an unregistered principal serialised on nothing and
                # walked straight past both aggregate caps. Refusing is safe because every real
                # caller registers the principal before it can spend (VerifyingPrincipalSource), so
                # reaching here means a bug or a deleted account, and neither should get budget.
                raise QuotaExhausted(f"principal={principal_id} is not registered")

            if window_days > 1 and daily_budget:
                in_window = await self._window_total(session, principal_id, window_days)
                if in_window + amount > daily_budget:
                    raise QuotaExhausted(
                        f"principal={principal_id} used={in_window} requested={amount} "
                        f"window={window_days}d budget={daily_budget}"
                    )

            if total_budget:
                already = await self._plan_period_total(session, principal_id)
                if already + amount > total_budget:
                    raise QuotaExhausted(
                        f"principal={principal_id} used={already} requested={amount} "
                        f"total_budget={total_budget}"
                    )

            row = (
                await session.execute(
                    statement,
                    {
                        "principal_id": principal_id,
                        "day": day,
                        "amount": amount,
                        # With a multi-day window the per-day statement is a backstop against a
                        # single-day blowout, not the real cap — the window check above owns that.
                        "budget": daily_budget,
                    },
                )
            ).first()
            if row is None:
                raise QuotaExhausted(
                    f"principal={principal_id} requested={amount} budget={daily_budget}"
                )

            handle = ReservationHandle(
                id=uuid4().hex, principal_id=principal_id, day=day, amount=amount
            )
            session.add(
                Reservation(id=handle.id, principal_id=principal_id, day=day, amount=amount)
            )
            return handle

    async def settle(self, reservation: ReservationHandle, usage: Usage) -> None:
        """Reconcile the held amount to what was actually spent.

        An overrun is kept in full rather than capped: the money really was spent, and hiding it
        would let a run of under-estimates walk past the daily budget. The floor at zero is a
        `CHECK` on the table, so a double-settle surfaces as a constraint violation instead of as
        free quota.
        """
        actual = usage.input_tokens + usage.output_tokens
        delta = actual - reservation.amount
        await self._adjust(reservation, delta)

    async def release(self, reservation: ReservationHandle) -> None:
        """Give the whole amount back — the call never reached the provider."""
        await self._adjust(reservation, -reservation.amount)

    async def _adjust(self, reservation: ReservationHandle, delta: int) -> None:
        async with self._sessions() as session, session.begin():
            # Mark the reservation settled first. If this row is already settled the UPDATE
            # affects nothing and we return without touching the total — which is what makes a
            # duplicate settle harmless rather than a second refund.
            settled = await session.execute(
                text(
                    """
                    UPDATE cost_reservations SET settled_at = now()
                     WHERE id = :id AND settled_at IS NULL
                    RETURNING id
                    """
                ),
                {"id": reservation.id},
            )
            if settled.first() is None:
                return

            if delta != 0:
                await session.execute(
                    text(
                        """
                        UPDATE principal_daily_spend
                           SET spent = GREATEST(0, spent + :delta), updated_at = now()
                         WHERE principal_id = :principal_id AND day = :day
                        """
                    ),
                    {
                        "delta": delta,
                        "principal_id": reservation.principal_id,
                        "day": reservation.day,
                    },
                )

    async def spent_today(self, principal_id: str) -> int:
        async with self._sessions() as session:
            total = await session.scalar(
                select(DailySpend.spent).where(
                    DailySpend.principal_id == principal_id, DailySpend.day == _today()
                )
            )
            return int(total or 0)

    #: `:today` comes from Python rather than SQL's `CURRENT_DATE`, because `CURRENT_DATE`
    #: evaluates in the DATABASE's timezone while every other date here comes from
    #: `datetime.now(UTC)`. A database not set to UTC shifts the window by a day around midnight —
    #: the kind of drift that produces one unreproducible bug report a month.
    _WINDOW_SQL = text(
        """
        SELECT COALESCE(SUM(spent), 0) FROM principal_daily_spend
         WHERE principal_id = :pid
           AND day > CAST(:today AS date) - CAST(:days AS integer)
        """
    )

    #: `plan_started_at` is NULL for any principal registered before it was populated. The fallback
    #: must be a date that INCLUDES everything (the epoch) — the previous `s.day` fallback compared
    #: a row to itself, which is always true, silently turning a plan-period total into an all-time
    #: one and charging a returning user for spend from a plan they no longer hold.
    _PLAN_PERIOD_SQL = text(
        """
        SELECT COALESCE(SUM(s.spent), 0) FROM principal_daily_spend s
         WHERE s.principal_id = :pid
           AND s.day >= COALESCE(
                 (SELECT p.plan_started_at::date FROM principals p
                   WHERE p.principal_id = :pid),
                 DATE '1970-01-01')
        """
    )

    @staticmethod
    async def _window_total(session: AsyncSession, principal_id: str, days: int) -> int:
        total = await session.scalar(
            PostgresLedger._WINDOW_SQL,
            {"pid": principal_id, "days": days, "today": _today()},
        )
        return int(total or 0)

    @staticmethod
    async def _plan_period_total(session: AsyncSession, principal_id: str) -> int:
        total = await session.scalar(PostgresLedger._PLAN_PERIOD_SQL, {"pid": principal_id})
        return int(total or 0)

    async def spent_in_window(self, principal_id: str, *, days: int) -> int:
        """Spend over the trailing `days`, inclusive of today.

        Rolling, not calendar. A calendar week resets on a fixed day, which lets someone spend the
        whole allowance on Sunday night and the whole of the next one on Monday morning.
        """
        async with self._sessions() as session:
            return await self._window_total(session, principal_id, days)

    async def spent_in_plan_period(self, principal_id: str) -> int:
        """Everything spent since the current plan started.

        Summed from the daily rows rather than kept as a second counter, so there is one source of
        truth and no way for the two to disagree. Scoped to `plan_started_at` so upgrading from
        trial to paid does not carry the trial's spend into the new plan.
        """
        async with self._sessions() as session:
            return await self._plan_period_total(session, principal_id)

    async def reclaim_orphans(self) -> int:
        """Release reservations whose turn died before settling. Returns how many.

        Without this, a crash mid-turn holds a worst-case amount against someone's daily budget
        forever — they lose quota to an outage that was never their fault, and no amount of waiting
        gives it back.
        """
        async with self._sessions() as session, session.begin():
            cutoff = text(f"now() - interval '{ORPHAN_AFTER_SECONDS} seconds'")
            orphans = (
                await session.execute(
                    text(
                        f"""
                        SELECT id, principal_id, day, amount FROM cost_reservations
                         WHERE settled_at IS NULL AND created_at < {cutoff}
                         FOR UPDATE SKIP LOCKED
                        """
                    )
                )
            ).all()
            for row in orphans:
                await session.execute(
                    text(
                        """
                        UPDATE principal_daily_spend
                           SET spent = GREATEST(0, spent - :amount), updated_at = now()
                         WHERE principal_id = :principal_id AND day = :day
                        """
                    ),
                    {"amount": row.amount, "principal_id": row.principal_id, "day": row.day},
                )
            if orphans:
                await session.execute(
                    delete(Reservation).where(Reservation.id.in_([r.id for r in orphans]))
                )
            return len(orphans)
