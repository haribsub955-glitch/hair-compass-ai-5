# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## ⚠️ Start with MOOSAWI_HANDOVER.md — this file predates the server

The app gained a **server-side agent** after this document was written, and most of what a change
now touches lives on the far side of that boundary. [MOOSAWI_HANDOVER.md](MOOSAWI_HANDOVER.md) is the
current entry point and is kept up to date. Everything below still describes the app itself
correctly; it simply says nothing about the server.

The facts that change decisions:

* **A second repository** (`agent-platform`, not published here) runs an HTTP agent the app talks
  to. It owns identity, subscriptions, token budgets, consent, the system prompt, the scope gate
  and the output safety screen. **The app renders; the server decides.** If you find yourself
  hardcoding a rule in Swift that the server already knows, that is the wrong side — it should
  arrive in the session response, which already carries `features`, `offer`, `tools` and `upgrade`.
* **Every request carries an `X-Access-Key` header**, and every endpoint except `/v1/session` also
  carries a `session_token`. The key is read from `HC_ACCESS_KEY` in the scheme environment and
  must never be committed.
* **`Service/Agent/AgentClient.swift` is wired to NO view.** `HairChatSheet` and
  `DeepAnalysisSheet` still use the older `HairChatService` / `CloudAnalysisService` path, which
  remains accurate. Connecting the agent to a screen is outstanding work, not a regression.
* **No Swift under `Service/Agent/` has ever been compiled** — it was written on a machine with no
  Xcode. Build before trusting any of it.
* **Attachments (photos) work server-side and are a paid feature.** The 3-day free period excludes
  them. Check `features` in the session response before showing an attachment button, and ask for
  photo consent before opening the picker.
* **An off-topic question returns a SUCCESSFUL turn with `iterations: 0`.** No model was called and
  nothing was spent. Render it as a normal assistant message, never an error. Likewise
  `served: false` means the safety screen stripped the answer — show the app's own deterministic
  summary instead.

## Overview

Hair Compass AI 5 is a native iOS app (SwiftUI + SwiftData, iOS 26.2 deployment target, Swift 5) for tracking hair/scalp health: daily check-ins, routines, medications/supplements, lab results, procedures, lifestyle triggers, progress photos, and a Home Screen widget. There is no README in the repo root; `docs/` only holds the GitHub Pages marketing/privacy/support site.

## Build, Run, Test

This is an Xcode project (no Swift Package Manager, no CocoaPods/SPM dependencies — Apple frameworks only). Use the workspace-less `.xcodeproj` with scheme **`Hair Compass AI 5`**.

```bash
# Build for simulator
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run the full test suite (unit + UI tests)
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run a single unit test (Swift Testing framework, not XCTest)
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Hair Compass AI 5Tests/Hair_Compass_AI_5Tests/calculatesInsightMetrics"
```

Note: the project name contains spaces — always quote paths/arguments. Pick a simulator that exists (`xcrun simctl list devices`); the deployment target is iOS 26.2, so the runtime must be new enough.

### Targets
- **Hair Compass AI 5** — the app.
- **Hair Compass CheckIn Widget** — WidgetKit extension (embedded app extension).
- **Hair Compass AI 5Tests** — unit tests, written with the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`), not XCTest.
- **Hair Compass AI 5UITests** — XCUITest UI tests.

## Architecture

### SwiftData is the source of truth
`Hair_Compass_AI_5App.swift` builds one `ModelContainer` over all `@Model` types defined in [Item.swift](Hair%20Compass%20AI%205/Data/Item.swift): `HairProfile`, `CheckInEntry`, `DailyObservation`, `RoutineTask`, `RoutineCompletionEntry`, `PhotoRecord`, `MedicationLog`, `MedicationDoseEntry`, `ProcedureEvent`, `LifestyleEntry`, `LabResultEntry`, `HairTriggerEvent`. The container is persisted on disk; if opening the store fails it deletes the `.store`/`.wal`/`.shm` files and recreates a fresh store (rather than falling back to in-memory) — relevant when changing the schema. Pure analytics helpers (`HairInsightCalculator`: averages, completion rate, streaks) also live in `Item.swift` and are what the unit tests cover.

### ContentView.swift is the entire UI (~11.6k lines)
[ContentView.swift](Hair%20Compass%20AI%205/App/ContentView.swift) holds the root `ContentView` plus ~55 `private struct ... : View` nested in the same file. Navigation is a custom `FloatingTabBar` over the `AppTab` enum with five tabs: `today` / `chart` / `photo` / `plan` / `you` (the enum keeps legacy aliases like `dashboard`, `checkIns`, `routine`, `profile` mapping onto these). Each tab is a top-level view here — `DashboardTab`, `CheckInsTab`, `RoutineTab`, `PhotoRecordsTab`, `ProfileTab`/`GuidanceTab`/`MedicationTab` — followed by their sheets, cards, library views, and chart views (`RoutineImpactChart`, `ChartEvidenceCard`, etc.). When adding UI, follow the existing pattern of a new `private struct ...: View` in this file unless extracting a feature.

### Services (`Services/`)
- **OpenAIServices.swift** — `OpenAIAnalysisService` calls the OpenAI `/v1/responses` endpoint (`gpt-4.1-mini`) with multi-angle photos for **record-keeping summaries only, explicitly not diagnosis** (preserve this framing in prompts). Also defines `PhotoFileStore` (singleton that saves/loads JPEGs to disk by path; `PhotoRecord` stores the path, not the image).
- **HealthInsightsStore.swift** — `@MainActor @Observable` HealthKit reader; surfaces daily metrics with an authorization state machine.
- **AffiliateCatalogService.swift** — `AffiliateCatalogStore` loads a bundled `AffiliateProducts.json` and can refresh from a (currently empty) remote URL; powers affiliate product rows.
- **ClinicianExportService.swift** — builds a plain-text clinical summary string from the SwiftData models for sharing/export.
- **AnalyticsService.swift** — local-only analytics; logs via `os.Logger` and stores event counts/properties in `UserDefaults`. No third-party analytics SDK.

### Monetization & gating
`Service/PurchaseService.swift` (`@MainActor @Observable`) wraps StoreKit 2: product IDs `com.harib.haircompass.pro.monthly2` / `.yearly2` (the "2" suffix is required — the un-suffixed IDs were burned by an old create-and-delete in App Store Connect), ASC subscription group "Premium". `hasPro` is the entitlement flag premium features check, injected via `@Environment(PurchaseService.self)`.

### Widget data sharing
The app writes a `HairCompassWidgetSnapshot` (Codable) into the shared App Group **`group.harib.Hair-Compass-AI-5`** under key `dashboardSnapshot`, then calls `WidgetCenter.shared.reloadTimelines(ofKind: "HairCompassCheckInWidget")`. The widget target ([HairCompassCheckInWidget.swift](Hair%20Compass%20CheckIn%20Widget/HairCompassCheckInWidget.swift)) reads the same App Group. The snapshot struct is duplicated on both sides — keep them in sync when changing fields.

### Design system
`DesignSystem/PremiumTheme.swift` — `PremiumTheme` enum of brand colors and gradients. Use these constants for any new UI rather than hardcoding colors.

## Conventions & gotchas

- **OpenAI key**: read from the `OPENAI_API_KEY` environment variable at launch (`seedOpenAIKeyIfProvided`) and stored in `UserDefaults` under `openAIAPIKey`. There is no key in the repo; set the env var in the scheme's run arguments for local testing.
- **Pre-submission placeholders**: `AppSubmissionLinks.privacyPolicyURL` and `.supportURL` in ContentView.swift, and `AffiliateCatalogStore.Configuration.remoteCatalogURLString`, are intentionally empty and must be filled before App Store submission (see `docs/README.md`).
- Tests use **Swift Testing**, not XCTest — write new unit tests with `@Test`/`#expect`.
