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

## QUEUE

1. Mac verification rerun of `fix/1.1-polish` @ `d0def34` (post-review fixes) — running (log:
   `~/hc-polishtest.log` on the Mac).
2. User decision: merge `fix/1.1-polish` into `feat/agent-profile-memory` for the 1.1 build.
3. User: final on-device/simulator UX pass of 1.1 before submitting build 5.
4. done 2026-09-02 — diff GitHub vs local, port surviving fixes onto 1.1 (`e2ad25a`).
5. done 2026-09-02 — codex+agy review round: codex P2 (dependency read inside unavailable
   branch) + agy icon-severity fixed in `d0def34`; agy's step-13 and DCE findings discarded
   with verified reasons (see commit message).
6. dropped — resubmission ASC lane for 1.0: app already approved and live.
