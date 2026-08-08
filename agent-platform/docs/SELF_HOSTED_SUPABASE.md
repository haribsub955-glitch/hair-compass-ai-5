# Self-hosted Supabase on beelink — the reusable dev/staging platform

**Status:** v2. v1 was **FAILed by adversarial review** (two independent external reviewers) — a plain
"isolated" Docker network does not stop egress, the auto-deploy was a supply-chain shell, and the
stock Supabase stack ships a Docker socket + a Deno RCE service. v2 is built around the three
controls those reviews said are load-bearing. **Nothing is exposed until v2 clears re-review.**

**Goal:** one self-hosted Supabase on beelink that mirrors Supabase Cloud, so an app developed
against it moves to Cloud with a `pg_dump`/restore + a `DATABASE_URL` change — never a rewrite. First
consumer: **agent-platform**. Future apps reuse it.

> Hard requirement: **a partner (and his AI agent), given every Supabase credential + both
> hostnames, reaches ONLY Supabase — never the beelink host, the Docker daemon, another container,
> or another service.** The reframing the review forced: the partner is effectively a Postgres
> superuser (Studio → `postgres-meta` runs SQL as `supabase_admin`), so containment can NOT rest on
> "non-superuser role." It rests on **egress-locking the Supabase containers** and **keeping the
> partner's code and infra off beelink**. Those are Controls 1–3.

## The three load-bearing controls (all three, or the isolation fails)

### Control 1 — Partner's code and infra never execute on beelink unchosen (closes supply-chain RCE)
The v1 "push → beelink `git pull && docker compose up --build`" *is* a beelink shell: a collaborator
commits a compose with `/var/run/docker.sock` or `/:/host`, a Dockerfile `RUN`, or edits
`.github/workflows/*` to exfiltrate the deploy secret. Closed by:
- **Infra is owner-only.** The compose, Dockerfiles, `.env`, tunnel token, and deploy workflow live
  in an **owner-controlled repo/path the partner cannot push to** — never in the shared app repo.
- **beelink never `--build`s partner source.** CI (GitHub Actions, isolated runner) builds the app
  image, and **beelink only `pull`s a trusted, tagged image**. A malicious Dockerfile `RUN` executes
  in throwaway CI, never on beelink; beelink's compose is owner-owned, so no socket/root mount can be
  injected.
- **Deploy secret** in a GitHub **Environment requiring owner approval**; branch protection bars
  workflow edits; the deploy job is not triggerable from a partner-editable workflow file.
- Net: the partner changes **application code** (→ a new image, run in the hardened container); he
  cannot change **what runs on the host**.

### Control 2 — Egress-locked Supabase network (closes host-gateway / published-port / LAN / SSRF)
A plain bridge blocks bridge→bridge by IP but NOT the container→host-gateway route, so `172.x.0.1:<any published port>`, host SSH/Samba, and the LAN stay reachable — and `pg_net` reaches them from SQL with no shell. Closed by:
- **`supabase-net` is `internal: true`** (Docker internal network: no default route, no masquerade).
  db/kong/auth/rest/meta/studio need **zero outbound** — they only talk to each other.
- **Only `cf-supabase` (the tunnel connector) has egress**, dual-homed on `internal` supabase-net +
  a tiny `egress-net` reaching only Cloudflare. It runs **no user code**, so it is not a pivot.
- **`DOCKER-USER` DROP backstop** (belt + suspenders): drop the supabase subnet → `172.x.0.1`, the
  LAN/RFC1918, and other docker subnets; allow DNS + established only.
- **Drop the SQL-egress extensions**: `harden_supabase.sql` (and DB init) `DROP EXTENSION`/revoke
  `pg_net`, `http`, `dblink`, `postgres_fdw`, and revoke `CREATE SUBSCRIPTION` from every non-owner
  role. Egress control is the backstop; removing these removes the no-shell SSRF path.

### Control 3 — Minimal hardened stack; contained superuser (closes docker.sock / Deno RCE / host binds)
The stock Supabase compose ships surfaces the app does not use and the review flagged:
- **Exclude `analytics`/`vector`** — stock mounts `/var/run/docker.sock` (even `:ro` is a full Docker
  API = host takeover). Not run.
- **Exclude `functions`/`edge-runtime`** (Deno = arbitrary code execution by design). Not run.
- **Named volumes only** — never `./volumes/...` host bind-mounts (storage/imgproxy). Storage/imgproxy
  excluded unless an app needs them, then with named volumes + the same hardening.
- **`supabase-db` hardened:** `no-new-privileges`, dropped caps, **no Docker socket, no host
  bind-mounts** (only its named data volume). So Studio-superuser → `COPY … FROM PROGRAM` yields a
  shell **inside db**, which — under Control 2 — has no network egress and no host reach. The partner
  can do anything *within* Supabase (it is his to test); he cannot get out.
- **Stack run = the core that mirrors Cloud:** `db, kong, auth (gotrue), rest (postgrest), meta,
  studio`. That is Auth + REST + Studio — the common Cloud surface — minus the RCE/socket services.

## Topology (v2)

```
GitHub (app code, shared)                 owner-only infra repo/path (compose, Dockerfiles,
   │ push branches/PRs (partner)             .github/workflows, .env, tunnel token)
   ▼ owner merges main → CI                       │
CI (isolated runner): build + scan → push image to registry
   │                                              │ owner approves deploy Environment
   ▼ beelink PULLS trusted image (never --build)  ▼
beelink
  ├─ net: supabase-net  (internal: true — NO egress)
  │    ├─ supabase-db  (unprivileged, socketless, named volume only)
  │    ├─ kong, auth, rest, meta, studio          (no host ports)
  │    └─ cf-supabase  (also on egress-net → Cloudflare only; forwards ONLY studio/api/pg)
  ├─ net: agent-db-net  (internal: true)  db ⇄ agent-platform only
  │    └─ agent-platform  (no debug ports, no docker socket; API is X-Access-Key gated)
  └─ DOCKER-USER: DROP supabase/agent subnets → host gw, LAN, other docker subnets (DNS/est. only)
```

- **db is dual-homed** (supabase-net for the Supabase services, agent-db-net for agent-platform).
  A DB-container shell could otherwise initiate to agent-platform (which holds the Anthropic key +
  `secret_key`); a `DOCKER-USER` rule blocks db→agent-platform initiation (agent-platform initiates
  to db, established only). agent-platform runs no debug ports and no socket, and Control 1 keeps its
  code owner-trusted — so its secrets stay out of the partner's reach.
- Nothing Supabase or agent-platform binds a host port; the dedicated tunnel is the only ingress,
  gated by Cloudflare Access (partner identity).

## Multi-app / reuse
- **agent-platform** needs only Postgres → its own database in `supabase-db`, via `DATABASE_URL`.
- **Future apps** using the Supabase SDK get their own database + scoped roles here, or their own
  stack (the compose is a template) to mirror "one Cloud project per app." Same software as Cloud →
  no re-code on cutover.

## Migration (remove vanilla Postgres)
`agent-db` (`postgres:17-alpine`) holds **140 test principals**. `pg_dump` → create the
`agent_platform` database in `supabase-db` → restore → `harden_supabase.sql` → repoint
`DATABASE_URL` → verify (`/livez`, `/health`, a real turn) → decommission `agent-db` (keep its
volume until verified). Reversible up to the last step.

## Cloud cutover (later)
`pg_dump` beelink Supabase → restore into the Supabase **Cloud** project → flip `DATABASE_URL` to the
Cloud session-pooler string. No app changes (engine switches local↔cloud automatically). An agent
performs it.

## Decisions for you
1. **Tunnel domain/hostnames** (`studio.…`, `api.…`) + the Cloudflare zone.
2. **Partner's Cloudflare Access identity** (email/SSO) for the gate.
3. **Studio for the partner, or non-superuser + no Studio?** Studio is fine *iff* Controls 2–3 are
   airtight (superuser stays contained in db); non-superuser + no Studio is the stronger,
   smaller-surface option. (Either way the partner never gets the tunnel token or an SSH key.)
4. **Does any app need Storage/Functions?** If yes, we add them deliberately with named volumes + no
   socket + the same isolation — never the stock defaults.
5. **Owner-only infra location** — a separate private repo, or a beelink-local path CI deploys from.
