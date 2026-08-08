"""Apply and verify the schema against whatever `DATABASE_URL` points at — without booting the API.

This is the one command to run the moment a real database (e.g. Supabase) is wired up: it proves
the connection string works, creates every table, claims the database for this `APP_ENV`, and reports
any schema drift — the exact sequence `api.py`'s startup runs, but on its own so a bad `DATABASE_URL`
fails here in five seconds instead of on the first request.

    # after editing .env so DATABASE_URL points at Supabase:
    .venv/Scripts/python scripts/apply_schema.py

Reads configuration from `.env` through the same `Settings` the server uses, so what passes here is
what the server will use. The database password is never printed.

Exit code 0 = schema present and current. Non-zero = could not connect, or drift `create_all` cannot
fix (a column/constraint added to an existing table — that needs a migration, not a re-run).
"""

from __future__ import annotations

import asyncio
import sys
from urllib.parse import urlsplit

from agent_server.core.config import settings
from agent_server.db.session import claim_database, create_schema, make_engine, verify_schema


def _safe_target(database_url: str) -> str:
    """host:port/dbname — never the password."""
    parts = urlsplit(database_url)
    host = parts.hostname or "?"
    port = f":{parts.port}" if parts.port else ""
    db = parts.path.lstrip("/") or "?"
    return f"{host}{port}/{db}"


async def main() -> int:
    config = settings()
    print(f"target   : {_safe_target(config.database_url)}  (APP_ENV={config.app_env})")

    engine = make_engine(config.database_url)
    try:
        # Claim FIRST: reject a wrong-environment database before create_all writes anything to it.
        owner = await claim_database(engine, config.app_env)
        await create_schema(engine)
        drift = await verify_schema(engine)
    except Exception as exc:  # noqa: BLE001 — fail loud with the reason, do not half-apply silently
        print(f"FAILED   : {type(exc).__name__}: {exc}")
        return 2
    finally:
        await engine.dispose()

    print(f"claimed  : {owner!r}")
    if drift:
        # create_all only ever CREATEs; these must be migrated by hand. Loud on purpose.
        print(f"DRIFT    : missing {', '.join(drift)} — needs a migration, not a re-run")
        return 1
    print("schema   : present and current")
    print("RESULT   : PASS")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
