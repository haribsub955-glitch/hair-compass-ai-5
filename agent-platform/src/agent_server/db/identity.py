"""Principals, devices and consent — the durable half of "who is this and what did they agree to".

`DevPrincipalSource` derives a principal by HMAC and stores nothing, which is fine for a dev loop
and useless for anything real: with no row there is no account linking, no reinstall recovery, and
no deletion — and deletion is not optional once an app has accounts.

This records them. A device registers itself the first time it opens a session; nothing manual.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime

from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from agent_core.contracts import Entitlement, Principal
from agent_server.db.models import ConsentRecord, Device, Identity

log = logging.getLogger("agent_server.identity")


class IdentityStore:
    """Upserts principals and devices, and records consent."""

    def __init__(self, sessions: async_sessionmaker[AsyncSession]) -> None:
        self._sessions = sessions

    async def set_plan(
        self,
        principal_id: str,
        *,
        plan_id: str,
        subscription_txn_id: str | None = None,
    ) -> bool:
        """Move a principal onto a plan. False if the subscription belongs to someone else.

        **Two things happen here that the ledger silently depended on and nothing was doing.**

        `plan_started_at` is stamped whenever the plan actually changes. Without it the lifetime
        trial cap has no window to measure and degrades to an all-time total - so a returning user
        is charged for spend from a plan they no longer hold. Only stamped on a *change*, or every
        session would reset the trial clock and the cap would never bind.

        `subscription_txn_id` is claimed under the unique constraint, which is what makes a
        StoreKit receipt non-transferable. A second principal replaying an extracted receipt hits
        an IntegrityError and gets False - refused by Postgres rather than by a code path.

        The `CAST(... AS varchar)`s are not decoration. asyncpg infers a parameter's type from its
        first use, and `:plan_id` appears both as an assignment to a varchar column and inside
        `IS DISTINCT FROM`; without the casts it deduces `text` in one place and `varchar` in the
        other and refuses the whole statement with AmbiguousParameterError. It only surfaces
        against a real Postgres, which is why this has a test that needs one.
        """
        try:
            async with self._sessions() as session, session.begin():
                result = await session.execute(
                    text(
                        """
                        UPDATE principals
                           SET entitlement = CAST(:plan_id AS varchar),
                               plan_started_at = CASE
                                   WHEN entitlement IS DISTINCT FROM CAST(:plan_id AS varchar)
                                   THEN now() ELSE plan_started_at END,
                               subscription_txn_id = COALESCE(
                                   CAST(:txn AS varchar), subscription_txn_id)
                         WHERE principal_id = :pid
                        RETURNING plan_started_at
                        """
                    ),
                    {"pid": principal_id, "plan_id": plan_id, "txn": subscription_txn_id},
                )
                return result.first() is not None
        except IntegrityError:
            # The transaction id is already claimed by a different principal. Deliberately not
            # distinguished from any other failure to the caller - telling a prober "that receipt
            # belongs to someone else" confirms the receipt is real.
            log.warning("subscription already claimed by another principal")
            return False

    async def register(
        self,
        principal: Principal,
        *,
        platform: str = "unknown",
        app_build: str = "",
        os_version: str = "",
    ) -> None:
        """Record this principal and the device it is speaking from.

        Upserts rather than inserts, because this runs on **every** session — a returning device
        must update `last_seen_at`, not collide. Written as one statement per table so a concurrent
        session from the same device cannot race into a duplicate-key error.

        A device moving to a different principal is treated as the device being re-registered, not
        as a conflict: that is what a reinstall followed by a subscription restore looks like.

        **`entitlement` is written on INSERT and never on conflict.** It used to be updated here,
        which quietly broke two things at once: the column holds the PLAN id, `register` was being
        handed a two-case enum value, and the ledger reads that column to resolve limits — so a
        trial user briefly resolved to pro's budget on every session, and `set_plan` then saw the
        value as changed and re-stamped `plan_started_at`, resetting the 90-day lifetime cap. The
        plan belongs to `set_plan`; this records that a device was seen.
        """
        now = datetime.now(UTC)
        async with self._sessions() as session, session.begin():
            await session.execute(
                text(
                    """
                    INSERT INTO principals
                        (principal_id, app_id, tenant_id, entitlement, created_at, last_seen_at)
                    VALUES (:principal_id, :app_id, :tenant_id, :entitlement, :now, :now)
                    ON CONFLICT (principal_id) DO UPDATE
                       SET last_seen_at = EXCLUDED.last_seen_at
                    """
                ),
                {
                    "principal_id": principal.principal_id,
                    "app_id": principal.app_id,
                    "tenant_id": principal.tenant_id,
                    "entitlement": principal.entitlement.value,
                    "now": now,
                },
            )
            await session.execute(
                text(
                    """
                    INSERT INTO devices
                        (device_id, principal_id, app_id, platform, app_build, os_version,
                         first_seen_at, last_seen_at)
                    VALUES (:device_id, :principal_id, :app_id, :platform, :app_build,
                            :os_version, :now, :now)
                    ON CONFLICT (device_id) DO UPDATE
                       SET principal_id = EXCLUDED.principal_id,
                           platform = EXCLUDED.platform,
                           app_build = EXCLUDED.app_build,
                           os_version = EXCLUDED.os_version,
                           last_seen_at = EXCLUDED.last_seen_at
                    """
                ),
                {
                    "device_id": principal.installation_id,
                    "principal_id": principal.principal_id,
                    "app_id": principal.app_id,
                    "platform": platform,
                    "app_build": app_build,
                    "os_version": os_version,
                    "now": now,
                },
            )

    async def standing(self, principal_id: str) -> tuple[datetime | None, bool]:
        """`(created_at, has_ever_subscribed)` — what the taster decision needs.

        Both facts come from the SERVER's own rows, never from the client. A taster measured on a
        clock the app controls is a taster that lasts as long as the app says it does.

        `has_ever_subscribed` is read from `subscription_txn_id`, which is set the first time a
        receipt is verified and never cleared. It is what stops a lapsed subscriber from being
        handed the introductory freebie again every time their card fails.
        """
        async with self._sessions() as session:
            row = (
                await session.execute(
                    text(
                        "SELECT created_at, subscription_txn_id FROM principals "
                        " WHERE principal_id = :pid"
                    ),
                    {"pid": principal_id},
                )
            ).first()
            if row is None:
                return None, False
            return row.created_at, row.subscription_txn_id is not None

    # --- device binding -----------------------------------------------------------------------

    async def bound_device(self, installation_id: str):
        """The key this installation must sign with, or `None` if it has never been claimed."""
        from agent_server.devicebind import BoundDevice

        async with self._sessions() as session:
            row = (
                await session.execute(
                    text(
                        "SELECT public_key, attested, counter FROM device_keys "
                        " WHERE installation_id = :iid"
                    ),
                    {"iid": installation_id},
                )
            ).first()
        if row is None:
            return None
        return BoundDevice(
            installation_id=installation_id,
            public_key_der=bytes(row.public_key),
            attested=row.attested,
            counter=row.counter,
        )

    async def bind_device(
        self, installation_id: str, *, public_key: bytes, attested: bool = False
    ) -> bool:
        """Claim an unclaimed installation id. Returns False if somebody already holds it.

        `ON CONFLICT DO NOTHING` rather than an upsert, and that is the entire security property:
        an upsert would let anyone rebind a key they do not hold, which is the takeover this
        prevents. Two devices racing for a fresh id is decided by the database, once.
        """
        async with self._sessions() as session, session.begin():
            result = await session.execute(
                text(
                    """
                    INSERT INTO device_keys (installation_id, public_key, attested, counter)
                    VALUES (:iid, :key, :attested, 0)
                    ON CONFLICT (installation_id) DO NOTHING
                    RETURNING installation_id
                    """
                ),
                {"iid": installation_id, "key": public_key, "attested": attested},
            )
            return result.first() is not None

    async def record_proof(self, installation_id: str, *, counter: int | None = None) -> None:
        """Note that a device proved itself, and advance its assertion counter.

        The counter only ever moves FORWARD (`GREATEST`), because a replayed assertion carrying an
        older value must not be able to rewind it and make itself valid again next time.
        """
        async with self._sessions() as session, session.begin():
            await session.execute(
                text(
                    """
                    UPDATE device_keys
                       SET last_proof_at = now(),
                           counter = GREATEST(counter, COALESCE(:counter, counter))
                     WHERE installation_id = :iid
                    """
                ),
                {"iid": installation_id, "counter": counter},
            )

    async def devices_for(self, principal_id: str) -> list[str]:
        """Every installation this person has. One principal, several devices is normal."""
        async with self._sessions() as session:
            rows = await session.scalars(
                select(Device.device_id).where(Device.principal_id == principal_id)
            )
            return list(rows)

    # --- consent ---------------------------------------------------------------------------

    async def grant(
        self,
        principal_id: str,
        *,
        purpose: str,
        policy_version: str,
        crosses_border: bool,
    ) -> None:
        """Record a grant. Appends rather than updates, so the history stays readable.

        A grant for a purpose that is already live is a no-op — re-affirming consent should not
        produce a second row that makes the audit trail look like the user was asked twice.

        **`crosses_border` is part of "the same terms".** It was not, and that was a real
        divergence: someone who first consented to local-only processing and later agreed to a
        cross-border transfer would hit the early return, and the record would permanently say they
        had only agreed to the narrower thing. Under PDPL a transfer is separately consentable, so
        a change in that flag is a new grant, not a duplicate.
        """
        if await self.has_consent(
            principal_id,
            purpose=purpose,
            policy_version=policy_version,
            crosses_border=crosses_border,
        ):
            return
        async with self._sessions() as session, session.begin():
            session.add(
                ConsentRecord(
                    principal_id=principal_id,
                    purpose=purpose,
                    policy_version=policy_version,
                    crosses_border=crosses_border,
                    granted_at=datetime.now(UTC),
                )
            )

    async def withdraw(self, principal_id: str, *, purpose: str) -> int:
        """Withdraw every live grant for a purpose. Returns how many were closed.

        Withdrawal is the half people forget: consent that cannot be taken back is not consent.
        This stops the *permission*; deleting what was already synced is a separate, deliberate
        step, because "stop collecting" and "erase what you have" are different requests and a
        user may want either.
        """
        async with self._sessions() as session, session.begin():
            result = await session.execute(
                text(
                    """
                    UPDATE consent_records SET withdrawn_at = now()
                     WHERE principal_id = :principal_id AND purpose = :purpose
                       AND withdrawn_at IS NULL
                    RETURNING id
                    """
                ),
                {"principal_id": principal_id, "purpose": purpose},
            )
            return len(result.all())

    async def has_consent(
        self,
        principal_id: str,
        *,
        purpose: str,
        policy_version: str | None = None,
        crosses_border: bool | None = None,
    ) -> bool:
        """Is there a live grant for this purpose, on these terms?

        When `policy_version` is given, a grant against an OLDER policy does not count. Silently
        carrying consent across a policy change is how "they agreed" stops meaning anything — if
        the terms moved, the question has to be asked again.

        `crosses_border` narrows the same way. PDPL treats the transfer as a separate act needing
        its own explicit consent, so a grant recorded as local-only does not answer "may we send
        this to Frankfurt".
        """
        async with self._sessions() as session:
            query = (
                select(ConsentRecord.id)
                .where(
                    ConsentRecord.principal_id == principal_id,
                    ConsentRecord.purpose == purpose,
                    ConsentRecord.withdrawn_at.is_(None),
                )
                .limit(1)
            )
            if policy_version is not None:
                query = query.where(ConsentRecord.policy_version == policy_version)
            if crosses_border is not None:
                query = query.where(ConsentRecord.crosses_border == crosses_border)
            return await session.scalar(query) is not None

    # --- federated sign-in ------------------------------------------------------------------
    #
    # Not wired to any endpoint yet — no provider is integrated. These exist because the *shape*
    # of the transition is what matters, and getting it wrong after real users exist means merging
    # accounts by hand.

    async def resolve(self, *, provider: str, subject: str) -> str | None:
        """Which principal owns this provider account? `None` means it has never been seen."""
        async with self._sessions() as session, session.begin():
            row = (
                await session.execute(
                    text(
                        """
                        UPDATE identities SET last_used_at = now()
                         WHERE provider = :provider AND subject = :subject
                        RETURNING principal_id
                        """
                    ),
                    {"provider": provider, "subject": subject},
                )
            ).first()
            return row.principal_id if row else None

    async def link(self, principal_id: str, *, provider: str, subject: str) -> str:
        """Attach a provider account to a principal. Returns the principal that now owns it.

        Idempotent when the link already points here. When it points at a **different** principal
        this returns that one unchanged rather than re-pointing it — because a provider account
        already claimed by someone else is the account-takeover case, and silently moving it is how
        that succeeds. Merging two real principals is a deliberate operation with its own consent,
        not a side effect of signing in.
        """
        existing = await self.resolve(provider=provider, subject=subject)
        if existing is not None:
            return existing
        async with self._sessions() as session, session.begin():
            session.add(Identity(provider=provider, subject=subject, principal_id=principal_id))
        return principal_id

    async def adopt_device(self, device_id: str, *, principal_id: str) -> None:
        """Move a device to a signed-in principal — the anonymous-to-account transition.

        This is the whole point of the identities table. Someone uses the app anonymously, their
        data accrues under an installation-derived principal, then they sign in with Apple. Their
        device re-points at the principal that Apple account already owns, and their history
        follows them across a reinstall or onto a second phone.

        Their *anonymous* principal is left in place rather than deleted, so nothing is destroyed
        by a mis-tap. Reclaiming or merging its data is a separate, explicit step.
        """
        async with self._sessions() as session, session.begin():
            await session.execute(
                text(
                    "UPDATE devices SET principal_id = :pid, last_seen_at = now() "
                    "WHERE device_id = :device_id"
                ),
                {"pid": principal_id, "device_id": device_id},
            )

    async def identities_for(self, principal_id: str) -> list[tuple[str, str]]:
        """(provider, subject) pairs linked to a principal. Drives a "signed in with" settings row
        and the unlink flow Apple expects alongside deletion."""
        async with self._sessions() as session:
            rows = await session.execute(
                select(Identity.provider, Identity.subject).where(
                    Identity.principal_id == principal_id
                )
            )
            return [(row.provider, row.subject) for row in rows]

    async def forget(self, principal_id: str) -> dict[str, int]:
        """Erase everything this principal has on the server. Returns what was removed.

        Apple requires in-app account deletion and Google requires a web path too, so this has to
        exist and has to be complete. Ordered so nothing is orphaned: synced data first, then the
        records describing it, then the identity.

        Audit events survive deliberately — they are metadata (ids, decisions, costs) with no
        payload, and erasing the record that a deletion happened would defeat the point of having
        an audit trail at all.

        **`principal_daily_spend` survives too, and that is a deliberate, arguable call.** A
        principal id is derived deterministically from the installation id, so the same device
        comes back as the same principal — which means deleting the spend rows would hand out a
        fresh token budget on every erasure. On a 90-day trial whose eligibility Apple owns, that
        is a repeatable way to spend real money. The rows themselves are a pseudonymous id, a date
        and an integer: no health data, no content, nothing about the person. Retaining them for
        abuse prevention is proportionate, and it is reported in the return value rather than
        hidden, so the user is told what was kept and why.
        """
        removed: dict[str, int] = {}
        async with self._sessions() as session, session.begin():
            # Device keys FIRST, and by a join through `devices`, because they are keyed by
            # installation id rather than principal id — a blanket
            # `DELETE ... WHERE principal_id = :pid` silently misses them, leaving a live
            # credential behind for an account that no longer exists.
            result = await session.execute(
                text(
                    """
                    DELETE FROM device_keys
                     WHERE installation_id IN (
                         SELECT device_id FROM devices WHERE principal_id = :pid)
                    RETURNING installation_id
                    """
                ),
                {"pid": principal_id},
            )
            removed["device_keys"] = len(result.all())
            for table in (
                "sync_records",
                "superseded_records",
                "consent_records",
                "identities",
                "devices",
            ):
                result = await session.execute(
                    text(f"DELETE FROM {table} WHERE principal_id = :pid RETURNING 1"),
                    {"pid": principal_id},
                )
                removed[table] = len(result.all())
            result = await session.execute(
                text("DELETE FROM principals WHERE principal_id = :pid RETURNING 1"),
                {"pid": principal_id},
            )
            removed["principals"] = len(result.all())
            kept = await session.scalar(
                text("SELECT count(*) FROM principal_daily_spend WHERE principal_id = :pid"),
                {"pid": principal_id},
            )
            # Negative to make it unmistakable in a log or an API response: these were KEPT.
            removed["spend_rows_retained"] = int(kept or 0)
        return removed


class StoredPrincipalSource:
    """Wraps another `PrincipalSource` and records whatever it returns.

    Composition rather than a new source: deriving identity and persisting it are different jobs,
    and keeping them apart means swapping dev identity for StoreKit verification later does not
    also mean rewriting registration.
    """

    def __init__(self, inner, store: IdentityStore) -> None:
        self._inner = inner
        self._store = store

    async def principal_for(
        self, *, app_id: str, installation_id: str, subscription_token: str
    ) -> Principal:
        principal = await self._inner.principal_for(
            app_id=app_id, installation_id=installation_id, subscription_token=subscription_token
        )
        await self._store.register(principal)
        return principal


__all__ = ["Entitlement", "IdentityStore", "StoredPrincipalSource"]
