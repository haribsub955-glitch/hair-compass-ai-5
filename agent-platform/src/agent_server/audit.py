"""The audit log — what happened, never what was said.

`audit_events` has existed since the schema landed and nothing wrote to it. An empty audit table is
worse than no audit table: it looks like a control during a review and answers nothing during an
incident. This is the writer.

**Three decisions worth stating, because each one is a trade.**

*Metadata only, enforced rather than documented.* The table's docstring says "never a prompt, never
a tool result, never model output" — and a docstring stops nobody. `_screen` rejects any string that
looks like prose, so the rule fails at the write instead of quietly turning the audit log into a
second, longer-retained copy of the personal data the architecture promises not to keep. A refused
value is replaced by a marker, never dropped silently.

*Writes never fail a turn.* An audit write that raises would let a database hiccup take down the
product. So failures are logged at ERROR and counted on `dropped` — visible, never fatal. The
counter is the point: "the audit log is silently empty" and "the audit log is fine" must not look
the same from the outside. `/health` surfaces it.

*Writes are off the request path.* Events go on a bounded queue drained by one background task, so
a slow database adds latency to nothing. Bounded, because an unbounded queue in front of a stalled
consumer is a memory leak with extra steps; when it is full the oldest event is dropped and counted.

The interface is what callers see. `NullAuditLog` is the dev default, which means every call site
can emit unconditionally without asking whether auditing is configured.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import re
from datetime import UTC, datetime
from typing import Any, Protocol, runtime_checkable

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from agent_server.db.models import AuditEvent

log = logging.getLogger("agent_server.audit")

#: How many events may wait for the database before the oldest is dropped. Sized for a burst, not
#: for an outage: if the queue is ever near full the database is the problem, and buffering more of
#: them just delays finding that out.
QUEUE_LIMIT = 1000

#: Longest string any single detail value may be. An identifier, an enum, a rule name or a version
#: fits easily; a sentence does not. This is the blunt half of the prose screen.
MAX_VALUE_CHARS = 120

#: More than this many keys and someone is dumping a payload in rather than recording a fact.
MAX_DETAIL_KEYS = 24

#: A value that is refused, kept as a value so the KEY still shows up in the log. "There was a
#: rejected field here" is information; a missing key is indistinguishable from a bug.
REDACTED = "<redacted:not-metadata>"

#: Prose looks like words separated by spaces. Identifiers, enum names, versions, hashes and
#: dotted paths do not contain spaces at all.
#:
#: **TWO runs, not three.** Three let "hair loss", an email with a display name, or any short
#: phrase through — and a two-word fragment of someone's question is still their data. The decision
#: strings we genuinely want to keep are matched by the allow-list below, so the regex does not
#: need to be generous.
_PROSE = re.compile(r"\S+\s+\S+")

#: Short decision strings that are prose-shaped but are ours, not the user's. Anything a MODEL or
#: a USER produced can never be on this list — that is the distinction the screen exists to make.
_ALLOWED_PHRASES = frozenset(
    {
        "out of scope",
        "budget exhausted",
        "iteration cap reached",
        "provider unavailable",
        "unknown tool result",
        "subscription not active",
        "receipt claimed by another principal",
    }
)


class AuditEventName:
    """The event vocabulary, in one place.

    A string literal at each call site drifts — `turn.complete` in one file, `turn_completed` in
    another, and a query that answers "how many turns failed" quietly misses half of them.
    """

    SESSION_STARTED = "session.started"
    SUBSCRIPTION_VERIFIED = "subscription.verified"
    SUBSCRIPTION_REJECTED = "subscription.rejected"
    PLAN_CHANGED = "plan.changed"
    TURN_STARTED = "turn.started"
    TURN_COMPLETED = "turn.completed"
    TURN_FAILED = "turn.failed"
    SCOPE_REFUSED = "scope.refused"
    SAFETY_BLOCKED = "safety.blocked"
    QUOTA_EXHAUSTED = "quota.exhausted"
    RATE_LIMITED = "ratelimit.tripped"
    CONSENT_GRANTED = "consent.granted"
    CONSENT_WITHDRAWN = "consent.withdrawn"
    DATA_EXPORTED = "data.exported"
    DATA_DELETED = "data.deleted"


def _screen(detail: dict[str, Any] | None) -> dict[str, Any]:
    """Reduce a detail dict to things that are safely metadata.

    Numbers and booleans pass untouched — a token count or a decision flag cannot leak content.
    Strings must be short and not prose-shaped. Nested structures are refused outright rather than
    walked: a nested dict is how a whole request body ends up in an audit row, and there is no
    legitimate audit fact that needs one.
    """
    if not detail:
        return {}
    screened: dict[str, Any] = {}
    for key, value in list(detail.items())[:MAX_DETAIL_KEYS]:
        if isinstance(value, bool | int | float) or value is None:
            screened[key] = value
        elif isinstance(value, str):
            stripped = value.strip()
            if stripped in _ALLOWED_PHRASES:
                screened[key] = stripped
            elif len(stripped) > MAX_VALUE_CHARS or _PROSE.search(stripped):
                screened[key] = REDACTED
            else:
                screened[key] = stripped
        else:
            screened[key] = REDACTED
    if len(detail) > MAX_DETAIL_KEYS:
        screened["_truncated"] = len(detail) - MAX_DETAIL_KEYS
    return screened


@runtime_checkable
class AuditLog(Protocol):
    def record(
        self,
        event: str,
        *,
        principal_id: str,
        device_id: str = "",
        turn_id: str = "",
        detail: dict[str, Any] | None = None,
    ) -> None:
        """Record an event. Deliberately NOT async and never raises — a call site must be able to
        audit a failure path without adding a second failure path."""
        ...


class NullAuditLog(AuditLog):
    """The default. Counts what it was asked to record so a test can assert on call sites, and
    logs at DEBUG so a dev loop can see the stream without a database."""

    def __init__(self) -> None:
        self.events: list[tuple[str, dict[str, Any]]] = []

    def record(
        self,
        event: str,
        *,
        principal_id: str,
        device_id: str = "",
        turn_id: str = "",
        detail: dict[str, Any] | None = None,
    ) -> None:
        screened = _screen(detail)
        self.events.append((event, screened))
        log.debug("audit %s principal=%s detail=%s", event, principal_id, screened)


class PostgresAuditLog(AuditLog):
    """Durable audit, written off the request path by one background drainer."""

    def __init__(self, sessions: async_sessionmaker[AsyncSession]) -> None:
        self._sessions = sessions
        self._queue: asyncio.Queue[AuditEvent] = asyncio.Queue(maxsize=QUEUE_LIMIT)
        self._task: asyncio.Task[None] | None = None
        #: Events lost to a full queue or a failed write. Never silently zero — `/health` reads it,
        #: because an audit log that stopped working must not look the same as one that is quiet.
        self.dropped = 0
        self.written = 0

    def start(self) -> None:
        if self._task is None or self._task.done():
            self._task = asyncio.create_task(self._drain(), name="audit-drain")

    async def stop(self, *, timeout: float = 5.0) -> None:
        """Flush what is queued, then stop. Called from the app's lifespan shutdown.

        Bounded by a TIMEOUT as well as by the queue. `queue.join()` waits for a `task_done()` per
        item, so if the drainer already died — cancelled, or wedged on a database with no connect
        timeout — the join never returns and shutdown hangs forever. A hung shutdown is worse than
        a few lost audit rows: the process will not restart, and the deploy that was meant to fix
        the database never lands.
        """
        if self._task is None or self._task.done():
            self._task = None
            return
        try:
            await asyncio.wait_for(self._queue.join(), timeout=timeout)
        except TimeoutError:
            self.dropped += self._queue.qsize()
            log.error(
                "audit queue did not drain in %.1fs — abandoning %d events (total dropped: %d)",
                timeout,
                self._queue.qsize(),
                self.dropped,
            )
        self._task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await self._task
        self._task = None

    def record(
        self,
        event: str,
        *,
        principal_id: str,
        device_id: str = "",
        turn_id: str = "",
        detail: dict[str, Any] | None = None,
    ) -> None:
        # `installation_id` is an unconstrained client-supplied string, and it used to land in
        # `device_id` verbatim — so `_screen` guarded `detail` while the caller could put anything
        # at all in the column next to it. Screened like any other value.
        row = AuditEvent(
            principal_id=principal_id,
            device_id=str(_screen({"d": device_id}).get("d", ""))[:128],
            event=event[:48],
            turn_id=turn_id[:64],
            detail=_screen(detail),
            occurred_at=datetime.now(UTC),
        )
        try:
            self._queue.put_nowait(row)
        except asyncio.QueueFull:
            # Drop the NEWEST rather than evicting the oldest. Under sustained overload the early
            # events are the ones that explain how it started; the tail is the symptom.
            self.dropped += 1
            log.error("audit queue full, dropped %s (total dropped: %d)", event, self.dropped)

    async def _drain(self) -> None:
        while True:
            row = await self._queue.get()
            try:
                async with self._sessions() as session, session.begin():
                    session.add(row)
                self.written += 1
            except Exception:
                self.dropped += 1
                # Never re-raised: an audit write must not be able to take down the product. Logged
                # with the exception so it is diagnosable, counted so it is visible.
                log.exception(
                    "audit write failed for %s (total dropped: %d)", row.event, self.dropped
                )
            finally:
                self._queue.task_done()

    async def recent(self, principal_id: str, *, limit: int = 100) -> list[dict[str, Any]]:
        """The events for one principal, newest first.

        Scoped to a principal because that is the only shape the app needs — a user asking what the
        service did with their data, and support answering "why was I refused". A global feed would
        be a cross-tenant read with no caller.
        """
        from sqlalchemy import select

        async with self._sessions() as session:
            rows = await session.execute(
                select(AuditEvent)
                .where(AuditEvent.principal_id == principal_id)
                .order_by(AuditEvent.occurred_at.desc(), AuditEvent.id.desc())
                .limit(min(limit, 500))
            )
            return [
                {
                    "event": row.event,
                    "turn_id": row.turn_id,
                    "detail": row.detail,
                    "occurred_at": row.occurred_at.isoformat(),
                }
                for row in rows.scalars()
            ]
