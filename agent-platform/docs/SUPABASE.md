# Moving the database to Supabase

**What Supabase is used for here: the Postgres database, and nothing else.** No PostgREST/Data API,
no `supabase-js`/`supabase-py`, no Auth, no Storage, no Edge Functions. The server talks to Supabase
over a plain Postgres connection string, exactly as it talks to the local `db` container today. That
is why this is a `DATABASE_URL` change rather than a rewrite — verified: `create_all` applies the
full schema clean on the real Supabase Postgres image, and the Postgres regression suite passes
against it (512 tests).

> **Supabase does not host the Python server.** It hosts Postgres. The FastAPI app still runs
> somewhere it can hold a long-lived connection (the current box + a tunnel, or a small cloud host).
> That choice is separate from this document — this covers the database only.

## 1. Which connection string to copy

Supabase → Project → **Connect**. There are three; use the **Session pooler**:

| String | Host / port | Use it? |
|---|---|---|
| **Session pooler** | `aws-<n>-<region>.pooler.supabase.com` : **5432** | **Yes.** A long-lived server; prepared statements work; IPv4-reachable. |
| Transaction pooler | `…pooler.supabase.com` : **6543** | Only if you must. It is for serverless; asyncpg's prepared statements can't survive it. The code detects 6543 and turns the statement cache off + drops client pooling, so it *works*, but session mode is the right one. |
| Direct connection | `db.<ref>.supabase.co` : 5432 | Avoid unless the host has IPv6. The direct endpoint is IPv6-only without the paid IPv4 add-on; the pooler is IPv4. |

Rewrite the driver prefix to the async driver and keep the rest:

```
postgresql+asyncpg://postgres.<project-ref>:<DB-PASSWORD>@aws-<n>-<region>.pooler.supabase.com:5432/postgres
```

- `postgresql+asyncpg://` — not `postgres://`. The `+asyncpg` is what selects the async driver.
- **Do not** append `?sslmode=require`. asyncpg does not accept libpq's `sslmode` — it raises
  `TypeError` on connect (a loud failure, not a silent downgrade). You need nothing in the string:
  for any remote host the code enables verified TLS itself (`ssl.create_default_context()` =
  certificate + hostname verification).
- **Override (rare):** to set TLS yourself, put `?ssl=verify-full` in the URL — the code defers to it.
  A *non-verifying* value (`ssl=require`/`prefer`/`allow`/`disable`) is honoured but logged as a
  WARNING, because on a remote host it drops certificate verification.
- **Plaintext LAN / Docker / Tailscale DB:** a dotted IP or host is treated as remote, so TLS is
  forced. For an unencrypted database on a LAN, a Docker network, or a Tailscale tailnet
  (`100.64.0.0/10`), set `?ssl=disable` — the connection then stays plaintext and the one-line
  warning above is expected there.

## 2. What I need from you

1. **The Session-pooler connection string** above, with the database password in it. (Paste it into
   `.env` yourself if you'd rather I not see the password — see §3. Either works.)
2. **The project region** (e.g. `eu-west-1`) — only so the Oman-PDPL data-residency note in
   `ARCHITECTURE.md §10` records where personal data is processed. It does not change any code.

Nothing else. No `anon` key, no `service_role` key, no project API URL — none of the SDK surface is
used.

## 3. Applying the schema (the one command once the string is set)

Edit `.env` so `DATABASE_URL` is the Supabase string, `APP_ENV=staging` (or `prod`), then:

```bash
.venv/Scripts/python scripts/apply_schema.py
```

It connects with the *same* settings the server will use, creates every table, claims the database
for this `APP_ENV`, and reports drift — so a wrong string fails here in seconds, not on the first
request. Expected output:

```
target   : aws-<n>-<region>.pooler.supabase.com:5432/postgres  (APP_ENV=staging)
claimed  : 'staging'
schema   : present and current
RESULT   : PASS
```

The server also runs this sequence at startup, so a fresh Supabase project is created on first boot
regardless. The script just lets you prove the connection before deploying.

## 4. The live-environment settings the server will refuse to start without

`config.validate_for_environment()` blocks a `staging`/`prod` boot that is unsafe. For the Supabase
move these must be set in `.env` (all already exist as settings; this is the checklist):

| Setting | Why it's required live |
|---|---|
| `DATABASE_URL` | Must be real Postgres — sqlite/memory is refused. |
| `SECRET_KEY` | ≥ 32 chars. Derives principal ids + signs session tokens. |
| `ACCESS_KEYS` | `name=<48+ random>` front-door key(s). An internet-reachable server with no front door is refused. |
| `REQUIRE_DEVICE_BINDING=true` | Without it an installation id alone opens a session — see the blocker in `READINESS.md`. |
| `APPLE_BUNDLE_ID`, `APPLE_ROOT_CERT_DIR` | Needed to verify StoreKit receipts and Apple's signature chain. |
| `LLM_PROVIDER` (+ key/model) | Not `fake` in a live environment. |

`claim_database` also binds the database to its `APP_ENV` on first write: point a `staging` process
at a `prod` database later and it refuses to start rather than metering real users. So decide
`APP_ENV` before the first `apply_schema` run.

**Staging and production must be separate Supabase projects** (separate databases). `claim_database`
enforces one environment per database, so a single project cannot serve both — a second environment
pointed at the same database refuses to boot. Create one project per environment.

## 5. Data-API / row-level-security posture

The tables are created in `public`, which Supabase exposes through its Data API (PostgREST). This app
uses **none** of that — it connects only as the database owner over the connection string. So the
posture is: **deny the Data API entirely.** Two steps, do **both**:

**A. Turn the Data API off for `public` (the decisive step).** Dashboard → **Settings → API →
Exposed schemas** → remove `public`. This disables PostgREST for the whole schema and does not depend
on getting grants exactly right. Do this even if you do nothing else.

**B. Run the hardening SQL** (defence in depth, and it covers `service_role` which step A's UI does
not always). From any machine with `psql` — note it is a plain `postgresql://` URL, **not** the
`+asyncpg` one, and there is no `db` container in this deployment:

```bash
psql "postgresql://postgres.<ref>:<pw>@aws-<n>-<region>.pooler.supabase.com:5432/postgres" \
  -f scripts/harden_supabase.sql
# …or paste the file's contents into the dashboard SQL editor.
```

`scripts/harden_supabase.sql` does three things, because RLS alone is not enough:
1. **Enables RLS** (no policies) on every current `public` table — denies `anon`/`authenticated`.
2. **Revokes all grants from `anon`, `authenticated`, AND `service_role`** — `service_role` has
   `BYPASSRLS`, so a leaked service_role key would read everything through PostgREST *despite* RLS;
   this is what stops it.
3. **`ALTER DEFAULT PRIVILEGES`** so a table added later (a new model picked up by `create_all`) is
   denied by construction, not left exposed until someone re-runs the script.

Verified on the Supabase Postgres image: none of this touches this server — the owner role keeps its
own privileges, so reads and writes continue unchanged; only the REST surface is closed. The real
access control is unchanged either way: the connection string is a secret and every query in the code
is already scoped by `principal_id`.

## 6. App host — where the FastAPI server runs

_(Open decision — not part of the database move. Filled once chosen.)_
