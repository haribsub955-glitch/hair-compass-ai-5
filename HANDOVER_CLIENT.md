# Client handover — continuing this on macOS

Written so you should not need to ask anything to get started. Where something is unknown or
undecided it says so explicitly rather than leaving you to discover it.

**The one fact that shapes everything below: no Swift in this project has ever been compiled.**
Everything under `Hair Compass AI 5/Service/Agent/` was written without a compiler, against APIs
read from source rather than checked by a build. Assume it does not build until you have proved it.
That is the gap your Mac closes and the reason this document exists.

**Split of work.** You own the phone. The server is read-only to you: it runs on a machine you do
not control, deployed from a separate repository you do not need. Its full contract is written out
in §4 — code against that, not against its source.

---

## 1. Access — read this before your first request

The server is reachable over the internet, so it sits behind a pre-shared key. **Every request to
every endpoint must carry it**, including `/health`. Without it you get `401` and nothing else —
no hint, no difference between "missing" and "wrong".

```
X-Access-Key: <ask Mohammed>
```

The client already sends it. `AgentClient.Configuration.accessKey` defaults to reading
`HC_ACCESS_KEY` from the process environment, so in Xcode:

> Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
> `HC_ACCESS_KEY` = the value you were given

**Never commit it.** `.gitignore` covers `.env`, `*.xcconfig` and friends, but the scheme
environment is the intended home. If you see `401` on everything, this is why, 90% of the time.

This key is *not* user authentication. It is a wall around the whole deployment while the real
authentication is being built — which is your first task.

Base URL is configuration, not a constant: `AgentClient.Configuration.baseURL`. Ask for the
hostname; do not hardcode it in a committed file.

---

## 2. First hour

```bash
open "Hair Compass AI 5.xcodeproj"

xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expect failures in `Service/Agent/`. Six API mismatches were already found and fixed by *reading*
`Model/Models.swift` — `shedRaw` not `shedCount`, `collectedAt` not `date`, `LabFlag` has no
`rawValue`, `ShedLevel` is Int-backed, `rapidWeightLossPercent(samples:)` not `snapshots:`,
`loggingStreak(entryDates:now:calendar:)`. Reading catches some. A compiler catches all.

Fix the build before starting §3. Do not build features on code that has never compiled.

Then the tests — **Swift Testing, not XCTest**, in the unit bundle (`import Testing`, `@Test`,
`#expect`). UI tests remain XCUITest.

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# one suite
-only-testing:"Hair Compass AI 5Tests/AgentMemoryTests"
```

Pick a simulator that exists and runs iOS ≥ 26.2 (`xcrun simctl list devices`); `simctl boot` it if
it shows Shutdown. Paths contain spaces — always quote.

Useful launch arguments (all `#if DEBUG` except `HC_SEED_DEMO`): `HC_SEED_DEMO` seeds demo data,
`HC_TAB <today|trends|care|labs|photos>` opens a tab, `HC_NORITUAL` suppresses the launch
animation, `HC_NOLOCK` skips the Face ID gate. `grep -roh 'HC_[A-Z_]*' --include=*.swift .` for the
full set (~28).

---

## 3. Your first real task, and why it is the release blocker

**`/v1/session` authenticates nothing.**

The server derives a user's identity from `installation_id` — a value this app generates and sends.
Anyone who learns someone's installation id can post it, receive a valid session token for *their*
account, and read their consent record and audit trail or erase their account. Two independent
adversarial reviews found it. It also means any random string is a brand-new user with a fresh free
allowance on a provider key that costs real money.

The server half is already built and waiting: a `device_keys` table, a proof check on
`/v1/session`, and a `REQUIRE_DEVICE_BINDING` flag. **It is switched off, because no client can
satisfy it yet.** That is you.

### What to build

1. **First launch** — generate a P-256 keypair in the Secure Enclave. `CryptoKit`'s
   `SecureEnclave.P256.Signing.PrivateKey` is the shortest path. The private key never leaves the
   device; that is the entire point. Persist the key's representation in the Keychain with
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and **not** synchronisable — a key that
   syncs to iCloud exists on two devices, which defeats binding.
2. **First request only** — send the public key as base64 DER in `device_key`. The server binds it
   trust-on-first-use: the first caller to claim an unused installation id gets it, and afterwards
   the id alone is worth nothing.
3. **Every later session** — sign the exact bytes `"<installation_id>:<unix_timestamp>"` and send:
   * `device_proof` — base64 of the DER ECDSA signature
   * `device_proof_at` — the same integer timestamp you signed
   Server tolerates ±300 s of clock skew.
4. **On `401`** — clear the cached session token and re-run `/v1/session` once. Do **not** silently
   retry the original turn: the user may already have been metered for it.

### Proving it works

Ask for `REQUIRE_DEVICE_BINDING=true`, then confirm three things: a valid proof succeeds; the same
request with `device_proof` removed returns `401`; a proof timestamped ten minutes ago returns
`401`.

### Then: App Attest

Upgrades the binding from "some key" to "a key inside real Apple hardware running our bundle id",
which is what distinguishes this app from a script with a stolen key.

`DCAppAttestService.shared` — check `isSupported`, `generateKey()`, `attestKey(_:clientDataHash:)`
with a server-issued challenge, then `generateAssertion` per request. Send the attestation object
base64-encoded alongside `device_key`.

It **must degrade to the plain key binding, never hard-fail**: attestation is unavailable on the
Simulator, on jailbroken devices, on enterprise builds and during Apple outages. The server's
`AttestationPolicy` already expects that shape and treats attestation as advisory until the data
says otherwise.

The server's verifier is written and tested — including against a certificate-chain bypass that a
review found by *executing* it — but nothing calls it yet.

---

## 4. The server contract, complete

Every endpoint: `X-Access-Key` header (§1). Every endpoint except `/v1/session`: `session_token` in
the body. Errors are always the same envelope —
`{error_code, message, correlation_id}` — never a stack trace, never a provider message. Quote the
`correlation_id` when asking about a failure; it is in the server log.

### `POST /v1/session`

The only endpoint that accepts an installation id.

```jsonc
{
  "installation_id": "stable-per-install-uuid",
  "subscription_token": "",        // StoreKit JWS; empty is fine in dev
  "protocol_version": 1,
  "device_key": "",                // base64 DER, first contact only (§3)
  "device_proof": "",              // base64 DER signature
  "device_proof_at": 0,            // unix seconds
  "hints": {
    "platform": "ios",
    "app_build": "12",
    "os_version": "26.2",
    "available_capabilities": []   // tool names THIS build implements
  }
}
```

Response:

```jsonc
{
  "protocol_version": 1,
  "pack": "hair-compass", "pack_version": "2026-07-29.1",
  "session_token": "…",            // use for everything else; ~24h
  "principal": { "principal_id": "p_…", "entitlement": "free|pro", "plan_id": "taster", … },
  "upgrade": "current",            // current | encouraged | required
  "device_attested": false,
  "offer": { … },                  // see below
  "tools": [ { "name": "…", "description": "…", "schema_": {…},
               "mutates": false, "requires_idempotency_key": false } ],
  "envelope_schema_versions": [1]
}
```

* **`plan_id`** is the real plan — `free`, `taster`, `trial`, `pro_monthly`, `pro_yearly`.
  `entitlement` is a coarse two-case flag kept for an internal tool gate; **read `plan_id`.**
* **`upgrade`** — show a soft prompt on `required`; you are still served. A hard refusal arrives as
  **426** and means this build may no longer talk to this server.
* **`offer`** — what the paywall renders: `products` (monthly first, then yearly),
  `default_product`, `trial_days`, `free_days`. **Deliberately carries no prices.** App Store
  Connect is the only thing that knows what a given user in a given country actually pays; read
  prices from StoreKit and never from us.
* **`tools`** — the effective set: server allowlist ∩ plan ∩ platform ∩ protocol ∩ what you
  advertised. Your `available_capabilities` can only ever *narrow* it. Claiming a tool you cannot
  run gains nothing; omitting one you can run simply loses it.

### `POST /v1/turn` — SSE

`{session_token, user_text, platform, available_capabilities}`.

Event sequence: `open` → (`tool_request` → you submit results)* → `answer` → `done`.

```
event: open          {"run_id": "r_…", "protocol_version": 1}
event: tool_request  {"parallel": true, "deadline_seconds": 30, "calls": [{"id","tool","arguments"}]}
event: answer        {"text": "…", "served": true, "safety": "allow", "iterations": 2, "usage": {…}}
event: error         {"message": "…"}
event: done          {"run_id": "r_…"}
```

**`parallel: true` means run them concurrently and submit each as it finishes** — a fast read must
not wait behind a slow one. The server dispatches reads together and each mutation alone.

**`served: false` is not an error.** It means the safety layer stripped the answer or the loop
stopped on something it could not verify. Render your own deterministic summary instead; showing an
error there would hide a perfectly good local answer.

**Refusals, all before the stream begins:**

| Code | `error_code` | Meaning |
|---|---|---|
| 401 | `unauthenticated` | Missing access key, or invalid/expired session token |
| 402/403 | `not_entitled` | Plan does not include this |
| 403 | `consent_required` | **See §5 — this will bite you** |
| 426 | `protocol_unsupported` | Build refused; must update |
| 429 | `quota_exhausted` | Rate limited |

### `POST /v1/turn/result`

`{session_token, result: {call_id, status, payload, error}}` where `status` is
`succeeded` | `failed` | `expired` | `unknown`.

Idempotent — a resend returns `accepted: false`, not an error. A tool that throws becomes a
`failed` result for **that call alone**, never a failed turn. No run id and no tool name: the
server already knows both from the `call_id` it issued, and anything you stated would be a claim it
would have to verify.

### Privacy — `POST /v1/privacy/consent` · `/state` · `/forget`

```jsonc
// consent
{"session_token": "…",
 "decision": {"purpose": "agent-analysis", "granted": true,
              "policy_version": "1.0", "crosses_border": true}}
```

`/state` returns every purpose **including ungranted ones**, so the screen can show what was
actually agreed and a user can verify a withdrawal worked. `/forget` erases server-side data and
reports what it removed.

Two honest gaps: `/forget` does **not** invalidate the current session token, which stays valid up
to 24 h; and spend counters are deliberately retained (a pseudonymous id, a date, an integer) so
erasure cannot be used to farm fresh allowances.

---

## 5. The 403 that will cost you an afternoon

**A turn is refused until `agent-analysis` is granted with `crosses_border: true`.**

The model provider is outside Oman, so a turn is a cross-border transfer of health data. Oman's
PDPL requires explicit consent for that, and the server checks **its own stored record** — sending
`crosses_border: true` in a request body does nothing, because a client-asserted flag is not a
check. This was found and fixed exactly because it used to be one.

So: wire the consent screen before you try to run a turn. Grant it once per install in dev.

If you see `403 consent_required`, the system is working correctly.

---

## 6. Attachments — asked, and the honest answer

**The agent cannot accept images or PDFs today.** The capability is *declared* — the Anthropic
adapter advertises `IMAGE_INPUT` — but there is no transport: `TurnRequest` carries
`{session_token, user_text, platform, available_capabilities}` and nothing else. No image field, no
media type, no PDF, and no attachment path in this client.

What exists instead:

* **Progress photos** already reach a model through the app's *separate* one-shot
  `CloudAnalysisService` path, gated behind explicit `AIConsent`. That is not the agent.
* **Lab PDFs** are handled on-device by Vision OCR, and the extracted *values* become facts. The
  raw document never leaves the phone.

That second pattern is the better design and worth keeping when attachments do arrive: for a health
app under PDPL, extracting facts on-device and sending the facts is materially safer than shipping
raw documents across a border, and it is what `AIContextBuilder` already does.

**If we add it**, it is a protocol change, not a client change — a field on `TurnRequest`, a size
cap, a media-type allowlist, its own consent purpose (photos are the most sensitive data here), and
the safety layer taught to screen image inputs. Do not build it client-side first; raise it and it
gets specified server-side.

---

## 6b. The agent is not connected to any screen — verified, not assumed

`AgentClient` is referenced by **zero views**. Searched: every `.swift` outside `Service/Agent/`
mentions it nowhere. The agent runs no user-visible flow today.

What exists instead:

* **`Feature/HairChatSheet.swift`** — a working chat UI, scope-guarded, backed by
  `HairChatService` (the older on-device / one-shot cloud path). It does **not** use the agent.
* **`Feature/DeepAnalysisSheet.swift`** — likewise, on the pre-agent path.
* **No attachment control in either.** No `PhotosPicker`, no `fileImporter`, no paperclip.

So there are two clients to the same idea living side by side: the shipped chat, and the agent that
was built to replace it. Connecting them is real work and it is yours. Two honest options:

1. **Point `HairChatSheet` at `AgentClient`.** Keeps the screen users already have, swaps what is
   behind it. Smaller, and the UI is already scope-guarded and styled.
2. **Give the agent its own surface.** Justified only if the agent's tool-calling loop needs to
   show something the chat cannot — tool progress, multi-step reasoning.

Option 1 unless you find a reason. Note that the agent's turn is a *stream* with tool round-trips
in the middle, so the sheet needs to render intermediate state (`tool_request` waves) that a
one-shot chat never had to.

**On the attachment button specifically:** if you add one, it cannot reach the model through the
agent — there is no transport for it (§6). Wiring a picker to the agent would silently drop the
attachment. Either route attachments through the existing `CloudAnalysisService` path, which does
handle photos behind `AIConsent`, or raise it and get the protocol extended first. Do not build a
button that appears to work.

---

## 7. What is already on the phone

| File | What it is |
|---|---|
| `Service/Agent/AgentClient.swift` | Actor. Session, SSE parsing, tool dispatch, result submission, access-key header. **No device key yet (§3), does not read `offer`.** |
| `Service/Agent/AgentToolExecutor.swift` | SwiftData-backed tool implementations + idempotency log |
| `Model/AgentProfile.swift` | On-device profile; `{{name}}` substituted client-side, age derived |
| `Model/AgentMemory.swift` | `@Model` + store; scope = visibility, sessionID = provenance |
| `Model/Models.swift` | The 9 SwiftData `@Model` types. **Read before touching tools.** |

House rules, not negotiable:

* **Apple frameworks only.** No SPM, no CocoaPods, no third-party SDKs. This is why there is no
  Alamofire and no image-caching library, and it is deliberate.
* Files join their target **by folder** (`PBXFileSystemSynchronizedRootGroup`) — adding a `.swift`
  file needs no `project.pbxproj` edit. Only capabilities, entitlements and Info.plist keys are
  real project config.
* Use the tokens in `Design/Clinical.swift`. Never hardcode a colour. The enum is called `Clinical`
  but the identity is deliberately warm ("Botanical Heritage") — do not "fix" the warmth.
* **Every stored `@Model` attribute needs an inline default** or must be optional. A new mandatory
  attribute without one fails lightweight migration and the container deletes and recreates the
  store. That is data loss, and it has happened here.
* Charts: overlaying `LineMark` groups without `series:` merges them into one line.

---

## 8. Two lessons this codebase paid for in full

**"Written and tested" is not "wired."** Five separate controls here were implemented,
unit-tested, green — and not on the path a request actually takes: the paywall, the rate limiter,
the per-plan budget caps, the consent gate, and App Attest. Every unit test passed the entire time.
Correctness and reachability are *different claims*, and a unit test only makes the first. When you
add a control, add a test that drives it through the real entry point.

**Run it before believing it.** A backup script sat scheduled, executable and mounted for weeks
producing nothing, because CRLF line endings made the shebang `#!/usr/bin/env bash\r`. Nothing
looked broken. On your side the equivalent is: launch it in the Simulator and drive the flow.
A green build is not a working screen.

---

## 9. Leave alone

* **Server deployment, its `.env`, and the access key.** Not yours; secrets are in no repository.
* **The evidence-tier framing.** Signals carry an honest tier, myths are named-and-excluded rather
  than silently dropped, treatment-efficacy stays behind the 24-week gate, and where money is
  involved the rating is shown and never bent. It is the product's spine.
* **`docs/superpowers/specs/`** — design specs backing specific subsystems. Read, don't rewrite.

## 10. Ask about these rather than guessing

* The base URL and the access key.
* Turning on `REQUIRE_DEVICE_BINDING` when §3 is ready — it is a coordinated switch.
* Anything touching money: plan ids, receipt handling, `appAccountToken`. Server-side and
  half-finished; the ownership binding in particular must land before the first paid release.
* Attachments (§6) — protocol change, not a client change.

The server's own outstanding list lives in its repo as `docs/READINESS.md`. It is blunt about what
does not work. Ask for it.

---

# Part II — the things that touch your UI

Everything above is how to get running. This part is what you actually build against, written for
someone maintaining the interface rather than the backend. Where a thing lives on the server it says
so, and says whether you can change it.

---

## 11. Running the agent, and using your own API key

**The phone never holds a provider API key.** It is server-side and always was — that is the point
of the whole architecture. A key shipped in an app is a key extracted from the app.

Two ways to work:

### A. Point at Mohammed's server *(recommended, nothing to set up)*

Set `baseURL` and `HC_ACCESS_KEY` (§1). You need no provider key at all — the server holds one and
meters your turns against a plan. This is the fastest path and the one that tests the real thing.

### B. Run the server yourself, with your own key

Useful when you want to change the system prompt, try another model, or work offline. You need the
server repository and Docker:

```bash
cp .env.example .env      # then edit:
#   LLM_PROVIDER=anthropic
#   LLM_API_KEY=sk-ant-…              your own key
#   SECRET_KEY=<32+ random chars>
#   DATABASE_URL=postgresql+asyncpg://agent:pw@db:5432/agent_platform
#   ACCESS_KEYS=                       leave empty locally — no front door needed on a laptop

docker compose up -d
curl localhost:8100/health
```

Then point the app at `http://<your-mac-lan-ip>:8100`.

**Free local option — no API key, no cost:** install LM Studio, load any model, and set

```
LLM_PROVIDER=lmstudio
LLM_BASE_URL=http://127.0.0.1:1234/v1
LLM_MODEL=                    # blank means "whatever is already loaded"
```

Leave `LLM_MODEL` blank deliberately. Naming a model is not a passive preference — with
just-in-time loading it *evicts* whatever the machine already had resident, which is a rude
surprise on a shared box.

Vision works on this path too, if the loaded model is one (LM Studio reports `type: vlm`).
Confirmed with `gemma-4-e4b-it-qat`.

---

## 12. The system prompt, and what you can change

`src/agent_server/packs/hair_compass.py` in the **server** repo:

| Constant | What it governs |
|---|---|
| `AGENT_SYSTEM_PROMPT` | How the agent behaves in a turn — tone, tool use, refusal style |
| `SYSTEM_PROMPT` | The older one-shot analysis path |
| `SCOPE_POLICY` | Which questions are answered at all (§13) |
| `SAFETY_POLICY` | What the answer may not say (§14) |

**Changing it is a server deploy, not a client change.** You cannot alter it from the app, and that
is deliberate: the prompt carries the product's safety posture, so it is not something a shipped
build can be talked into changing.

If you want a change, say what behaviour you want and it gets made server-side. Running your own
server (option B) lets you experiment freely first — that is the reason to bother with option B at
all.

One known issue you will hit on the local path: small local models narrate their reasoning
("Thinking Process: 1. Analyze the request…") straight into the answer and burn the whole token
budget doing it. Not a bug in the transport — it needs a "do not think aloud" line in the prompt for
local models. Harmless in dev, expensive on a paid provider.

---

## 13. How non-hair questions are stopped

Ask the agent about football and it will not answer. That is a **deterministic scope gate**, not the
model deciding — `SCOPE_POLICY` in the pack, plain patterns, evaluated **before any spend**. No
model call, no tokens, no money.

What you see from the client is an ordinary successful turn:

```
event: answer
data: {"text": "I only cover hair and scalp health, and your own tracking record. …",
       "served": true, "safety": "allow", "iterations": 0}
```

**`iterations: 0` is the tell** — no model was called. Render it as a normal assistant message. It
is not an error and must not be shown as one.

The gate is asymmetric on purpose: a message showing *any* sign of belonging here — a domain word,
or the user talking about themselves — is allowed even if it also trips an off-topic pattern.
"I've been coding late, is stress making me shed?" is a real question and the hair half is the part
that matters.

There is a second, separate layer: the **safety screen** on the way out. It runs on whatever the
model produced and strips a personal diagnosis, a recommendation to start a prescription, a myth
asserted as fact, or an efficacy number the model invented. When it fires you get `served: false`
or a modified `text`, and `safety` says so.

**When `served` is false, show your own deterministic summary** — the app already computes real
numbers locally. Do not show an error; there is a perfectly good local answer available and an
error would hide it.

---

## 14. Attachments — what the UI must do

Working end to end today. Photos only; **no PDF** (lab documents are OCR'd on-device so only the
values travel, which is cheaper and safer than shipping the document abroad).

### The flow

```
1. check `features` from /v1/session contains "photo_analysis"   → else hide the button
2. ask for photo consent  → BEFORE opening the picker
3. PhotosPicker → Data
4. POST /v1/attachments (multipart) → { attachment_id, media_type, bytes, sha256 }
5. POST /v1/turn  { …, "attachments": ["att_…"] }
```

```jsonc
POST /v1/attachments        // multipart/form-data
  X-Access-Key: <key>
  session_token=<token>     // form field
  file=<binary>             // form field

{ "attachment_id": "att_8rLw…", "media_type": "image/jpeg",
  "sha256": "7a681e…", "bytes": 7617 }
```

### Rules that will bite you if you skip them

* **Hide the button when the plan lacks `photo_analysis`.** The free 3-day period does *not*
  include photos. Letting someone pick a photo and then refusing reads as a bug rather than a
  paywall. `features` in the session response is there precisely so you can hide it.
* **Consent prompt first, picker second.** Asking for a photo and *then* asking permission to send
  it is the wrong order and reads as a bait. Photos need their own grant — `photo-analysis`, which
  is separate from `agent-analysis` and can be declined on its own.
* **An attachment is single-use.** The server deletes it in the same statement that reads it. A
  retried turn needs a fresh upload. Never cache the id and reuse it.
* **Max 3 per turn, 8 MB each, JPEG or PNG.** Anything else is refused at upload with `413`.
* HEIC is not accepted yet — convert to JPEG before upload. iOS gives you that from
  `PhotosPicker` easily.

### Errors you must handle

| Code | Meaning | What to show |
|---|---|---|
| 402/403 `not_entitled` | Plan has no photos | The paywall, not an error |
| 403 `consent_required` | Photo consent not granted | The consent sheet |
| 413 | Too big, or not a real image | "Photos only, up to 8 MB" |

---

## 15. Affiliate products — how you add and render them

**Not built yet. Specified, and the shape is settled** — the design is in the server repo as
`docs/CATALOG.md`. This is the commercial surface: brand partnerships shown as a picture and a tap
that opens an affiliate link.

### How a product gets added

**Not by you, and not in a release.** The server owns the list; an admin UI is being added so a
brand can be added by filling a form — image, title, link, evidence tier. Devices pick it up on
their next refresh. **No App Store submission to add or change a partner**, which is the entire
point of doing it this way.

What you build is the *rendering*, once:

```jsonc
GET /v1/catalog
{ "version": 7,
  "show_evidence_tier": false,
  "products": [
    { "id": "…", "brand": "…", "title": "…",
      "image": "/assets/…",        // served by us, not the brand's CDN
      "link": "https://…",         // the affiliate network's tracked URL
      "evidence_tier": "…" }
  ] }
```

### Client rules

* **Cache to disk and always render from the cache.** The network is a refresh, never a
  dependency — the list must work with no signal.
* Send the version you hold; unchanged returns `304` with no body.
* Ship a **bundled seed catalogue** so a first launch offline is not an empty screen.
* Tap → `openURL(link)`, then post an aggregate tap count. **A failed count is dropped, never
  retried** — the affiliate network attributes the commission through its own link, so our counter
  is analytics, and analytics must never delay a user's tap.
* Images come from our server, not the brand's. That is deliberate: brands never see your users'
  IP addresses, and a brand CDN outage cannot blank the screen.
* **`show_evidence_tier` is a server flag — obey it.** It is currently off. If it flips on, render
  the tier badge; do not hardcode either behaviour.

### The disclosure is not optional

The surface must state that these are affiliate links and that we may earn a commission. Required by
the FTC and the ASA regardless of anything else. One persistent line on the surface — not buried in
Settings.

---

## 16. Testing without a phone in your hand

Everything below works from a terminal on your Mac. `$K` is the access key, `$B` the base URL.

```bash
# 1. open a session
S=$(curl -s -X POST $B/v1/session -H "X-Access-Key: $K" -H 'content-type: application/json' \
  -d '{"installation_id":"my-mac-test","hints":{"platform":"ios","available_capabilities":[]}}')
T=$(echo $S | python3 -c 'import sys,json;print(json.load(sys.stdin)["session_token"])')
echo $S | python3 -m json.tool | head -20        # plan_id, features, offer, upgrade

# 2. grant consent (once per install)
curl -s -X POST $B/v1/privacy/consent -H "X-Access-Key: $K" -H 'content-type: application/json' \
  -d "{\"session_token\":\"$T\",\"decision\":{\"purpose\":\"agent-analysis\",
      \"granted\":true,\"policy_version\":\"1.0\",\"crosses_border\":true}}"

# 3. a turn — watch the SSE stream
curl -N -X POST $B/v1/turn -H "X-Access-Key: $K" -H 'content-type: application/json' \
  -d "{\"session_token\":\"$T\",\"user_text\":\"is 80 hairs a day normal?\"}"

# 4. an off-topic question — expect iterations: 0, no model call
curl -N -X POST $B/v1/turn -H "X-Access-Key: $K" -H 'content-type: application/json' \
  -d "{\"session_token\":\"$T\",\"user_text\":\"who won the world cup?\"}"

# 5. what the server holds about you
curl -s -X POST $B/v1/privacy/state -H "X-Access-Key: $K" -H 'content-type: application/json' \
  -d "{\"session_token\":\"$T\"}" | python3 -m json.tool

# 6. erase it
curl -s -X POST $B/v1/privacy/forget -H "X-Access-Key: $K" -H 'content-type: application/json' \
  -d "{\"session_token\":\"$T\"}"
```

In the Simulator, the launch arguments in §2 get you to a screen fast: `HC_SEED_DEMO HC_TAB care`
seeds data and opens Plan.

**Ask for a tester grant** if you need a paid plan without a real purchase. Mohammed can add your
installation id to `TESTER_GRANTS` on the server — named, expiring, and audited, so it is not a
blanket "everyone is Pro" switch.

---

## 17. Quick map — where does a thing live?

| You want to change… | Where | Needs a release? |
|---|---|---|
| Any screen, layout, copy in the app | this repo | yes |
| Which questions are answered | `SCOPE_POLICY`, server | no — server deploy |
| What the answer may not say | `SAFETY_POLICY`, server | no — server deploy |
| Agent tone and behaviour | `AGENT_SYSTEM_PROMPT`, server | no — server deploy |
| Prices, trial length, what a plan unlocks | plan catalogue, server + App Store Connect | no |
| Affiliate products | admin UI, server | no |
| Which model, which provider | server `.env` | no |
| Whether photos are allowed on a plan | plan `features`, server | no |

The pattern: **the app renders, the server decides.** If you find yourself hardcoding a rule in
Swift that the server already knows, that is the wrong side — ask for it in the session response
instead. `features`, `offer`, `tools` and `upgrade` all exist for exactly that reason.
