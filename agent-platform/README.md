# agent-platform

The server behind Hair Compass AI. It owns everything the phone must not be trusted with: identity,
subscriptions, token budgets, consent, the system prompt, the scope gate and the output safety
screen. **The app renders; the server decides.**

Python 3.13 · FastAPI · SQLAlchemy · Postgres. The client is a separate repository.

---

## Running it on your machine

You need **Docker Desktop** and nothing else — no Python install, no Postgres, no local setup.
Install it first (`https://docker.com/products/docker-desktop`), start it, and confirm it is up:

```bash
docker --version
docker compose version
```

Then:

```bash
cp .env.example .env        # edit it — see below
docker compose up -d        # builds the image and starts Postgres alongside
curl localhost:8100/health
```

Two containers come up: the API on `8100`, and Postgres on `127.0.0.1:5433` (loopback only — nothing
outside the machine reaches the database). First build takes a few minutes; after that it is seconds.

```bash
docker compose logs -f agent      # follow the server
docker compose restart agent      # after changing .env
docker compose down               # stop; add -v to also drop the database
```

### The three settings that matter

```ini
# 1. Anything 32+ characters. Derives principal ids and signs session tokens, so changing it
#    invalidates every existing session — fine locally, never do it casually in production.
SECRET_KEY=<32+ random characters>

# 2. Leave exactly as shipped. `db` is the Postgres container's name on the compose network.
DATABASE_URL=postgresql+asyncpg://agent:agent@db:5432/agent_platform
POSTGRES_PASSWORD=agent

# 3. Where the model lives — pick ONE of the blocks below.
```

**Anthropic** — what production uses:

```ini
LLM_PROVIDER=anthropic
LLM_API_KEY=sk-ant-…
LLM_MODEL=claude-sonnet-5
```

**Any OpenAI-compatible endpoint** — OpenAI, OpenRouter, Groq, Together, Ollama, LM Studio all speak
this shape, so only the URL and model change:

```ini
LLM_PROVIDER=openai-compat
LLM_BASE_URL=https://api.openai.com/v1
LLM_API_KEY=sk-…
LLM_MODEL=gpt-5
```

**Local and free**, if you have LM Studio running:

```ini
LLM_PROVIDER=lmstudio
LLM_BASE_URL=http://host.docker.internal:1234/v1
LLM_MODEL=
```

`host.docker.internal` rather than `127.0.0.1` — inside a container, localhost is the container.
Leave `LLM_MODEL` blank on purpose: naming one is not a passive preference, because with
just-in-time loading it **evicts** whatever the machine already had resident.

Photos need a model that can see. `claude-sonnet-5`, `gpt-5`, or locally any model LM Studio
reports as `type: vlm`.

### Leave `ACCESS_KEYS` empty locally

It is the front door for an internet-reachable deployment (`X-Access-Key` on every request). On a
laptop there is nothing to guard, and an empty value disables it.

---

## First request

```bash
B=http://localhost:8100
S=$(curl -s -X POST $B/v1/session -H 'content-type: application/json' \
  -d '{"installation_id":"dev-1","hints":{"platform":"ios","available_capabilities":[]}}')
T=$(echo $S | python3 -c 'import sys,json;print(json.load(sys.stdin)["session_token"])')

# consent is required before a turn — see below
curl -s -X POST $B/v1/privacy/consent -H 'content-type: application/json' \
  -d "{\"session_token\":\"$T\",\"decision\":{\"purpose\":\"agent-analysis\",
      \"granted\":true,\"policy_version\":\"1.0\",\"crosses_border\":true}}"

curl -N -X POST $B/v1/turn -H 'content-type: application/json' \
  -d "{\"session_token\":\"$T\",\"user_text\":\"is 80 hairs a day normal?\"}"
```

**A turn returns `403 consent_required` until consent is granted.** That is the system working: the
model provider sits outside Oman, so a turn is a cross-border transfer of health data and PDPL wants
explicit consent. The server checks its own stored record — a `crosses_border: true` in a request
body is a claim, not a check.

---

## Tests

```bash
uv sync                     # or: pip install -e ".[dev]"
pytest -q                   # ~490, no database needed

# the Postgres ones, against the running container
AGENT_TEST_DATABASE_URL=postgresql+asyncpg://agent:agent@localhost:5433/agent_platform pytest -q
```

Those 20 skip without a database, and they are the ones that catch what unit tests cannot — a
`SELECT ... FOR UPDATE` that locks nothing, an asyncpg type inference that only fails on the real
engine. A green local run is not evidence they pass.

---

## Where things live

| | |
|---|---|
| `src/agent_core/` | Pure logic, no I/O — plans, consent, safety, the loop, dispatch |
| `src/agent_server/` | HTTP, database, providers, auth |
| `src/agent_server/packs/hair_compass.py` | **The system prompt, scope gate and safety rules** |
| `src/agent_core/plans.py` | Tiers, budgets, what each plan unlocks |
| `docs/READINESS.md` | Honest state: what works, what does not, what blocks release |
| `docs/ATTACHMENTS.md` · `docs/CATALOG.md` | Designs for photos and affiliate products |

**Start with `docs/READINESS.md`.** It is blunt about the outstanding security work, including one
open account-takeover, and it is more useful than anything else here for deciding what to touch.

---

## Two conventions worth inheriting

**"Written and tested" is not "wired."** Six controls in this codebase were implemented,
unit-tested, green — and not on the path a request takes: the paywall, the rate limiter, the
per-plan budgets, the consent gate, App Attest and the whole agent client. Every unit test passed
the entire time. Correctness and reachability are different claims. `tests/test_request_path.py`
exists to assert the second, and a new control belongs in it.

**Run it before believing it.** A backup script sat scheduled, executable and mounted for weeks
producing nothing, because CRLF line endings made the shebang `#!/usr/bin/env bash\r`. Nothing
looked broken.
