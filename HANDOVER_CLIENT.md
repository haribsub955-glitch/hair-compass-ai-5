# Client handover — picking this up on macOS

You have a Mac. That is the whole reason this document exists: **no Swift in this project has ever
been compiled.** Every `.swift` file under `Hair Compass AI 5/Service/Agent/` was written without a
compiler, against APIs read from the source rather than checked by a build. Assume it does not
build until you have proved it does.

Split of work: **you own the phone, the server is read-only to you.** The server runs on a machine
you do not control and is deployed from a separate repository. You code against its contract, which
is written out below; you never need its source.

---

## 1. First thing, before writing anything

```bash
open "Hair Compass AI 5.xcodeproj"
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expect failures in `Service/Agent/`. Six API mismatches were already found and fixed by *reading*
`Model/Models.swift` — `shedRaw` not `shedCount`, `collectedAt` not `date`, `LabFlag` has no
`rawValue`, and so on. That method catches some of them. A compiler catches all of them.

Fix the build first. Do not start the task in §2 on top of code that has never compiled.

Then the tests — Swift Testing, not XCTest:

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## 2. The task that actually blocks release

**`/v1/session` authenticates nothing, and closing it needs a Mac.**

Today the server derives a user's identity from `installation_id` — a value the app generates and
sends. Anyone who learns someone's installation id can post it, receive a valid session token for
*their* account, and read their consent record and audit trail or erase their account. Two
independent adversarial reviews found this.

The server side is already built: a `device_keys` table, a proof check on `/v1/session`, and a
`REQUIRE_DEVICE_BINDING` flag. **It is switched off, because no client can satisfy it yet.** That
is your job, and it is the last blocker before anyone outside the team touches this.

### What to build

1. **On first launch**, generate a P-256 keypair in the Secure Enclave and keep the private key
   there. `SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave`, or `CryptoKit`'s
   `SecureEnclave.P256.Signing.PrivateKey`. The private key must never leave the device — that is
   the entire point.
2. **Send the public key once**, as base64 DER, in `device_key` on the first `/v1/session`. The
   server binds it trust-on-first-use: the first caller to claim an unused installation id gets it,
   and after that the id alone is worth nothing.
3. **Every later session**, sign `"<installation_id>:<unix_timestamp>"` with that key and send:
   - `device_proof` — base64 of the DER ECDSA signature
   - `device_proof_at` — the same unix timestamp you signed
   The server allows ±300 s of clock skew.
4. **Handle `401`** by clearing the cached session token and re-running `/v1/session`. Do not
   silently retry a turn — the user may already have been metered for it.

Keychain item should be `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and **not** synchronised
to iCloud. A key that syncs is a key that exists on two devices, which defeats binding.

### How to know it works

Ask for `REQUIRE_DEVICE_BINDING=true` on the server, then confirm: a session with a valid proof
succeeds; the same request with the proof stripped returns `401`; a proof with a timestamp ten
minutes old returns `401`.

### Second, once that lands

**App Attest**, which upgrades the binding from "some key" to "a key inside real Apple hardware
running our bundle id". `DCAppAttestService`: check `isSupported`, `generateKey`, `attestKey` with
a server challenge, send the attestation object. The server's verifier is written and tested —
including against a certificate-chain bypass that a review found by executing it — but nothing
calls it yet.

Attestation fails on the Simulator, on jailbroken devices and during Apple outages, so it must
**degrade to the plain key binding**, never hard-fail. `AttestationPolicy` on the server already
expects that shape.

---

## 3. The server contract, as it stands today

Base URL is configured, not hardcoded — `AgentClient.Configuration.baseURL`. Every endpoint except
`/v1/session` takes a `session_token` and nothing else identifying.

### `POST /v1/session`
The only endpoint that accepts an installation id.

```jsonc
{
  "installation_id": "…",
  "subscription_token": "",          // StoreKit JWS, empty in dev
  "protocol_version": 1,
  "device_key":  "",                 // base64 DER, first contact only
  "device_proof": "", "device_proof_at": 0,
  "hints": { "platform": "ios", "app_build": "…", "os_version": "…",
             "available_capabilities": [] }
}
```

Returns `session_token`, `principal`, `upgrade`, `offer`, `tools`, `device_attested`.

* `upgrade` — `current` | `encouraged` | `required`. Show a banner on `required`; you are still
  served. A hard refusal arrives as **426** and means this build may no longer talk to the server.
* `offer` — what the paywall renders: `products` (monthly, yearly), `default_product`,
  `trial_days`, `free_days`. **Deliberately carries no prices** — App Store Connect is the only
  thing that knows what a given user in a given country pays. Read prices from StoreKit.
* `tools` — the effective tool set. Your `available_capabilities` can only ever *narrow* it.

### `POST /v1/turn`
SSE stream. `{session_token, user_text, platform, available_capabilities}`.

Events: `open` → `tool_request` → (you submit results) → `answer` → `done`.

`tool_request` carries `parallel`. When true, run the calls concurrently and submit each as it
finishes — a fast read must not wait behind a slow one.

**Refusals you must handle**, all before the stream starts:
`401` session invalid · `402/403` plan not entitled · `403 consent_required` · `429` rate limited.

### `POST /v1/turn/result`
`{session_token, result: {call_id, status, payload, error}}`. Idempotent — a resend is not an
error. A tool that throws becomes a `failed` result for *that call*, not a failed turn.

### `POST /v1/privacy/consent` · `/state` · `/forget`
`{session_token, …}`. **A turn is refused with `403 consent_required` until `agent-analysis` is
granted with `crosses_border: true`.** The model provider is outside Oman, so that is a PDPL
cross-border transfer and the server checks its own stored record — sending `true` from the client
does nothing. Wire the consent screen before you try to run a turn, or you will debug a 403 that is
working correctly.

`/state` returns every purpose including the ungranted ones, so the screen can show what was
actually agreed. `/forget` erases server-side data; it does **not** invalidate the current token,
which stays valid up to 24 h — a known gap, tracked.

---

## 4. What already exists on the phone

* `Service/Agent/AgentClient.swift` — actor, Foundation only. Session handling, SSE parsing, tool
  dispatch, result submission. Already updated for session tokens; **does not yet handle
  `offer`, and has no device key.**
* `Service/Agent/AgentToolExecutor.swift` — SwiftData-backed tool implementations, with an
  idempotency log.
* `Model/AgentProfile.swift`, `Model/AgentMemory.swift` — on-device profile and memory.
* `Model/Models.swift` — the 9 SwiftData `@Model` types. **Read this before touching tools.**

House rules that are not negotiable: **Apple frameworks only** — no SPM, no CocoaPods, no
third-party SDKs. Files join their target by folder (`PBXFileSystemSynchronizedRootGroup`), so
adding a `.swift` file needs no `project.pbxproj` edit. Use the design tokens in
`Design/Clinical.swift`; never hardcode a colour.

---

## 5. Two lessons this codebase paid for

**"Written and tested" is not "wired".** Five separate controls here were implemented,
unit-tested, green — and not on the path a request takes: the paywall, the rate limiter, the
per-plan budget caps, the consent gate, and App Attest. Every unit test passed the whole time.
Correctness and reachability are *different claims*. When you add a control, add a test that drives
it through the real entry point.

**Run it before believing it.** A backup script sat scheduled and executable for weeks producing
nothing, because CRLF line endings made the shebang `#!/usr/bin/env bash\r`. Nothing looked broken.
On your side the equivalent is: launch it in the Simulator and drive the flow. A green build is not
a working screen.

---

## 6. Things to leave alone

* **Server deployment and its `.env`.** Not yours, and the secrets are not in any repo.
* **The evidence-tier framing.** Signals carry an honest tier, myths are named-and-excluded rather
  than silently dropped, and treatment-efficacy claims stay behind the 24-week gate. It is the
  product's spine, not decoration.
* **`docs/superpowers/specs/`** — design specs that back specific subsystems. Read, don't rewrite.

Open questions and the full outstanding list live in the server repo's `docs/READINESS.md`. Ask for
it; it is the honest state of what works and what does not.
