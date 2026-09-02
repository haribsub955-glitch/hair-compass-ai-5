# CLAUDE.md

Guidance for Claude Code in this repository. Target gate: G3 (Production — shipped App Store app).

## What this app is

Hair Compass AI 5 — native iOS hair/scalp tracking app. SwiftUI + SwiftData, iOS 26 deployment
target, Apple frameworks only (no SPM/CocoaPods). AI features run on-device via FoundationModels
(Apple Intelligence) — no cloud, no key. Tests use **Swift Testing** (`@Test`/`#expect`), UI tests
use XCTest. A Home Screen widget shares data through App Group `group.harib.Hair-Compass-AI-5`.

## Branch topology (read this before choosing a base)

- **`feat/agent-profile-memory` is the LIVE product line.** 1.0 was approved by App Review from
  `6e966f1` (build 4 lineage). `131c4ba` on it is the 1.1 feature commit (see Monetization).
- `rebuild/clinical-minimal` (the nominal main) is **dead since 2026-08-22** — it holds an
  abandoned direction (cloud DeepSeek AI, full monetization wall, Wren-everywhere). Don't base
  new work on it without an explicit decision.
- `fix/appstore-2.1-3.1.2` — rejection-fix wave for 1.0; superseded by 1.1. Its three surviving
  fixes were ported to `fix/1.1-polish` (availability watch, Open Settings removal, periodLabel).
- `design/monetization-hard-wall` holds the App Review rejection log (both rejections + causes).

## Build, run, test

Scheme **`Hair Compass AI 5`**, plain `.xcodeproj`. Builds run on the Mac
(`ssh mac`, clone at `~/Projects/hair-compass-ai-5`); GitHub is the only sync plane — push a
branch, fetch on the Mac. Full remote-loop recipe: `ios-remote-loop` skill.

```bash
# Unit suite (~220-350 s on the 2016 Intel MBP)
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination "platform=iOS Simulator,id=DBA94B02-F422-45A8-B0F6-57487CD5AA72" \
  -only-testing:"Hair Compass AI 5Tests"
# UI tests: ALWAYS -parallel-testing-enabled NO (parallel clone sims crash launchd_sim on Intel)
```

- Automation simulator `HC-Automation` = `DBA94B02-F422-45A8-B0F6-57487CD5AA72`; never touch the
  user's iPhone 16e sim.
- Test targets use file-system-synchronized groups — a new test file needs no pbxproj edit.

## Monetization (1.1 access model)

- StoreKit 2 in `Service/PurchaseService.swift`; product IDs `com.harib.haircompass.pro.monthly2`
  / `.yearly2` (the "2" suffix is required — un-suffixed IDs were burned in ASC), group "Premium".
- Since 1.1 (`131c4ba`): every fresh install gets a **3-day full-access window** anchored in the
  Keychain (`Service/AccessWindow.swift` — reinstalls and clock rollbacks cannot restart it).
  After it, Today/Trends/Labs/Photos sit behind `ProGate`; **Plan (medication logging) is free
  forever** — a dose schedule is a safety surface. `ProAvailability.sellable` is always true: Pro
  carries device-independent value, so the paywall sells on every iPhone and the Apple
  Intelligence notice narrows to the two AI gates (`requiresOnDeviceAI: true`).

## Conventions & gotchas

- `ProAvailability.current` / `OnDeviceAvailability.current` are static system reads SwiftUI does
  NOT track. Any view rendering availability needs the watch pattern: `scenePhase` bump + 2 s
  change-detecting poll into an `availabilityRefresh` token (see `ProGate`). One-way polls fail
  open — watch both directions.
- Never add an "Open Settings" button for Apple Intelligence: `openSettingsURLString` opens THIS
  app's settings page, and the Apple Intelligence & Siri pane has no public URL. Name the Settings
  path in copy instead. (BodySignals/Care keep their buttons — those target app permissions.)
- Archive builds ignore the scheme's `.storekit` fixture — a green local StoreKit test proves
  nothing about submission readiness; only TestFlight sandbox purchases prove ASC config.
  Submission checklist: `ios-appstore-submission` skill.
- DEBUG launch args for QA: `HC_AI_STATUS <available|notEnabled|modelNotReady|deviceNotEligible>`,
  `HC_ONBOARD`, `HC_ONBOARD_STEP <n>`, `HC_PAYWALL_BOTTOM`, `HC_NORITUAL`.
- Trial copy: hyphenated compound modifiers stay singular — `PurchaseService.periodLabel` ("3-day
  free trial"); regression-tested in `PurchaseCopyTests`.
- Legal/support URLs live in `Model/AppInfo.swift` and must point at `haircompass-ai.com`
  directly (the GitHub Pages host is a redirect hop the readiness test blacklists).
- Every AI reply passes `AIOutputValidator` (OnDeviceAnalysisService.swift) AFTER generation:
  any digit not literally present in the record JSON (only "24" exempt) or any ungrounded
  clinical term (thyroid, vitamin d, pregnancy…) replaces the WHOLE answer with the "couldn't
  safely summarize" fallback. The chat system prompt (`HairChatPrompt.system`) is written to
  keep the model inside those rules — digits only from the record, general knowledge in words —
  so keep prompt and validator in step when editing either (contract tests: HairChatTests).
- FoundationModels generations cannot run on the Intel Mac's simulators (host lacks Apple
  Intelligence) — prompt/gate behavior with a LIVE model is verifiable only on a real
  AI-capable iPhone.

## QUEUE

0. **Decision (user + Harib): does the cloud agent ship at all, and to whom?** Full analysis in
   the "Spend Line" review (artifact, 2026-09-02). Recommendation: cloud = paying subscribers
   only, verified from the `subscription_token` StoreKit JWS already in the `/v1/session`
   contract, with `originalTransactionId` + `appAccountToken` bound to one principal; free tier
   stays on-device (which is what ships today). That single decision removes the anonymous
   free-tier farming risk and takes App Attest off the v1 critical path. Everything below in
   this block depends on it. Not started — it is a product decision, not mine.
0b. Server work (Harib's repo, not this one), in order once 0 is decided: make the five unwired
   controls reachable and prove it through the real HTTP route · atomic USD reservation before
   every provider call (a counter does not cap under concurrency) · four kill switches, failing
   closed to the on-device path · edge caps (input size, history window, one tool wave,
   tool-result bytes, `max_tokens`, whole-turn deadline, disconnect cancellation).
0c. This repo, small, blocked on 0: move `AgentBridge.installationID` from `UserDefaults` to the
   Keychain — UserDefaults is wiped by app deletion, so reinstall currently mints a new user with
   a fresh allowance. `AccessWindow` already does exactly this for the 3-day window. Also decide
   what `X-Access-Key` is in a Release build: it currently defaults to a scheme env var and the
   client omits the header when empty, so a shipped build would send none. Both only matter if
   the cloud path ships, hence blocked on 0.
1. User: re-test the three chat questions on a real AI-capable iPhone at `266a476` — expect
   real answers (words, not digits) instead of the "couldn't safely summarize" fallback.
2. Harib (or user says merge): pull `0ea1e55` + `266a476` from `fix/1.1-polish` into
   `feat/agent-profile-memory` — he already fast-forwarded onto `3a899f1` on 2026-09-02.
3. User: final on-device/simulator UX pass of 1.1 before submitting build 5.
3b. done 2026-09-02 — Wren-identity prompt hardening + gate-contract test, full suite green
   at `266a476` (unit 180s, UITests 91s).
4. done 2026-09-02 — diff GitHub vs local, port surviving fixes onto 1.1 (`e2ad25a`).
5. done 2026-09-02 — codex+agy review round: codex P2 (dependency read inside unavailable
   branch) + agy icon-severity fixed in `d0def34`; agy's step-13 and DCE findings discarded
   with verified reasons (see commit message).
6. dropped — resubmission ASC lane for 1.0: app already approved and live.
