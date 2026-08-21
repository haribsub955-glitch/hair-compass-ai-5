# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Hair Compass AI (bundle id `harib.Hair-Compass-AI-5`, display name "Hair Compass AI") is a native
iOS app (SwiftUI + SwiftData, iOS 26.2 deployment target) for documenting hair/scalp health:
daily check-ins, treatments, labs, triggers, procedures, standardized photos, body signals, and a
Home Screen widget. Framing is load-bearing everywhere: **record-keeping and education, never
diagnosis**. `docs/` is the public GitHub Pages site (live at https://haircompass-ai.com — Pages
serves the **default branch**, `rebuild/clinical-minimal`).

**This repository is PUBLIC.** No key, token, or secret may ever be committed. The DeepSeek API
key lives only in `Config/Secrets.local.xcconfig` (gitignored; see AI section).

## Build, Run, Test

One SPM dependency: `lottie-ios` (offline Lottie playback; all playback goes through
`Design/ClinicalLottie.swift`). Everything else is Apple frameworks — do not add dependencies
casually. Project name contains spaces — always quote. Use a simulator that exists; the
iPhone 17 family sims carry iOS 26.3 and work (16-family sims are on iOS 18 and do not).

```bash
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test  -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Targets: **Hair Compass AI 5** (app) · **Hair Compass CheckIn Widget** (WidgetKit) ·
**Hair Compass AI 5Tests** (unit — **Swift Testing**: `@Test`/`#expect`, not XCTest) ·
**Hair Compass AI 5UITests** (XCUITest, launch-flow only).

DEBUG-only QA flags (launch arguments): `HC_SEED_DEMO` (≈120 days of data), `HC_NORITUAL`,
`HC_TAB <today|trends|care|labs|photos>`, `HC_TIER <free|taster|pro>`, `HC_AI_STATUS <case>`,
`HC_CLOUD_CONSENT <granted|denied>`, `HC_AI_CLOUD_OFF`; env `HC_AI_KEY` / `HC_AI_BASE_URL` /
`HC_AI_MODEL`. Full list: `grep -rh 'arguments.contains("' --include=*.swift`.

## Architecture

- `App/` — `HairCompassApp` (ModelContainer over the SwiftData models), `RootView` (tab shell,
  launch ritual, entitlement resolution), deep links, App Intents.
- `Feature/` — one file per surface (TodayView, TrendsView, CompareView, LabsView, PhotosView,
  CareView, BaselineFlow, Onboarding/, paywall pieces, sheets). UI follows the **Clinical**
  design language in `Design/Clinical.swift` — use its tokens, never hardcode colors; the app
  deliberately strips card chrome (don't box everything).
- `Service/` — persistence repositories, HealthKit, notifications, purchases, export/PDF,
  photo store, **AI services** (below).
- `Model/` — SwiftData `@Model`s (`Models.swift`), deterministic analytics (`Analytics.swift`,
  `ChartMetric`, `CompassScore`…), `AIContextBuilder`, `AppInfo` (legal URLs baked into the
  binary), content libraries.

### AI: one engine decision, one output gate

`AIEngine.resolve` (Service/CloudAI.swift) decides per request, shared by all three surfaces
(Ask Wren chat, Deep analysis, ingredient summaries):

1. **Cloud (DeepSeek)** — when configured AND the person granted `CloudAIConsent`. OpenAI-
   compatible `/chat/completions`, non-streaming, via `CloudAI.reply`. Key path:
   `Config/Secrets.local.xcconfig` (gitignored) → `Config/AI.xcconfig` → `HC_DEEPSEEK_API_KEY`
   build setting → Info.plist `HCDeepSeekAPIKey` → `CloudAIConfig.current`. A clone without the
   secrets file builds fine and simply has no cloud.
2. **On-device (Apple Intelligence / FoundationModels)** — the no-consent path and the offline
   fallback (`OnDeviceAvailability` classifies why it can't run).
3. Daily insights (`InsightEngine`) never use the cloud: on-device model over deterministic
   facts, else the rule-based paragraph.

Consent is a real tri-state (`CloudAIConsent`: undecided/granted/denied) — **nothing is ever
sent before a grant**; `CloudAIConsentCard` asks in place, and the Baseline screen keeps the
reversible toggle. Every generated reply from either engine passes the deterministic
`AIOutputValidator` gate before display — validate against the exact JSON/facts string the model
saw. `AIContext` (Model/AIContextBuilder.swift) is the canonical, versioned, identifier-free
payload: no name, no photos, stable `.sortedKeys` encoding.

### Monetization

`Service/PurchaseService.swift` (StoreKit 2; products `com.harib.haircompass.pro.monthly` /
`.yearly`, group `21442176`) + `Feature/Entitlements.swift` (`ProFeature` — the policy table),
`ProGate`, `TodayGating`, `HistoryAccess`. Free tier = check-in only (log forever, see only
today); 3-day local taster; everything else Pro. `ProAvailability` owns what the paywalls
disclose about the two AI features (nothing, when cloud is configured). Don't widen the free
tier, don't cap check-ins, export stays free — these are owner rulings.

### Widget

App writes a snapshot through `Service/WidgetBridge.swift` into App Group
`group.harib.Hair-Compass-AI-5`; the widget reads the same group. The snapshot must never leak
Pro-locked history to a free tier.

## Conventions & gotchas

- Swift Testing for unit tests; UI tests don't cover AI flows.
- A stale SwiftData store from an older schema crashes at launch in the sim — delete
  `HairCompassAI5.store*` under the sim container (both app sandbox and App Group).
- The shell is zsh: quote everything (paths contain spaces), and `for x in $VAR` does not
  word-split.
- `APP_STORE_SUBMISSION.md` is the submission runbook; `SubmissionReadinessTests` are the
  tripwires. App Privacy in App Store Connect must declare Health data (cloud AI) — see the
  runbook.
- Docs edits go live only when merged to `rebuild/clinical-minimal` (Pages source).
