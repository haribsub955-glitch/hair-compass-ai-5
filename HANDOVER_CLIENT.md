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
