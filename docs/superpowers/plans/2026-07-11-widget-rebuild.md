# Widget Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the home-screen widget in the Clinical language (compass rings + streak + status), and make tapping it deep-link into the app's log flow.

**Architecture:** One implementation track (single agent — the duplicated snapshot struct makes splitting riskier than serializing). Spec: `docs/superpowers/specs/2026-07-11-widget-rebuild-design.md` — the spec IS the requirements; this plan adds file-level steps. Same global constraints as prior plans (no xcodebuild, no git, Clinical values, Swift Testing).

**Files:**
- Rewrite: `Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift`
- Modify: `Hair Compass AI 5/Service/WidgetBridge.swift` (snapshot v2 + builder)
- Modify: `Hair Compass AI 5/App/RootView.swift` (photos query, fingerprint bit, `.onOpenURL`, router injection)
- Modify: `Hair Compass AI 5/Feature/TodayView.swift` (consume router → `showLog`)
- Create: `Hair Compass AI 5/App/DeepLinkRouter.swift`
- Create: `Hair Compass AI 5Tests/WidgetSnapshotTests.swift`

**Consumes (frozen, already shipped):** `CompassScore(hasLoggedToday:medsDone:medsTotal:hasPhotoThisWeek:)` with `.score/.log/.care/.lens`; `HairAnalytics.shieldedStreak(entryDates:now:calendar:) -> (streak: Int, shieldsHeld: Int)`.

- [ ] **1. DeepLinkRouter + routing.** New file:

```swift
import Foundation

/// Routes widget/URL-scheme entries to in-app destinations. Consume-once flags: the
/// destination view resets them after presenting.
@MainActor
@Observable
final class DeepLinkRouter {
    var openLogRequested = false
}
```

RootView: `@State private var deepLinks = DeepLinkRouter()`, `.environment(deepLinks)` beside the other injections, and (placed with the other top-level modifiers):

```swift
.onOpenURL { url in
    guard url.scheme == "haircompass" else { return }
    tab = .today
    if url.host == "log", !showOnboarding { deepLinks.openLogRequested = true }
}
```

TodayView: `@Environment(DeepLinkRouter.self) private var deepLinks` and

```swift
.onChange(of: deepLinks.openLogRequested) { _, requested in
    if requested { showLog = true; deepLinks.openLogRequested = false }
}
.onAppear { if deepLinks.openLogRequested { showLog = true; deepLinks.openLogRequested = false } }
```

(The `.onAppear` covers the cold-start case where the URL arrives before TodayView exists.)

- [ ] **2. Snapshot v2 + builder.** In WidgetBridge.swift: replace the struct with the spec's v2 shape verbatim; `snapshotKey = "clinicalSnapshot.v2"`; builder signature becomes `build(entries:treatments:doses:photos:now:calendar:)`. Compute: `hasLoggedToday` (existing day check), `medsDone/medsTotal` (existing loop), `hasPhotoThisWeek` = any photo in the current `.weekOfYear`, then `let compass = CompassScore(...)` → `score/ringLog/ringCare/ringLens`; `shedLabel`/`scalpLabel` from the latest entry ("" when none); `(streakDays, shieldsHeld) = HairAnalytics.shieldedStreak(...)`; `dueTitles` unchanged. Update the placeholder to spec copy. Keep the doc comment about the duplicated struct.
- [ ] **3. RootView call site.** Add `@Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]`; pass `photos:` to the builder; append to `widgetFingerprint` a photo-week bit: `photos.first.map { "\($0.createdAt.timeIntervalSince1970)" } ?? "nophoto"`.
- [ ] **4. Widget rewrite.** Per spec §Widget design, exactly: `WidgetPalette` enum (hex constants in comments), small/medium/accessoryCircular/accessoryRectangular views, mini rings drawn with the `Circle().trim().stroke(style: StrokeStyle(lineWidth:, lineCap: .round)).rotationEffect(-90°)` recipe (static — no animation in widgets), dotted care track when `ringCare == nil`, `widgetURL(URL(string: "haircompass://log"))` on every family, `supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])`, kind string unchanged, timeline policy unchanged (hourly). Sync the duplicated struct + key EXACTLY with WidgetBridge.swift.
- [ ] **5. Tests.** `WidgetSnapshotTests.swift` (Swift Testing, `@testable import Hair_Compass_AI_5`, @MainActor where the builder requires it): the four cases in spec §Tests. Build model instances in-memory the way existing tests do (check `Hair_Compass_AI_5Tests.swift` for the in-memory `ModelContainer` pattern and reuse it).
- [ ] **6 (orchestrator).** Build BOTH schemes, run tests, install, `xcrun simctl openurl "iPhone 17 Pro" "haircompass://log"` + screenshot (log sheet must be up), verify the app-group plist contains `clinicalSnapshot.v2`, commit.
