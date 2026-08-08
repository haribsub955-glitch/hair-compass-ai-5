#!/usr/bin/env bash
# Per-app onboarding for the self-hosted Supabase stack — the multi-app seam.
# Creates a scoped, NON-SUPERUSER login role and a database it fully controls, on Supabase's
# Postgres (which is CREATEROLE/CREATEDB but NOT a full superuser).
#
#   bash new-app.sh <app>          # e.g.  bash new-app.sh agent_platform
#
# Prints the app's DATABASE_URL and writes it to .<app>.dburl (mode 600). NEVER commit that file.
#
# Two Supabase-Postgres facts this encodes (both cost a backend reset / a rejection if ignored):
#  1. CREATE DATABASE from TEMPLATE template0, NOT the default template1 — template1 carries
#     pgsodium/vault/pg_cron, and copying those on CREATE DATABASE resets the Postgres backend.
#  2. `postgres` here is not a superuser: do NOT `ALTER ROLE ... NOSUPERUSER` (rejected) and do not
#     rely on revoking predefined roles (no ADMIN). A freshly CREATEd role is already NOSUPERUSER /
#     NOBYPASSRLS / NOREPLICATION by default, which is what we want.
set -euo pipefail
APP="${1:?usage: new-app.sh <app>}"
ROLE="${APP}_app"
DBC="${SUPABASE_DB_CONTAINER:-supabase-db}"
cd "$(dirname "$0")"

PGPW="$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)"
PW="$(openssl rand -hex 24)"
px() { docker exec -i -e PGPASSWORD="$PGPW" "$DBC" psql -U postgres -v ON_ERROR_STOP=1 "$@"; }

echo "new-app.sh: creating role '${ROLE}' + database '${APP}' (template0) in '${DBC}'..."

# role (default attrs are already the locked-down ones) + database from the bare template
px <<SQL
DROP DATABASE IF EXISTS "${APP}";
DROP ROLE IF EXISTS "${ROLE}";
CREATE ROLE "${ROLE}" LOGIN PASSWORD '${PW}' NOCREATEDB NOCREATEROLE;
CREATE DATABASE "${APP}" TEMPLATE template0;
SQL

# harden + grant inside the app database (extension drops are no-ops on template0; kept for reruns)
px -d "${APP}" <<SQL
DROP EXTENSION IF EXISTS pg_net;
DROP EXTENSION IF EXISTS http;
DROP EXTENSION IF EXISTS dblink;
DROP EXTENSION IF EXISTS postgres_fdw;
REVOKE ALL ON DATABASE "${APP}" FROM PUBLIC;
GRANT CONNECT, TEMPORARY, CREATE ON DATABASE "${APP}" TO "${ROLE}";
GRANT ALL ON SCHEMA public TO "${ROLE}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "${ROLE}";
SQL

umask 077
printf 'postgresql+asyncpg://%s:%s@db:5432/%s\n' "${ROLE}" "${PW}" "${APP}" > ".${APP}.dburl"
echo "OK: role=${ROLE} (NOSUPERUSER, NOCREATEDB, NOCREATEROLE), db=${APP} (from template0)"
echo "connection string written to ./.${APP}.dburl (mode 600) — NEVER commit it"
