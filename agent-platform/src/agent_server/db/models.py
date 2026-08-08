"""The server's tables. Stock Postgres — nothing Supabase-specific.

Supabase *is* Postgres, so building on plain SQLAlchemy means moving there later is a
`DATABASE_URL` change rather than a rewrite. That holds only if nothing here reaches for
PostgREST, the Supabase client, or storage buckets — so nothing here does. Row-level security is
ordinary Postgres and can be layered on afterwards without touching these definitions.

**Two design rules run through every table.**

*Columns for what the server queries or decides on; `JSONB` for everything else.* Adding an
attribute to the phone's `Profile` must not require a migration, a deploy, or a conversation. New
keys land in `attributes` and the server carries them without knowing what they are.

*Nothing here holds a direct identifier.* No name, no birth date, no email. Principals are
pseudonymous, derived server-side. What makes that stick is that there is no column to put a name
in — a rule enforced by a schema is harder to forget than one written in a comment.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Principal(Base):
    """Who the server acts for. Pseudonymous by construction.

    One principal can own several devices — a phone and a tablet are the same person. So
    `principal_id` is *visibility* (what data is theirs) and `device_id` is *provenance* (which
    machine wrote it), the same split `AgentMemory` makes between scope and session.
    """

    __tablename__ = "principals"

    principal_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    app_id: Mapped[str] = mapped_column(String(64), nullable=False)
    tenant_id: Mapped[str | None] = mapped_column(String(64))
    entitlement: Mapped[str] = mapped_column(String(16), nullable=False, default="free")
    #: When the current plan started. A lifetime trial cap is measured from here, so switching
    #: plans resets the window rather than counting spend from a previous plan against the new one.
    plan_started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    #: Apple's `originalTransactionId` for the subscription that granted the current plan.
    #:
    #: A StoreKit JWS is a BEARER artefact - signed by Apple, unchanged for the billing period, and
    #: silent about who is presenting it. Verifying it and moving on means one extracted receipt
    #: entitles every device it is pasted into. Recording it under a unique constraint is what
    #: makes it non-transferable: the second principal to claim it is refused by Postgres.
    subscription_txn_id: Mapped[str | None] = mapped_column(String(64))

    __table_args__ = (
        # Every query is scoped by app. Without this index, a second app on the same deployment
        # turns every lookup into a scan of both apps' rows.
        Index("ix_principals_app", "app_id"),
        # One subscription, one principal. NULL is unconstrained in Postgres, so every principal
        # without a subscription coexists happily.
        UniqueConstraint("subscription_txn_id", name="uq_principal_subscription"),
    )


class Device(Base):
    """One installation. Registered automatically the first time it opens a session.

    `device_id` is the installation id the client sends — stable across launches, new on reinstall.
    It is deliberately NOT a hardware identifier: those are restricted, they survive uninstall in
    ways users do not expect, and nothing here needs one.
    """

    __tablename__ = "devices"

    device_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    principal_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("principals.principal_id", ondelete="CASCADE"), nullable=False
    )
    app_id: Mapped[str] = mapped_column(String(64), nullable=False)
    platform: Mapped[str] = mapped_column(String(16), nullable=False, default="unknown")
    app_build: Mapped[str] = mapped_column(String(32), nullable=False, default="")
    os_version: Mapped[str] = mapped_column(String(32), nullable=False, default="")
    first_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (Index("ix_devices_principal", "principal_id"),)


class Identity(Base):
    """A way of proving you are a principal. One principal, many identities.

    Not needed until Sign in with Apple ships, and added now because it is the one thing that is
    genuinely expensive to retrofit: without it, `principal_id` stays welded to `installation_id`,
    every reinstall orphans a person's history, and unpicking that after real users exist means
    merging accounts by hand.

    **Storing the provider's subject id does not break the no-direct-identifier rule.** Apple's
    `sub` and Google's `sub` are opaque and app-scoped — they identify a person *to this app* and
    are useless anywhere else. An email address is the opposite, so there is deliberately no column
    for one: Apple hands out a private relay address, we would gain nothing by keeping it, and it
    would turn a pseudonymous table into a personal one.

    **`(provider, subject)` is unique; email is never the join key.** Auto-merging two accounts
    because they share an email address is a well-known takeover route — an attacker who controls
    an unverified address inherits the other account. Linking a second provider to an existing
    principal must require a fresh, deliberate authentication while already signed in.
    """

    __tablename__ = "identities"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    #: "apple" | "google" | "email" | future providers.
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    #: The provider's own stable, app-scoped subject id. Never an email.
    subject: Mapped[str] = mapped_column(String(255), nullable=False)
    principal_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("principals.principal_id", ondelete="CASCADE"), nullable=False
    )
    linked_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (
        # One provider account maps to exactly one principal. The constraint is what makes
        # "sign in and get your data back" deterministic rather than a best guess.
        UniqueConstraint("provider", "subject", name="uq_identity_provider_subject"),
        Index("ix_identities_principal", "principal_id"),
    )


class DailySpend(Base):
    """One row per principal per day. The whole cost ledger rests on this being atomic.

    A budget check that reads then writes is raceable — two turns both see room and both spend.
    The reserve is therefore a single `INSERT … ON CONFLICT DO UPDATE … WHERE` statement that
    Postgres evaluates atomically: either the row comes back updated, or the budget is gone. No
    application lock, and correct across processes, which the in-memory version never was.
    """

    __tablename__ = "principal_daily_spend"

    principal_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    day: Mapped[date] = mapped_column(Date, primary_key=True)
    spent: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        # Spend can be refunded to zero but never below it. A negative total would mean a settle or
        # release ran twice, and it should surface as a constraint violation rather than as free
        # quota.
        CheckConstraint("spent >= 0", name="ck_spend_non_negative"),
    )


class Reservation(Base):
    """A worst-case amount held before a provider call, reconciled after.

    Kept as its own row rather than a number in memory so a crashed process does not lose the fact
    that money is outstanding. An unsettled reservation older than its expiry is recoverable: it
    means the turn died mid-flight, and the amount should be released rather than held forever.
    """

    __tablename__ = "cost_reservations"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    principal_id: Mapped[str] = mapped_column(String(64), nullable=False)
    day: Mapped[date] = mapped_column(Date, nullable=False)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    settled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        Index("ix_reservations_open", "principal_id", "settled_at"),
        CheckConstraint("amount > 0", name="ck_reservation_positive"),
    )


class ConsentRecord(Base):
    """What the user agreed to, and when. Written before any personal data is accepted.

    Oman's PDPL wants explicit consent recorded before personal data crosses a border, and the
    provider is outside Oman. `withdrawn_at` is the half people forget: consent that cannot be
    withdrawn is not consent, and withdrawal has to actually stop the syncing and delete what was
    synced.
    """

    __tablename__ = "consent_records"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    principal_id: Mapped[str] = mapped_column(String(64), nullable=False)
    purpose: Mapped[str] = mapped_column(String(64), nullable=False)
    policy_version: Mapped[str] = mapped_column(String(32), nullable=False)
    crosses_border: Mapped[bool] = mapped_column(nullable=False, default=False)
    granted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    withdrawn_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (Index("ix_consent_principal_purpose", "principal_id", "purpose"),)


class SyncRecord(Base):
    """The synced slice of a device's data. **This is the table that never needs migrating.**

    `attributes` is `JSONB`, so adding a field to the phone's model puts a new key in here and
    requires nothing of the server — no migration, no deploy. That was the explicit requirement,
    and it is why only the columns the server actually *queries* are columns.

    `natural_key` is the record's stable identity on the phone, so a second sync updates rather
    than duplicates. `deleted_at` is a tombstone: a hard delete lets a replica that has not synced
    since resurrect the row on its next push.
    """

    __tablename__ = "sync_records"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    principal_id: Mapped[str] = mapped_column(String(64), nullable=False)
    #: Provenance — which installation wrote it. Visibility is `principal_id`.
    device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    natural_key: Mapped[str] = mapped_column(String(128), nullable=False)

    attributes: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    #: What shape `attributes` was written against. A row from an older build stays identifiable
    #: rather than being silently misread as the current shape.
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    consent_version: Mapped[str] = mapped_column(String(32), nullable=False, default="")

    #: The origin's clock, used for conflict resolution.
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    #: Our clock, used as the pull cursor. The two differ whenever a device's clock is wrong, and
    #: a cursor built on the origin's clock would then skip records forever.
    server_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (
        UniqueConstraint("principal_id", "kind", "natural_key", name="uq_sync_identity"),
        # The pull query: everything for this principal changed since a cursor.
        Index("ix_sync_pull", "principal_id", "server_seen_at"),
    )


class SupersededRecord(Base):
    """The losing side of a sync conflict, kept rather than dropped.

    Last-write-wins is a fine default and a bad excuse for losing data. When a conflict resolves,
    the version that lost lands here — so "the sync ate my note" is always answerable, and a bad
    clock on one device is recoverable rather than destructive.
    """

    __tablename__ = "superseded_records"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    principal_id: Mapped[str] = mapped_column(String(64), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    natural_key: Mapped[str] = mapped_column(String(128), nullable=False)
    attributes: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    losing_device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    losing_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class DeviceKey(Base):
    """The public key an installation must sign with to prove it is itself.

    Separate from `devices` because the lifetimes differ: a device row is bookkeeping that follows
    a principal around, while this is a credential. Binding is trust-on-first-use — the first
    caller to claim an unused installation id sets the key — and after that the id alone is worth
    nothing without the matching private key.
    """

    __tablename__ = "device_keys"

    installation_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    #: SubjectPublicKeyInfo DER. Stored normalised so a re-encoded but identical key compares equal.
    public_key: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    #: True when an App Attest attestation backed this key: the caller is our app, on real hardware.
    attested: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    #: Highest App Attest assertion counter seen. Persisted because forgetting it makes every past
    #: assertion replayable — verifying the signature and dropping the counter is only half a check.
    counter: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    bound_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    last_proof_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Attachment(Base):
    """Bytes on their way to a model, and nothing more.

    Deliberately NOT a photo library. A row lives from upload until the turn that uses it, and the
    fetch deletes it in the same statement — so there is no window where a used attachment waits
    for a cleanup job that might not run. Anything never used is reaped on a timer.

    The bytes are `bytea` rather than a file path because a row and a file can disagree: erasure,
    a restore, or a failed write leaves one without the other, and at this size and lifetime the
    database is simply the safer of the two.
    """

    __tablename__ = "attachments"

    attachment_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    #: Scoped, so one user's photo can never resolve inside another user's turn.
    principal_id: Mapped[str] = mapped_column(String(64), nullable=False)
    #: The SNIFFED type, never the one the client declared.
    media_type: Mapped[str] = mapped_column(String(32), nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    byte_size: Mapped[int] = mapped_column(nullable=False)
    data: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (Index("ix_attachments_created", "created_at"),)


class Deployment(Base):
    """Which environment this database belongs to. One row, written once.

    The incident this prevents: someone points a staging process at the production `DATABASE_URL`
    — a copied `.env`, a wrong secret in a deploy pipeline, a `docker compose` run in the wrong
    directory — and staging then writes to, meters against, and erases real users' data. Nothing
    else in the system would notice, because every table is shaped identically.

    So the database itself records whose it is, and a process whose environment disagrees refuses
    to start. It is one row and one comparison, and it turns a silent catastrophe into a failed
    deploy.
    """

    __tablename__ = "deployment"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    app_env: Mapped[str] = mapped_column(String(16), nullable=False)
    claimed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        # Exactly one row, enforced rather than assumed. A second claim is the bug this exists to
        # catch, so it must not be able to insert quietly alongside the first.
        CheckConstraint("id = 1", name="ck_deployment_singleton"),
    )


class AuditEvent(Base):
    """Metadata only. Never a prompt, never a tool result, never model output.

    The moment this table holds payloads it becomes the copy of personal data the architecture says
    is not kept — and it would be a copy with a longer retention than the thing it describes. Ids,
    hashes, versions, decisions and costs are enough to answer "what happened", which is what an
    audit log is for.
    """

    __tablename__ = "audit_events"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    principal_id: Mapped[str] = mapped_column(String(64), nullable=False)
    device_id: Mapped[str] = mapped_column(String(128), nullable=False, default="")
    event: Mapped[str] = mapped_column(String(48), nullable=False)
    turn_id: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    #: Small structured facts — decision, tier, tool name, token counts, policy version.
    detail: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (Index("ix_audit_principal_time", "principal_id", "occurred_at"),)
