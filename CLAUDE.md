# CLAUDE.md

Guidance for Claude Code in this repository. Target gate: G3 (Production — shipped App Store app).

## What this app is

Hair Compass AI 5 — native iOS hair/scalp tracking app. SwiftUI + SwiftData, iOS 26 deployment
target, Apple frameworks only (no SPM/CocoaPods). AI is cloud-first: DeepSeek through
`Service/CloudAI.swift`, only after `CloudAIConsent` is granted, with Apple Intelligence
(FoundationModels) on-device as the no-consent/offline fallback; every reply from either engine
passes `AIOutputValidator` before display. The key lives ONLY in `Config/Secrets.local.xcconfig`
(gitignored) → `Config/AI.xcconfig` → Info.plist `HCDeepSeekAPIKey`; a clone without that file
builds and simply has no cloud. **This repo is PUBLIC — never commit a key.** Tests use
**Swift Testing** (`@Test`/`#expect`), UI tests use XCTest. A Home Screen widget shares data through App Group `group.harib.Hair-Compass-AI-5`.

**Two warnings that survive the port** (from `fix/1.1-polish`, verified 2026-09-03): the key
ships inside the IPA, so the only cost control on the cloud path is the client-side daily cap in
`CloudAIBudget` (`CloudAI.swift`) — a pulled key is unmetered spend on the shared account. And
⚠️ "retest on an AI-capable iPhone" exercises the *fallback* only: with a key configured, every
iPhone answers from DeepSeek. No key literal exists anywhere in git history.

## Branch topology (read this before choosing a base)

- **`feat/agent-profile-memory` is the LIVE product line.** 1.0 was approved by App Review from
  `6e966f1` (build 4 lineage). `131c4ba` on it is the 1.1 feature commit (see Monetization).
- `rebuild/clinical-minimal` (the nominal main, and the GitHub Pages source for
  haircompass-ai.com via `docs/`) was dead from 2026-08-22 to 2026-09-02, holding an abandoned
  direction (full monetization wall, Guide/Shop tab, Lottie, Wren-everywhere). On 2026-09-02 the
  cloud DeepSeek engine and its three audit rounds were ported from it onto the live line
  (`feat/cloud-ai-on-1.1`), and main was merged to that tree. The wall/Lottie/Guide work stays
  only in history and on `design/monetization-hard-wall`.
- `fix/appstore-2.1-3.1.2` — rejection-fix wave for 1.0; superseded by 1.1. Its three surviving
  fixes were ported to `fix/1.1-polish` (availability watch, Open Settings removal, periodLabel).
- `design/monetization-hard-wall` holds the App Review rejection log (both rejections + causes).
- `fix/1.1-polish` — Moosawi's review line (agent-platform cost review, Keychain installation id).
  Merged into main 2026-09-04; nothing of it is outstanding.
- **`feat/agent-platform-server` carries the Python server as a monorepo subfolder**
  `agent-platform/` (`4af35de`) — same codebase as the local clone at
  `Programming/Harib/agent-platform`, but **copied, sharing no git history**, and **last touched
  2026-08-08**: no `global_daily_spend`, and the plan catalogue still has the un-suffixed product
  ids that resolve every real receipt to the free tier's zero budget. Syncing it is a content
  copy plus an explicit publish decision, never a merge.
- `feat/cloud-ai-on-1.1` — the DeepSeek engine ported onto the 1.1 access model; already carries
  our Wren-identity merge (`7117dbf`).

**Nothing is deployed anywhere.** No Supabase project is connected (`docs/SUPABASE.md` +
`docker-compose.supabase.yml` are a prepared migration path; Supabase would host Postgres only —
never the FastAPI app), no agent container runs, and `AgentBridge` is DEBUG-only behind
`HC_AGENT`, defaulting to `http://localhost:8100`. The phone's live AI path talks straight to
`api.deepseek.com`, so none of the server-side ledger work is in it _(verified 2026-09-03)_.

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
  `HC_ONBOARD`, `HC_ONBOARD_STEP <n>`, `HC_PAYWALL_BOTTOM`, `HC_NORITUAL`, `HC_NOTODAY` (demo seed
  skips today's `DailyEntry`, for testing the "Same as yesterday" quiet-day chip), `HC_PLANOPEN`
  (clears today's doses so the plan is fully open), `HC_PLANCLOSED` (G2 motion amendment M8 —
  `Seed.ensureDosesToday` logs every open occurrence today, forcing the closure card, the
  seven-day constellation and Close the Day), `HC_MOTION_STATIC` (renders every G2 one-shot
  animation in its final state, the way Reduce Motion does — `MotionQA.isStatic`).
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

0. **Agent-platform cost review — "The Spend Line" (artifact, 2026-09-02, corrected).**
   ⚠️ MOOSAWI_HANDOVER.md §8 ("five controls implemented, unit-tested, and not on the request
   path") is **STALE**. Verified against `Programming/Harib/agent-platform` source: atomic
   reservation (`reserve → provider call → settle`, single ON CONFLICT statement), receipt
   verification non-bypassable when live, `uq_principal_subscription`, free plan
   `daily_token_budget: 0`, device binding + access key refused-at-boot when live, rate limiter
   and consent gate on the path. Do not re-derive the threat model from the handover.
0b. done 2026-09-03 — server `70e4815` (repo `../agent-platform`, NOT pushed, awaiting the user's
   say-so): **live product ids** (the catalogue said `harib.haircompass.pro.monthly`, Apple sends
   `com.harib.haircompass.pro.monthly2`, so every real receipt resolved to the free tier's zero
   budget — a paying subscriber got nothing; the tests hard-coded the same wrong value) ·
   **global daily ceiling** (`global_daily_spend`, same atomic statement, default 7.5M tokens/day
   ≈ $100/month, refused at live boot if unset) · **`PROVIDER_SPEND_ENABLED` kill switch**
   enforced in `reserve()` so no endpoint can skip it. 596 passed.
0c. done 2026-09-03 — `16f280e`: `AgentBridge.installationID` moved to the Keychain; merged
   onto main 2026-09-04 with the rest of `fix/1.1-polish`.
0d. Still open, server side, from their own `docs/ENGINE_AUDIT_2026-08-31.md`: image cost is not
   reserved (`agent.py:449` — the cap does not apply to the expensive class) · four
   pay-for-nothing bugs (`dispatch.py:157` HIGH, every write turn dies after the model call is
   paid for; `agent.py:344`, `:253`, `:276`). Also: finer-grained switches (free-cloud-only,
   images-only, force-cheap-model) — only the master switch was built.
0d-i. **`PROVIDER_SPEND_ENABLED` needs a restart to take effect** — `Settings` is `frozen=True`
   and `get_settings` is `lru_cache`d, so the value is fixed at boot; the ledger's callable is the
   right seam but nothing behind it can move. To make it a real 3am switch: a flags row in
   Postgres, flippable from the Supabase console, read OUTSIDE the reserve transaction and cached
   a few seconds so it adds no lock to the hot path. Found by agy, `ef4106b` documents the truth.
0d-ii. Reviewer availability, 2026-09-03: codex is out of credits until ~Sep 7; the Fable
   reviewer hit a rate limit. agy was the only external reviewer that returned, so anything
   reviewed today has had ONE external pass, not two (U5: agy alone is never sufficient to merge).
0d-iii. Running the server's Postgres suite locally: `docker run -d --name hc-pgtest -e
   POSTGRES_PASSWORD=test -e POSTGRES_USER=agent -e POSTGRES_DB=agent_platform -p 55432:5432
   postgres:17-alpine`, then
   `AGENT_TEST_DATABASE_URL="postgresql+asyncpg://agent:test@127.0.0.1:55432/agent_platform"
   .venv/Scripts/python.exe -m pytest tests/test_postgres_regressions.py`. Disposable, off their
   compose stack and volume. ⚠️ Never point it at the deployment DB now: `global_daily_spend` is
   keyed by day alone, so a test run would consume that day's real ceiling.
0e. Decide what `X-Access-Key` is in a Release build: the client defaults it to a scheme env var
   and omits the header when empty, while the server refuses to boot live without one, so a
   shipped build would be locked out on day one.
1. User: re-test the three chat questions — expect real answers (words, not digits) instead of
   the "couldn't safely summarize" fallback. With a DeepSeek key configured any iPhone will
   answer, so an AI-capable device is only needed to test the fallback engine.
1b. User decides: the DeepSeek key ships extractable inside the IPA, and the only spend control
   on that path is a client-side rate limiter — a pulled key is unlimited spend on the shared
   account. The server-side ledger fixes nothing here, because the phone never talks to the
   server. Cheapest real fix is a thin proxy holding the key; second-cheapest is DeepSeek's own
   account cap, set low.
2. done 2026-09-04 — `fix/1.1-polish` merged into main: `16f280e` (Keychain installation id —
   `AgentBridge` no longer mints a fresh id per reinstall) plus the six review/docs commits
   `8151886`, `77f8273`, `74b0c6e`, `9ef78f1`, `041501a`, `c2413c1`. The 2026-09-02 note it
   replaces: `0ea1e55` + `266a476` merged into `feat/agent-profile-memory` (and main) with the
   cloud-engine port, so the prompt's self-description follows the engine
   (`HairChatPrompt.system(engine:)`: "stays on this iPhone" only when answering on-device).
3. User: final on-device/simulator UX pass of 1.1 before submitting build 5.
3b. done 2026-09-02 — Wren-identity prompt hardening + gate-contract test, full suite green
   at `266a476` (unit 180s, UITests 91s).
4. done 2026-09-02 — diff GitHub vs local, port surviving fixes onto 1.1 (`e2ad25a`).
5. done 2026-09-02 — codex+agy review round: codex P2 (dependency read inside unavailable
   branch) + agy icon-severity fixed in `d0def34`; agy's step-13 and DCE findings discarded
   with verified reasons (see commit message).
6. dropped — resubmission ASC lane for 1.0: app already approved and live.
