"""Engine and session factory. One place that knows how to reach the database.

`create_all` rather than Alembic for now, deliberately: there is one schema version and no
production data, so a migration tool would be ceremony around a single `CREATE TABLE`. Alembic is
already a declared dependency and becomes necessary the moment a deployed table changes shape —
which, for `sync_records`, is the case the JSONB column is designed to avoid entirely.
"""

from __future__ import annotations

import ipaddress
import logging
import ssl
from uuid import uuid4

from sqlalchemy import URL, make_url
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from agent_server.db.models import Base, Deployment

log = logging.getLogger("agent_server.db")

#: SSL query values that encrypt without verifying the certificate, or not at all. Honoured when an
#: operator sets one explicitly, but never silently — `_connect_args` warns. `verify-ca`/`verify-full`
#: are the verifying modes and are left alone.
_INSECURE_SSL = {"disable", "allow", "prefer", "require"}


def make_engine(database_url: str) -> AsyncEngine:
    """One place that knows how to reach the database, local container or managed Postgres alike.

    Two things a managed host needs that a compose container does not, both derived from the URL so
    there is no new setting to forget:

    * **TLS.** Supabase (and every managed Postgres) can require a TLS connection. asyncpg does
      **not** accept libpq's `sslmode=` — passing it raises `TypeError` on connect, not a silent
      downgrade — so TLS is turned on here with a context that verifies the server against the system
      trust store. Skipped for loopback/private/compose hosts. If the URL carries an explicit `ssl`
      param it is honoured, and a *non-verifying* value is warned about rather than applied silently.
    * **The transaction-mode pooler.** Supabase's Supavisor pooler on port **6543** multiplexes one
      backend across many clients, so a server-side prepared statement can vanish mid-session. On
      6543 both the asyncpg and the SQLAlchemy-dialect prepared-statement caches are disabled and
      statement names are made unique per client. Client-side pooling is still kept (the pooler is
      built for clients to hold connections; dropping it would add a TCP+TLS handshake per request).
      A long-lived server should still prefer the **session** pooler (port 5432) or a direct
      connection, where prepared statements work natively and this branch is never taken.
    """
    connect_args, transaction_pooler = _connect_args(make_url(database_url))

    if transaction_pooler:
        log.warning(
            "DATABASE_URL uses the transaction-mode pooler (port 6543); prepared statements are "
            "disabled to survive it, and even so it is fragile under burst load. A long-lived "
            "server should use the session pooler (port 5432) or a direct connection."
        )

    # pool_pre_ping + pool_recycle because a managed pooler silently reaps idle connections: without
    # them a pooled connection can be dead on checkout (pre_ping catches it) or reaped mid-idle
    # (recycle stays under the reaper's window). Harmless against the local container too.
    return create_async_engine(
        database_url,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=5,
        pool_recycle=1800,
        connect_args=connect_args,
    )


def _is_local_host(host: str) -> bool:
    """True for a host that speaks plaintext on the local wire — loopback, a private/LAN address, or
    a short dot-less name (a compose service like `db`/`postgres`/`local-db`). A managed database is
    a dotted FQDN (`…​.pooler.supabase.com`) and is treated as remote.

    A name allowlist was the first cut; it forced TLS onto any local service not named `db` and
    crashed it. Deriving local-ness from the address shape is what makes that impossible.
    """
    host = (host or "").lower().strip("[]")  # SQLAlchemy gives a bare `::1`; be defensive anyway
    if not host or host == "localhost":
        return True
    try:
        ip = ipaddress.ip_address(host)
        return ip.is_loopback or ip.is_private or ip.is_link_local
    except ValueError:
        # A hostname, not an IP. A compose/short name has no dot; an FQDN does.
        return "." not in host


def _connect_args(url: URL) -> tuple[dict[str, object], bool]:
    """asyncpg + dialect connect args for a parsed URL, and whether it is the transaction pooler.

    Pure and connection-free so the SSL/pooler decisions can be asserted without a live remote
    database. Returns `(connect_args, is_transaction_pooler)`.
    """
    connect_args: dict[str, object] = {}

    if not _is_local_host(url.host or ""):
        explicit = url.query.get("ssl")
        if explicit is None:
            # Verify against the system trust store. Supabase's cert chains to a public CA, so no
            # bundled CA is needed. create_default_context() = CERT_REQUIRED + check_hostname.
            connect_args["ssl"] = ssl.create_default_context()
        elif str(explicit).lower() in _INSECURE_SSL:
            # Honour a deliberate override, but never let a downgrade pass silently: `require`
            # encrypts without verifying the certificate; `disable` is plaintext to a remote host.
            log.warning(
                "DATABASE_URL sets ssl=%s on remote host %r — certificate verification is NOT "
                "enforced. Use ssl=verify-full (or drop the ssl param) for a verified connection.",
                explicit,
                url.host,
            )

    is_transaction_pooler = url.port == 6543
    if is_transaction_pooler:
        # Disable asyncpg's cache AND the SQLAlchemy dialect's, and make each prepared-statement name
        # unique per client so two clients sharing one pooled backend cannot collide (the SQLAlchemy
        # asyncpg dialect's documented "Prepared Statement Name with PGBouncer" recipe).
        connect_args["statement_cache_size"] = 0
        connect_args["prepared_statement_cache_size"] = 0
        connect_args["prepared_statement_name_func"] = lambda: f"__asyncpg_{uuid4()}__"

    return connect_args, is_transaction_pooler


def make_sessions(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine, expire_on_commit=False)


#: Constraints and columns that `create_all` will NOT add to a table that already exists, and that
#: something important silently stops enforcing if they are missing. Each entry is the check, not
#: the fix — the fix is a migration.
REQUIRED_SCHEMA = (
    ("principals", "column", "subscription_txn_id"),
    ("principals", "column", "plan_started_at"),
    ("principals", "constraint", "uq_principal_subscription"),
    ("identities", "constraint", "uq_identity_provider_subject"),
)


async def create_schema(engine: AsyncEngine) -> None:
    """Create anything missing, then check what `create_all` cannot fix.

    **`create_all` only ever CREATEs.** It does not ALTER, so adding a column or a constraint to an
    existing table changes the ORM metadata and nothing in the database. That is not theoretical
    here: the unique constraint that makes a StoreKit receipt non-transferable was added to the
    model, and a deployed database without it accepts the same receipt from any number of
    principals while every test passes against a fresh one.

    So the drift is asserted rather than assumed. This warns rather than raising because refusing
    to start over a missing index would turn a data-integrity gap into an outage — but it warns at
    ERROR, names the object, and cannot be missed in a log.
    """
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    await verify_schema(engine)


class WrongDatabase(RuntimeError):
    """This database belongs to a different environment. Refuse rather than write to it."""


async def claim_database(engine: AsyncEngine, app_env: str) -> str:
    """Record which environment owns this database, or confirm it is already ours.

    Returns the owning environment. Raises `WrongDatabase` when it is somebody else's.

    The scenario, which is mundane and therefore likely: a copied `.env`, a wrong secret in a
    pipeline, or a `docker compose up` in the wrong directory points a staging process at the
    production `DATABASE_URL`. Every table is shaped identically, so nothing else in the system
    would notice — staging would meter, write and erase real users' data. One row and one
    comparison turns that into a failed deploy.

    The claim is an upsert on a fixed primary key, so two processes starting together cannot
    produce two rows.

    Runs BEFORE `create_schema`, and bootstraps only its own one-row table to do so: a staging
    process pointed at a production database must be rejected before `create_all` writes anything —
    otherwise a newly added model table lands in production before the mismatch is caught.
    """
    from sqlalchemy import text

    async with engine.begin() as connection:
        # Only this table, idempotently, so the claim can gate every other write.
        await connection.run_sync(Deployment.__table__.create, checkfirst=True)
        owner = await connection.scalar(
            text(
                """
                INSERT INTO deployment (id, app_env) VALUES (1, :env)
                ON CONFLICT (id) DO UPDATE SET app_env = deployment.app_env
                RETURNING app_env
                """
            ),
            {"env": app_env},
        )
    if owner != app_env:
        raise WrongDatabase(
            f"this database belongs to {owner!r} and this process is {app_env!r} — "
            "refusing to start. Check DATABASE_URL and APP_ENV."
        )
    log.info("database claimed by %s", owner)
    return str(owner)


async def verify_schema(engine: AsyncEngine) -> list[str]:
    """Names of required columns/constraints that are missing. Empty means the schema is current."""
    from sqlalchemy import text

    missing: list[str] = []
    async with engine.connect() as connection:
        for table, kind, name in REQUIRED_SCHEMA:
            if kind == "column":
                found = await connection.scalar(
                    text(
                        "SELECT 1 FROM information_schema.columns "
                        " WHERE table_schema = 'public' AND table_name = :t AND column_name = :n"
                    ),
                    {"t": table, "n": name},
                )
            else:
                found = await connection.scalar(
                    text("SELECT 1 FROM pg_constraint WHERE conname = :n"),
                    {"n": name},
                )
            if not found:
                missing.append(f"{table}.{name}")
    if missing:
        log.error(
            "SCHEMA DRIFT — missing %s. `create_all` does not ALTER an existing table, so these "
            "must be migrated by hand or with Alembic. Until then the controls that depend on "
            "them are NOT enforced.",
            ", ".join(missing),
        )
    return missing
