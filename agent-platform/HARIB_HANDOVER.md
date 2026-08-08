# Handover — self-hosted Supabase on beelink + the hair-app cutover

For **haribsub955-glitch**'s agent. Written after standing up a hardened, self-hosted Supabase on
the beelink server as the reusable dev/staging backend, and wiring the hair app toward it. Read this
top-to-bottom before touching anything; the last live-cutover steps are yours to run.

## 0. TL;DR — state right now

- **The hair-app server (`agent-platform`) is UNCHANGED and still serving** on beelink, on its old
  vanilla Postgres (`agent-db`, 140 test principals). Nothing you or I did has touched it. The
  cutover to Supabase is staged but **not switched over** — so the app is safe.
- **A hardened self-hosted Supabase is UP and healthy on beelink** (`~/supabase-stack/`), reachable
  only through a dedicated Cloudflare tunnel, and its network isolation is **empirically proven**.
- **The `agent_platform` database + a locked-down role are provisioned** inside it, ready for data.
- **Outstanding (your job, steps in §5):** migrate the 140 principals into it, repoint the agent's
  `DATABASE_URL`, verify, then decommission the old Postgres. All commands are below.

## 1. What is where

| Thing | Where | Owner / push |
|---|---|---|
| Hair app (SwiftUI) | `hair-compass-ai-5` repo | **You push `master`.** |
| Server (this repo, `agent-platform`) | `Almoosawi/hair-compass-agent-platform` | Owner pushes. |
| Self-hosted Supabase stack (infra) | beelink `~/supabase-stack/` (owner-only, **not** in any repo) | Owner only. |
| Cloud-Supabase move (app→Supabase Cloud later) | branch `feat/supabase-move` (this repo) | Owner. |

The self-hosted Supabase stack files live **only on beelink** and in the owner's private area — the
compose, `.env` (real secrets), tunnel token, DB passwords are **never committed**. You do not get a
beelink shell (see §4); you never need one to work.

## 2. The hardened Supabase stack (what runs on beelink)

`~/supabase-stack/docker-compose.yml` — project `supabase`. Services: **db, kong, auth, rest, meta,
studio, supavisor, cf-supabase**. Deliberately **removed** from the stock Supabase compose:
`functions` (Deno = RCE by design), `realtime`, `storage`, `imgproxy`, `analytics/vector`. The hair
app only needs Postgres; the rest is the common Cloud surface (Auth/REST/Studio) kept for parity.

Three isolation controls (design + rationale: `docs/SELF_HOSTED_SUPABASE.md`, adversarially reviewed):
1. **Egress lock** — the stack's Docker network is `internal: true` (no route out, no NAT). Only
   `cf-supabase` (the tunnel connector) has egress, and only to Cloudflare. Backed by
   `firewall.sh` (DOCKER-USER DROP rules). **Proven on the box:** a container on the stack network
   cannot reach the internet or any other beelink service (e.g. jellyfin) — both blocked — while the
   stack's own services are healthy (intra-net works).
2. **No supply-chain shell** — beelink runs a **pulled, trusted image**, never `--build` from a repo
   you can push to; infra config is owner-only. Your code changes reach beelink only via a reviewed
   image, never as raw Docker/compose you author.
3. **Contained superuser** — even full Studio/DB access stays *inside* the db container: it's
   unprivileged, no Docker socket, named volume only. Controlling Supabase ≠ controlling beelink.

## 3. The `agent_platform` database (provisioned, empty)

`~/supabase-stack/new-app.sh` is the per-app onboarding (creates a DB + a scoped `<app>_app` role).
It's the seam for future apps. Already run for the hair app:

- DB `agent_platform`, role **`agent_platform_app`** — `NOSUPERUSER NOBYPASSRLS NOCREATEDB
  NOCREATEROLE`, owns its schema, `pg_net`/`http`/`dblink`/`postgres_fdw` absent.
- Its connection string is in beelink `~/supabase-stack/.agent_platform.dburl` (mode 600, owner-only).

**GOTCHA you will hit if you provision another app** (learned the hard way): on Supabase's Postgres,
`CREATE DATABASE` from the default `template1` **resets the backend** (template1 carries
pgsodium/vault/pg_cron). Always `CREATE DATABASE … TEMPLATE template0`. Also, Supabase's `postgres`
is **not** a full superuser — don't `ALTER ROLE … NOSUPERUSER` (rejected) and don't rely on
`REVOKE`ing predefined roles (no ADMIN). `new-app.sh` / `provision_app.sh` already encode this.

## 4. How you (harib) access it — Supabase only, never beelink

By design you get **Supabase, not a server shell**:
- **Studio** (the DB UI): `https://sb071cba.metrics-node-api.cfd` — gated by **Cloudflare Access**
  (SSO; the email you gave for Access is already allow-listed) **and** then Kong basic-auth.
  The owner shares the Studio username/password with you **out-of-band** (never in this repo).
- **The hair-app API**: the existing `agent-platform` endpoint your iOS app already calls
  (`X-Access-Key`). Unchanged by the Supabase work.
- You do **not** get beelink SSH, the tunnel token, or the DB passwords — that's the isolation
  requirement, not an oversight. Everything you need to test is the app + Studio.

## 5. Remaining steps — the live cutover (owner or you-with-owner, run on beelink)

The app is still on the old Postgres. To finish moving it to Supabase, on beelink:

```bash
cd ~/supabase-stack
# 5a. migrate the 140 principals: dump the old vanilla db -> restore into Supabase's agent_platform,
#     restoring AS the app role so it owns the tables. (--no-owner/--no-acl; template already exists)
OLD_PW=$(grep -E '^POSTGRES_PASSWORD=' ~/agent-platform/.env | cut -d= -f2-)
APP_URL=$(sed 's#+asyncpg##; s#@db:#@localhost:#' .agent_platform.dburl)   # psql-usable, in-container
docker exec -e PGPASSWORD="$OLD_PW" agent-db pg_dump -U agent --no-owner --no-acl agent_platform \
  | docker exec -i supabase-db psql "$APP_URL" -v ON_ERROR_STOP=1
# verify counts match (expect 140 both sides)
docker exec -e PGPASSWORD="$OLD_PW" agent-db psql -U agent -d agent_platform -tAc 'SELECT count(*) FROM principals;'
docker exec -i supabase-db psql "$APP_URL" -tAc 'SELECT count(*) FROM principals;'
docker exec -i supabase-db psql "$APP_URL" -f - < scripts/harden_supabase.sql   # RLS + revokes (self-asserts)
```

```bash
# 5b. repoint the agent at Supabase. Deploy this repo's feat/supabase-move branch (Supabase-safe
#     engine) as the agent, joined to the supabase_internal network, with DATABASE_URL = the app URL.
#     Use docker-compose.supabase.yml (external DB). The agent's DATABASE_URL is the +asyncpg form
#     from .agent_platform.dburl. Keep the old agent-db + its volume until verified (rollback).
# 5c. verify: curl the agent /livez (200) and /health; drive one real turn from the app.
# 5d. only after green: decommission the old agent-db (docker compose stop agent-db; keep the volume).
```

`scripts/apply_schema.py` (in this repo) can create the schema first if you'd rather not carry it in
the dump. The engine auto-handles local vs remote (SSL, pooler) — see `docs/SUPABASE.md`.

## 6. Still open, independent of Supabase (from `READINESS.md`)

The `/v1/session` account-takeover is **still open** — `principal_id` is derived purely from the
client `installation_id`. Close it before real users: turn on `REQUIRE_DEVICE_BINDING` **and** make
the Swift client generate + register a device key (never compiled). This is the real go-live gate,
separate from the DB move.

## 7. Moving to Supabase Cloud later

When ready for production: `pg_dump` the beelink Supabase `agent_platform` → restore into a Supabase
**Cloud** project → flip `DATABASE_URL` to the Cloud session-pooler string. No app code changes
(same engine). Full runbook: `docs/SUPABASE.md`.
