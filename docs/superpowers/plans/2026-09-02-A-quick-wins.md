# Sub-project A: Quick Wins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every "not enough data" state on the Trends tab with one shared shaded chart placeholder that says when the chart opens, and add an "Erase everything and start over" action to Profile that returns the app to onboarding without restarting the 3-day access window.

**Architecture:** One new SwiftUI view, `ChartPlaceholder`, with a pure `Copy` function for its label, adopted by four existing sites (Trends empty state, JourneyChart, CompareView, BodySignalsDashboard). One new service, `EraseAndStartOver`, that wipes SwiftData, photos, defaults, notifications and the widget snapshot, then re-seeds a fresh profile; `BaselineFlow` asks for it, `RootView` performs it after the sheet closes and shows onboarding.

**Tech Stack:** SwiftUI, Swift Charts, SwiftData, Swift Testing (`@Test`/`#expect`), XCUITest for the one UI test. Xcode file-system-synchronized groups: new files under the app or test roots compile without project edits.

**Spec:** `docs/superpowers/specs/2026-09-02-first-run-plan-tour-refinement-design.md` (section A)

## Global Constraints

- Framing rule: record-keeping and education, never diagnosis. No copy tells the person to start, stop or change anything.
- No palette change, no new typefaces, no dark mode, no new dependencies.
- No data threshold changes: 2 daily logs (Trends rows, journey), 7 days (Compare chart), 8 paired days (association), 2 readings (body signals).
- The 3-day `AccessWindow` (Keychain) must never restart; erase must not touch it.
- Unit tests are Swift Testing (`@Test`, `#expect`), never XCTest. UI tests are XCTest.
- Every command below runs from the repo root `"/Users/haribazri/Hair Compass AI 5"`. The project name contains spaces: quote every path.
- Simulator: `platform=iOS Simulator,name=iPhone 17 Pro`. UI tests: always `-parallel-testing-enabled NO`.
- Commit messages end with the two trailer lines shown in each commit step.

**Test command shorthand used below** (define once in your shell):

```bash
cd "/Users/haribazri/Hair Compass AI 5"
DD="/private/tmp/claude-501/-Users-haribazri-Hair-Compass-AI-5/ff0a543b-cd29-4e99-83c4-0d3dc9b8f4cb/scratchpad/DerivedData-port"
utest() { xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5Tests/$1" 2>&1 | grep -E 'error:|✘|✔|Test run with|TEST (SUCCEEDED|FAILED)|BUILD FAILED' | tail -20; }
```

After any xcodebuild run, discard its rewrite of the shared scheme file before committing: `git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"`.

---

## File structure

| File | Responsibility |
|---|---|
| Create `Hair Compass AI 5/Design/ChartPlaceholder.swift` | The shaded ghost chart, its label pill, and the pure label copy |
| Create `Hair Compass AI 5Tests/ChartPlaceholderTests.swift` | Label copy per unit, clamping, singular |
| Modify `Hair Compass AI 5/Feature/TrendsView.swift:406-424` | `emptyState` uses the placeholder |
| Modify `Hair Compass AI 5/Feature/JourneyChart.swift:56, 420-432` | thin-data placeholder uses the component at the live chart's height |
| Modify `Hair Compass AI 5/Feature/CompareView.swift:205-320, 366-380` | locked chart and association read use the component |
| Modify `Hair Compass AI 5/Feature/BodySignalsDashboard.swift:240-275` | answered-but-empty state shows the placeholder above the existing prompt |
| Delete `Hair Compass AI 5/Assets.xcassets/trends-journey-empty.imageset/` | only used by the old Trends empty state |
| Modify `Hair Compass AI 5/Service/PhotoStore.swift:19-27` | directory override for tests, `deleteAll()` |
| Create `Hair Compass AI 5/Service/EraseAndStartOver.swift` | the wipe, injectable side effects |
| Create `Hair Compass AI 5Tests/EraseAndStartOverTests.swift` | wipe proves every model empty, fresh profile, defaults cleared, photos gone, access window untouched |
| Modify `Hair Compass AI 5/Feature/BaselineFlow.swift:8-16, 118-166, 310` | the destructive row, confirmation alert, "Export first" scroll |
| Modify `Hair Compass AI 5/App/RootView.swift:60, 84, 396-406` | performs the erase after the sheet closes, shows onboarding |
| Modify `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift` | `testEraseReturnsToOnboarding` |

---

### Task 1: `ChartPlaceholder` component and its copy

**Files:**
- Create: `Hair Compass AI 5/Design/ChartPlaceholder.swift`
- Test: `Hair Compass AI 5Tests/ChartPlaceholderTests.swift`

**Interfaces:**
- Produces:
  - `enum ChartPlaceholderUnit { case dailyLogs, days, pairedDays, readings }`
  - `enum ChartPlaceholderCopy { static func label(required: Int, have: Int, unit: ChartPlaceholderUnit) -> (primary: String, progress: String) }`
  - `struct ChartPlaceholder: View { init(required: Int, have: Int, unit: ChartPlaceholderUnit, height: CGFloat = 132) }`
  - `struct ChartPlaceholderPill: View { init(required: Int, have: Int, unit: ChartPlaceholderUnit) }`

- [ ] **Step 1: Write the failing tests**

Create `Hair Compass AI 5Tests/ChartPlaceholderTests.swift`:

```swift
//
//  ChartPlaceholderTests.swift
//  Hair Compass AI 5Tests
//
//  The one line every "not yet" chart shows must say the section's own rule, honestly and in
//  the same words everywhere: "Opens after N <unit>" and "k of N".
//

import Testing
@testable import Hair_Compass_AI_5

struct ChartPlaceholderTests {

    @Test func dailyLogsCopy() {
        let c = ChartPlaceholderCopy.label(required: 2, have: 1, unit: .dailyLogs)
        #expect(c.primary == "Opens after 2 daily logs")
        #expect(c.progress == "1 of 2")
    }

    @Test func daysCopy() {
        let c = ChartPlaceholderCopy.label(required: 7, have: 2, unit: .days)
        #expect(c.primary == "Opens after 7 days")
        #expect(c.progress == "2 of 7")
    }

    @Test func pairedDaysCopy() {
        let c = ChartPlaceholderCopy.label(required: 8, have: 0, unit: .pairedDays)
        #expect(c.primary == "Opens after 8 paired days")
        #expect(c.progress == "0 of 8")
    }

    @Test func readingsCopy() {
        let c = ChartPlaceholderCopy.label(required: 2, have: 1, unit: .readings)
        #expect(c.primary == "Opens after 2 readings")
        #expect(c.progress == "1 of 2")
    }

    /// Progress can never read "3 of 2" — a site that passes more than it needs is clamped,
    /// and a negative count is treated as zero.
    @Test func progressIsClamped() {
        #expect(ChartPlaceholderCopy.label(required: 2, have: 5, unit: .dailyLogs).progress == "2 of 2")
        #expect(ChartPlaceholderCopy.label(required: 2, have: -1, unit: .dailyLogs).progress == "0 of 2")
    }

    /// Not used by any site today, but the function must never print "1 daily logs".
    @Test func singularUnits() {
        #expect(ChartPlaceholderCopy.label(required: 1, have: 0, unit: .dailyLogs).primary == "Opens after 1 daily log")
        #expect(ChartPlaceholderCopy.label(required: 1, have: 0, unit: .days).primary == "Opens after 1 day")
        #expect(ChartPlaceholderCopy.label(required: 1, have: 0, unit: .pairedDays).primary == "Opens after 1 paired day")
        #expect(ChartPlaceholderCopy.label(required: 1, have: 0, unit: .readings).primary == "Opens after 1 reading")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `utest ChartPlaceholderTests`
Expected: build failure mentioning `ChartPlaceholderCopy` cannot be found in scope.

- [ ] **Step 3: Write the component**

Create `Hair Compass AI 5/Design/ChartPlaceholder.swift`:

```swift
//
//  ChartPlaceholder.swift
//  Hair Compass AI 5
//
//  The one "not open yet" state for every chart on Trends. A soft illustrative curve at low
//  opacity — a chart that hasn't opened, never an empty box — with one pill that states the
//  section's own rule ("Opens after 7 days") and the honest progress toward it ("2 of 7").
//  Every site passes its own threshold; no threshold lives here.
//

import Charts
import SwiftUI

enum ChartPlaceholderUnit {
    case dailyLogs, days, pairedDays, readings

    fileprivate func noun(_ count: Int) -> String {
        switch self {
        case .dailyLogs: return count == 1 ? "daily log" : "daily logs"
        case .days: return count == 1 ? "day" : "days"
        case .pairedDays: return count == 1 ? "paired day" : "paired days"
        case .readings: return count == 1 ? "reading" : "readings"
        }
    }
}

/// Pure copy, so the words every chart shows are testable without rendering anything.
enum ChartPlaceholderCopy {
    static func label(required: Int, have: Int, unit: ChartPlaceholderUnit) -> (primary: String, progress: String) {
        let clamped = min(max(have, 0), required)
        return ("Opens after \(required) \(unit.noun(required))", "\(clamped) of \(required)")
    }
}

/// The label pill on its own — for sites that have no chart area to shade (the association
/// read under a Compare chart) but must still speak in the same words.
struct ChartPlaceholderPill: View {
    let required: Int
    let have: Int
    let unit: ChartPlaceholderUnit

    var body: some View {
        let copy = ChartPlaceholderCopy.label(required: required, have: have, unit: unit)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(Clinical.caption(13)).foregroundStyle(Clinical.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.primary)
                    .font(Clinical.caption(14)).foregroundStyle(Clinical.ink)
                Text(copy.progress)
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 260)
        .background(Clinical.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
        .shadow(color: Clinical.cardShadow, radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(copy.primary). \(copy.progress).")
    }
}

struct ChartPlaceholder: View {
    let required: Int
    let have: Int
    let unit: ChartPlaceholderUnit
    var height: CGFloat = 132

    /// A gentle rise with one dip — illustrative only, never mistaken for data (no axes, no
    /// numbers, and the pill says so).
    private static let ghost: [Double] = [
        0.30, 0.34, 0.31, 0.38, 0.42, 0.40, 0.47, 0.51, 0.48, 0.56, 0.60, 0.58, 0.64, 0.68,
    ]

    var body: some View {
        let copy = ChartPlaceholderCopy.label(required: required, have: have, unit: unit)
        ZStack {
            Chart {
                ForEach(Array(Self.ghost.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("Day", i), y: .value("Level", v))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(colors: [Clinical.accentSoft, Clinical.accentSoft.opacity(0)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    LineMark(x: .value("Day", i), y: .value("Level", v))
                        .interpolationMethod(.monotone)
                        .lineStyle(.init(lineWidth: 2))
                        .foregroundStyle(Clinical.hairline)
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .opacity(0.35)
            .accessibilityHidden(true)

            ChartPlaceholderPill(required: required, have: have, unit: unit)
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chart not open yet. \(copy.primary). \(copy.progress).")
    }
}

#Preview {
    VStack(spacing: 20) {
        ChartPlaceholder(required: 2, have: 1, unit: .dailyLogs)
        ChartPlaceholder(required: 7, have: 3, unit: .days, height: 170)
        ChartPlaceholderPill(required: 8, have: 7, unit: .pairedDays)
    }
    .padding(20)
    .background(Clinical.canvas)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `utest ChartPlaceholderTests`
Expected: `✔ Test run with 6 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Design/ChartPlaceholder.swift" "Hair Compass AI 5Tests/ChartPlaceholderTests.swift"
git commit -m "$(cat <<'EOF'
ChartPlaceholder: one shaded 'opens after N' state for every chart

A ghost curve at low opacity with one pill that states the section's own
rule and the honest progress toward it. Pure copy function, unit-tested;
no threshold lives in the component.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
EOF
)"
```

---

### Task 2: Trends empty state and the journey chart adopt the placeholder

**Files:**
- Modify: `Hair Compass AI 5/Feature/TrendsView.swift:406-424` (`emptyState`)
- Modify: `Hair Compass AI 5/Feature/JourneyChart.swift:56-57` (call site) and `:420-432` (`thinDataPlaceholder`)
- Delete: `Hair Compass AI 5/Assets.xcassets/trends-journey-empty.imageset/`

**Interfaces:**
- Consumes: `ChartPlaceholder(required:have:unit:height:)` from Task 1.

- [ ] **Step 1: Replace `emptyState` in TrendsView**

In `Hair Compass AI 5/Feature/TrendsView.swift`, replace the whole `private var emptyState: some View { ... }` (the block that renders `Image("trends-journey-empty")`, the "Not enough data" eyebrow and the "Trends appear after two or more daily logs in this window." text) with:

```swift
    /// The scalp and adherence ledger rows need two daily logs in the window. Until then the
    /// section is a chart that hasn't opened — the same shaded placeholder every Trends chart
    /// uses — with the rule and the progress toward it in one pill.
    private var emptyState: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Scalp and adherence")
                ChartPlaceholder(required: 2, have: windowEntries.count, unit: .dailyLogs)
            }
        }
    }
```

- [ ] **Step 2: Replace the journey chart's thin-data placeholder**

In `Hair Compass AI 5/Feature/JourneyChart.swift`, replace the whole `private var thinDataPlaceholder: some View { ... }` (the block with the `chart.xyaxis.line` symbol, "Keep logging to see your journey" and "Two or more daily logs in this window unlock the timeline.") with:

```swift
    // MARK: Thin-data placeholder

    /// Same height as the live shed chart (`.frame(height: 180)` below), so nothing jumps the
    /// moment the second log lands and the real timeline takes its place.
    private var thinDataPlaceholder: some View {
        ChartPlaceholder(required: 2, have: data.shedPoints.count, unit: .dailyLogs, height: 180)
    }
```

The call site at the top of `body` (`if data.shedPoints.count < 2 { thinDataPlaceholder } else { ... }`) does not change.

- [ ] **Step 3: Remove the now-unused asset**

```bash
grep -rn 'trends-journey-empty' --include='*.swift' "Hair Compass AI 5" "Hair Compass AI 5Tests" "Hair Compass CheckIn Widget"
```

Expected: no output. Then:

```bash
git rm -r -q "Hair Compass AI 5/Assets.xcassets/trends-journey-empty.imageset"
```

- [ ] **Step 4: Build and run the Trends-related suites**

Run: `utest BrandArtCoverageTests && utest TrajectorySummaryTests`
Expected: both `TEST SUCCEEDED`, no `error:` lines. (`BrandArtCoverageTests` proves no `BrandArt` constant lost its renderer; the deleted asset was never a `BrandArt` constant.)

- [ ] **Step 5: See it in the simulator**

```bash
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -quiet 2>&1 | grep -E 'error:' ; \
xcrun simctl terminate booted harib.Hair-Compass-AI-5 2>/dev/null; \
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/Hair Compass AI 5.app" && \
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_NORITUAL HC_TAB trends && sleep 3 && \
xcrun simctl io booted screenshot "$DD/../trends-placeholder.png"
```

Open `trends-placeholder.png` (Read tool). Expected: with the existing one-day record, the journey area shows the shaded curve with "Opens after 2 daily logs · 1 of 2", and the scalp-and-adherence card shows the same. If the simulator has more than one log, seed a fresh state first: `xcrun simctl uninstall booted harib.Hair-Compass-AI-5` then reinstall and complete onboarding by hand, or accept the screenshot of whichever card is still locked.

- [ ] **Step 6: Commit**

```bash
git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"
git add "Hair Compass AI 5/Feature/TrendsView.swift" "Hair Compass AI 5/Feature/JourneyChart.swift"
git commit -m "$(cat <<'EOF'
Trends: the journey and the ledger open with the shared placeholder

Both two-log gates now show the shaded chart and its 'Opens after 2 daily
logs · k of 2' pill instead of an illustration and a sentence. The
journey placeholder matches the live chart's height so nothing jumps.
The trends-journey-empty asset had no other user and is removed.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
EOF
)"
```

---

### Task 3: CompareView's locked chart and association read adopt the placeholder

**Files:**
- Modify: `Hair Compass AI 5/Feature/CompareView.swift:205-320` (`previewLocked`, `lockChip`, `sampleSignal`, `sampleOverlay`) and `:366-380` (`readCard`)

**Interfaces:**
- Consumes: `ChartPlaceholder`, `ChartPlaceholderPill` from Task 1; `ChartMath.association` returning `.insufficient(need:)` (existing, `Model/ChartMetric.swift:59`).

- [ ] **Step 1: Find the exact call site of `previewLocked`**

```bash
grep -n 'previewLocked\|lockChip\|sampleSignal\|sampleOverlay' "Hair Compass AI 5/Feature/CompareView.swift"
```

Expected: one call `previewLocked(daysLogged: overlapDays)` inside `chartCard`'s `if !ready { ... }`, the two static arrays, and the two function definitions.

- [ ] **Step 2: Replace the locked preview**

Replace the whole `private func previewLocked(daysLogged: Int) -> some View { ... }` **and** the whole `private func lockChip(daysLogged: Int) -> some View { ... }` with:

```swift
    /// Honest "not enough data yet" state: the shared shaded placeholder at the real chart's
    /// height, so nothing visually jumps the moment the comparison crosses the 7-day threshold.
    private func previewLocked(daysLogged: Int) -> some View {
        ChartPlaceholder(required: Self.readyThreshold, have: daysLogged, unit: .days, height: 170)
    }
```

Then delete the two static arrays `sampleSignal` and `sampleOverlay` and their doc comments. Confirm nothing else references them:

```bash
grep -n 'sampleSignal\|sampleOverlay' "Hair Compass AI 5/Feature/CompareView.swift"
```

Expected: no output.

- [ ] **Step 3: The association read speaks the same words when short of pairs**

In `readCard`, replace:

```swift
                    Text(ChartMath.phrasing(assoc, hairTitle: hair.title, lifestyleTitle: overlay.title, lagDays: lag.days))
                        .font(Clinical.caption(14)).foregroundStyle(Clinical.ink)
```

with:

```swift
                    if case .insufficient(let need) = assoc {
                        // Same pill as every locked chart: the rule, and the honest progress.
                        ChartPlaceholderPill(required: need, have: paired.hair.count, unit: .pairedDays)
                    } else {
                        Text(ChartMath.phrasing(assoc, hairTitle: hair.title, lifestyleTitle: overlay.title, lagDays: lag.days))
                            .font(Clinical.caption(14)).foregroundStyle(Clinical.ink)
                    }
```

`ChartMath.phrasing`'s `.insufficient` sentence stays in `ChartMetric.swift` (other callers and tests may use it); Compare simply no longer renders it.

- [ ] **Step 4: Build and run the Compare suites**

Run: `utest CompareAssociationTests`
Expected: `TEST SUCCEEDED`, no `error:` lines.

- [ ] **Step 5: See it in the simulator**

```bash
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -quiet 2>&1 | grep -E 'error:' ; \
xcrun simctl terminate booted harib.Hair-Compass-AI-5 2>/dev/null; \
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/Hair Compass AI 5.app"; \
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_NORITUAL HC_TAB trends && sleep 3
```

Open Compare from Trends (the compare row on the Trends screen; tap it with `~/homebrew/bin/cliclick` after locating it in a screenshot, or navigate by hand) and screenshot. Expected: the locked chart shows the shaded curve with "Opens after 7 days · 1 of 7"; below it the read card shows the pill "Opens after 8 paired days · 1 of 8".

- [ ] **Step 6: Commit**

```bash
git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"
git add "Hair Compass AI 5/Feature/CompareView.swift"
git commit -m "$(cat <<'EOF'
Compare: the locked chart and the short-of-pairs read use the shared placeholder

Compare had its own sample chart and lock chip; both move onto
ChartPlaceholder so every locked chart in the app says the same words.
The association read shows the pill ('Opens after 8 paired days') while
short of pairs instead of a sentence.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
EOF
)"
```

---

### Task 4: Body signals show the placeholder when Health has answered but nothing is drawable

**Files:**
- Modify: `Hair Compass AI 5/Feature/BodySignalsDashboard.swift:250-275` (`signalContent`)

**Interfaces:**
- Consumes: `ChartPlaceholder` from Task 1; existing `seriesCache: [BodySignal: [MetricPoint]]` and `healthKit.authorization` with case `.requestedQueryable` (`Service/SignalSource.swift:22`).

Note on scope: a metric with fewer than 2 readings is deliberately not rendered as its own row (the dashboard's "no empty boxes" rule). The placeholder appears once, for the whole card, in the one state where Health has been answered and no metric can draw yet.

- [ ] **Step 1: Add the placeholder above the existing answered-but-empty prompt**

In `signalContent`, replace:

```swift
            case .requestedQueryable:
                requestedEmptyPrompt
```

with:

```swift
            case .requestedQueryable:
                // Health has answered and nothing can draw yet: the same shaded placeholder as
                // every other Trends chart, with the most-populated metric's progress, above the
                // existing explanation of why there is no in-app retry for a denied request.
                VStack(alignment: .leading, spacing: 12) {
                    ChartPlaceholder(
                        required: 2,
                        have: seriesCache.values.map(\.count).max() ?? 0,
                        unit: .readings,
                        height: 110
                    )
                    requestedEmptyPrompt
                }
```

- [ ] **Step 2: Build and run the body-signals suite**

Run: `utest BodySignalsTests`
Expected: `TEST SUCCEEDED`, no `error:` lines.

- [ ] **Step 3: Commit**

```bash
git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"
git add "Hair Compass AI 5/Feature/BodySignalsDashboard.swift"
git commit -m "$(cat <<'EOF'
Body signals: answered-but-empty shows the shared chart placeholder

Once Health has been answered and no metric has two readings, the card
shows the shaded placeholder with 'Opens after 2 readings' above the
existing prompt, instead of prose alone. Rows still appear only when a
metric can draw.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
EOF
)"
```

---

### Task 5: `EraseAndStartOver` service

**Files:**
- Modify: `Hair Compass AI 5/Service/PhotoStore.swift:6-27` (directory override, `deleteAll()`)
- Create: `Hair Compass AI 5/Service/EraseAndStartOver.swift`
- Test: `Hair Compass AI 5Tests/EraseAndStartOverTests.swift`

**Interfaces:**
- Consumes: the 13 `@Model` types listed in `App/HairCompassApp.swift:32-35`; `Seed.bootstrapIfNeeded(context:profiles:)` (`Model/Seed.swift:6`); `WidgetSnapshot.placeholder` and `WidgetBridge.write(_:)` (`Service/WidgetBridge.swift:42, 89`); `CloudAIConsent.reset(in:)` (`Service/CloudAI.swift:105`); `AccessWindow(store:now:)` and `AccessAnchorStoring` (`Service/AccessWindow.swift:8-9, 27`).
- Produces:
  - `PhotoStore.init(directoryOverride: URL? = nil)` and `func deleteAll()`
  - `enum EraseAndStartOver { @MainActor static func perform(context: ModelContext, defaults: UserDefaults = .standard, defaultsDomain: String = Bundle.main.bundleIdentifier ?? "harib.Hair-Compass-AI-5", photoStore: PhotoStore = PhotoStore(), cancelNotifications: () async -> Void = { ... }, writeWidget: (WidgetSnapshot) -> Void = WidgetBridge.write) async throws }`

- [ ] **Step 1: Write the failing test**

Create `Hair Compass AI 5Tests/EraseAndStartOverTests.swift`:

```swift
//
//  EraseAndStartOverTests.swift
//  Hair Compass AI 5Tests
//
//  "Erase everything and start over" must leave nothing of the record behind — every model,
//  every photo file, every preference — and must leave exactly two things alone: the 3-day
//  access window (1.1 rule: nothing restarts it) and the subscription (Apple's, not ours).
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct EraseAndStartOverTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self, MissedDoseRecord.self,
            SideEffectLog.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self,
            ProcedureAppointment.self, ProgressCheckIn.self, AgentMemory.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// An in-memory access-window store that counts writes, so the test can prove the erase
    /// never wrote a new anchor.
    private final class MemoryAnchorStore: AccessAnchorStoring {
        var anchor: Date?
        var saveCount = 0
        init(anchor: Date?) { self.anchor = anchor }
        func loadAnchor() -> Date? { anchor }
        func saveAnchor(_ date: Date) { anchor = date; saveCount += 1 }
    }

    @Test func eraseLeavesAFreshProfileAndNothingElse() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let onboarded = Profile()
        onboarded.hasOnboarded = true
        context.insert(onboarded)
        context.insert(TriggerEvent())
        context.insert(TreatmentDose())
        try context.save()

        let suite = "EraseAndStartOverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "hasSeenTutorial")
        CloudAIConsent.record(true, in: defaults)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("erase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("a.jpg"))
        let photos = PhotoStore(directoryOverride: dir)

        let anchorDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = MemoryAnchorStore(anchor: anchorDate)
        _ = AccessWindow(store: store)   // reads the anchor; must not be touched by the erase

        var cancelled = false
        var written: WidgetSnapshot?
        try await EraseAndStartOver.perform(
            context: context,
            defaults: defaults,
            defaultsDomain: suite,
            photoStore: photos,
            cancelNotifications: { cancelled = true },
            writeWidget: { written = $0 }
        )

        // Exactly one fresh, un-onboarded profile; every other table empty.
        let profiles = try context.fetch(FetchDescriptor<Profile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.hasOnboarded == false)
        #expect(try context.fetch(FetchDescriptor<TriggerEvent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).isEmpty)

        // Preferences gone, consent back to undecided.
        #expect(defaults.object(forKey: "hasSeenTutorial") == nil)
        #expect(CloudAIConsent.isDecided(defaults) == false)

        // Photos gone, side effects fired.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        #expect(cancelled)
        #expect(written == .placeholder)

        // The access window is untouched: same anchor, no new write.
        #expect(store.anchor == anchorDate)
        #expect(store.saveCount == 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `utest EraseAndStartOverTests`
Expected: build failure: `PhotoStore` has no initializer `init(directoryOverride:)`, `EraseAndStartOver` not found.

- [ ] **Step 3: Give `PhotoStore` a directory override and `deleteAll()`**

In `Hair Compass AI 5/Service/PhotoStore.swift`, replace:

```swift
    nonisolated private var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ScalpPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
```

with:

```swift
    /// Tests point the store at a temporary folder; the app never passes this.
    nonisolated private let directoryOverride: URL?

    init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
    }

    nonisolated private var directory: URL {
        let dir: URL
        if let directoryOverride {
            dir = directoryOverride
        } else {
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            dir = base.appendingPathComponent("ScalpPhotos", isDirectory: true)
        }
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Removes every stored photo file and clears the thumbnail cache. Only "Erase everything
    /// and start over" calls this.
    func deleteAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files { try? FileManager.default.removeItem(at: url) }
        cache.removeAllObjects()
    }
```

If `PhotoStore` already declares an explicit `init()`, merge: keep one `init(directoryOverride: URL? = nil)` and move any existing init body into it. Check with `grep -n 'init' "Hair Compass AI 5/Service/PhotoStore.swift"`.

- [ ] **Step 4: Write the service**

Create `Hair Compass AI 5/Service/EraseAndStartOver.swift`:

```swift
//
//  EraseAndStartOver.swift
//  Hair Compass AI 5
//
//  "Erase everything and start over": every record, photo and preference on this iPhone goes,
//  a fresh un-onboarded profile is seeded, and the app returns to onboarding. Two things are
//  deliberately left alone — the 3-day AccessWindow in the Keychain (1.1 rule: nothing restarts
//  it) and the StoreKit entitlement (Apple's, not ours). Side effects are parameters so the
//  wipe is provable in a unit test without touching the device.
//

import Foundation
import SwiftData
import UserNotifications

enum EraseAndStartOver {

    @MainActor
    static func perform(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        defaultsDomain: String = Bundle.main.bundleIdentifier ?? "harib.Hair-Compass-AI-5",
        photoStore: PhotoStore = PhotoStore(),
        cancelNotifications: () async -> Void = {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        },
        writeWidget: (WidgetSnapshot) -> Void = WidgetBridge.write
    ) async throws {
        // 1. The record. One delete per model type: relationships cascade, but naming every
        //    type here is what makes "everything" true when a new model is added later.
        try context.delete(model: TreatmentDose.self)
        try context.delete(model: MissedDoseRecord.self)
        try context.delete(model: SideEffectLog.self)
        try context.delete(model: Treatment.self)
        try context.delete(model: DailyEntry.self)
        try context.delete(model: LabResult.self)
        try context.delete(model: PhotoRecord.self)
        try context.delete(model: HealthSnapshot.self)
        try context.delete(model: TriggerEvent.self)
        try context.delete(model: ProcedureAppointment.self)
        try context.delete(model: ProgressCheckIn.self)
        try context.delete(model: AgentMemory.self)
        try context.delete(model: Profile.self)
        try context.save()

        // 2. Photo files.
        photoStore.deleteAll()

        // 3. Every preference — tutorial, reminders, consent, budget, dismissals. The access
        //    window is in the Keychain, not here, so it survives by construction.
        defaults.removePersistentDomain(forName: defaultsDomain)
        CloudAIConsent.reset(in: defaults)

        // 4. Nothing scheduled may fire for a record that no longer exists.
        await cancelNotifications()

        // 5. The Home Screen widget must not keep showing the erased record.
        writeWidget(.placeholder)

        // 6. A fresh profile, un-onboarded, exactly as a first install gets.
        Seed.bootstrapIfNeeded(context: context, profiles: [])
        try context.save()
    }
}
```

Check the schema list against `App/HairCompassApp.swift:32-35`:

```bash
sed -n '30,36p' "Hair Compass AI 5/App/HairCompassApp.swift"
```

Every type in that list must appear in a `context.delete(model:)` line above. If the app list has a type this file lacks, add it.

- [ ] **Step 5: Run the test to verify it passes**

Run: `utest EraseAndStartOverTests`
Expected: `✔ Test run with 1 test in 1 suite passed`.

- [ ] **Step 6: Run the photo and backup suites to prove the store change is inert**

Run: `utest BackupServiceTests && utest PhotoCompareMismatchTests`
Expected: both `TEST SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"
git add "Hair Compass AI 5/Service/PhotoStore.swift" "Hair Compass AI 5/Service/EraseAndStartOver.swift" "Hair Compass AI 5Tests/EraseAndStartOverTests.swift"
git commit -m "$(cat <<'EOF'
EraseAndStartOver: the wipe, provable without the device

Deletes every model type by name, every photo file, the whole defaults
domain and the cloud consent, cancels pending notifications, blanks the
widget, and seeds a fresh un-onboarded profile. The access window lives in
the Keychain and is never touched — the test pins that with a counting
store. PhotoStore gains a directory override for tests and deleteAll().

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
EOF
)"
```

---

### Task 6: The Profile row, the confirmation, and the return to onboarding

**Files:**
- Modify: `Hair Compass AI 5/Feature/BaselineFlow.swift:8-16` (new callback + state), `:118-166` (ScrollViewReader, the row, the alert), near `:310` (`aboutFooter`)
- Modify: `Hair Compass AI 5/App/RootView.swift:60-97` (state), `:396-406` (sheet)
- Modify: `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift` (new test)

**Interfaces:**
- Consumes: `EraseAndStartOver.perform(context:)` from Task 5; `RootView`'s existing `@Environment(\.modelContext) private var context`, `@AppStorage("hasSeenTutorial")`, `@State showOnboarding`, `@State showProfileEdit`.
- Produces: `BaselineFlow.init(profile:onEraseRequested:)` — `var onEraseRequested: (() -> Void)? = nil`.

- [ ] **Step 1: Write the failing UI test**

Append to `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift`, inside the `Hair_Compass_AI_5UITests` class (before its closing brace):

```swift
    /// "Erase everything and start over" wipes the record and returns to the illustrated cover,
    /// exactly as a first install would — and it survives the confirmation alert.
    @MainActor
    func testEraseReturnsToOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_PROFILE"]
        app.launch()

        let erase = app.buttons["eraseStartOver"]
        XCTAssertTrue(erase.waitForExistence(timeout: 10), "the destructive row must exist on Profile")
        erase.tap()

        let confirm = app.alerts.buttons["Erase"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 6), "erase must ask first")
        confirm.tap()

        XCTAssertTrue(app.buttons["onboardIntroPrimary"].waitForExistence(timeout: 12),
                      "after the wipe the app must open on the illustrated cover")
    }
```

`HC_PROFILE` opens the Profile sheet at launch (`RootView.swift:265`). The row is at the bottom of a long form; XCUITest scrolls to a button automatically on `tap()` when it is in the hierarchy but off screen. If `waitForExistence` fails because the row is not yet laid out, insert `app.swipeUp(); app.swipeUp()` before the first assertion.

- [ ] **Step 2: Run the UI test to verify it fails**

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5UITests/Hair_Compass_AI_5UITests/testEraseReturnsToOnboarding" 2>&1 | grep -E "Test Case .* (passed|failed)|error:|TEST (SUCCEEDED|FAILED)" | tail -5
```

Expected: `failed` with "the destructive row must exist on Profile".

- [ ] **Step 3: Add the callback, the row and the alert to BaselineFlow**

In `Hair Compass AI 5/Feature/BaselineFlow.swift`, directly after `@Bindable var profile: Profile`, add:

```swift
    /// Set by RootView. Called after the person confirms "Erase everything and start over";
    /// the wipe itself runs in RootView once this sheet has closed, so no view is still
    /// holding the profile it is about to delete.
    var onEraseRequested: (() -> Void)? = nil
    @State private var confirmErase = false
```

Wrap the form's `ScrollView { ... }` in a `ScrollViewReader { proxy in ... }` (the `ScrollView` is the direct child of the `NavigationStack` in `body`; add the reader around it and keep everything else in place). Give the backup section an anchor by replacing `BackupRestoreSection()` with:

```swift
                    BackupRestoreSection()
                        .id("backup")
```

Directly after `FeedbackSection()` and before `aboutFooter`, add:

```swift
                    startOverSection(proxy: proxy)
```

Add the section and the alert. Place this private view builder next to `aboutFooter`:

```swift
    /// The one destructive action in the app. Deliberately last, deliberately plain — no
    /// card, no icon — and it always asks. The subscription and the 3-day window survive it.
    private func startOverSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) { confirmErase = true } label: {
                Text("Erase everything and start over")
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.critical)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("eraseStartOver")
            Text("Removes every record and photo on this iPhone and returns to the first-run setup. Your subscription is not affected.")
                .font(Clinical.caption(12))
                .foregroundStyle(Clinical.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .alert("Erase everything?", isPresented: $confirmErase) {
            Button("Export first") {
                withAnimation { proxy.scrollTo("backup", anchor: .top) }
            }
            Button("Erase", role: .destructive) {
                onEraseRequested?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All records on this iPhone will be erased and the app starts from the beginning. Export a backup first if you want to keep them. Your subscription is not affected.")
        }
    }
```

- [ ] **Step 4: Perform the erase from RootView after the sheet closes**

In `Hair Compass AI 5/App/RootView.swift`, next to the other `@State` declarations (near line 84), add:

```swift
    /// Set by BaselineFlow's "Erase" confirmation; honoured once the Profile sheet has fully
    /// closed so no presented view still holds the profile being deleted.
    @State private var pendingErase = false
```

Replace the profile sheet:

```swift
        .sheet(isPresented: $showProfileEdit) {
            if let profile {
```

with:

```swift
        .sheet(isPresented: $showProfileEdit, onDismiss: {
            guard pendingErase else { return }
            pendingErase = false
            Task { await eraseAndStartOver() }
        }) {
            if let profile {
```

and pass the callback where `BaselineFlow(profile: profile)` is constructed:

```swift
                BaselineFlow(profile: profile, onEraseRequested: { pendingErase = true })
```

Add the method to `RootView` (next to the other private funcs):

```swift
    /// The wipe, then straight back to the illustrated cover. `hasSeenTutorial` is cleared
    /// explicitly because @AppStorage caches its value in this view.
    private func eraseAndStartOver() async {
        do {
            try await EraseAndStartOver.perform(context: context)
        } catch {
            // Nothing sensible to show mid-wipe; the next launch re-seeds whatever is missing.
            return
        }
        hasSeenTutorial = false
        showOnboarding = true
    }
```

- [ ] **Step 5: Build and run the UI test to verify it passes**

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5UITests/Hair_Compass_AI_5UITests/testEraseReturnsToOnboarding" 2>&1 | grep -E "Test Case .* (passed|failed)|error:|TEST (SUCCEEDED|FAILED)" | tail -5
```

Expected: `passed`, `TEST SUCCEEDED`.

- [ ] **Step 6: Full suites**

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5Tests" 2>&1 | grep -E '✘|Test run with|TEST (SUCCEEDED|FAILED)|BUILD FAILED' | tail -3
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5UITests" 2>&1 | grep -E "Test Case .* failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3
```

Expected: unit run with 479 + 7 new tests passed; UI run `Executed 9 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"
git add "Hair Compass AI 5/Feature/BaselineFlow.swift" "Hair Compass AI 5/App/RootView.swift" "Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift"
git commit -m "$(cat <<'EOF'
Profile: erase everything and start over

A plain destructive row at the end of Profile, always confirmed, with an
'Export first' shortcut to the backup section. The wipe runs in RootView
after the sheet has closed, so nothing still holds the profile being
deleted, then the illustrated cover returns as on a first install. UI
test walks the whole path.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
EOF
)"
```

---

### Task 7: Land sub-project A

**Files:** none new.

- [ ] **Step 1: Push the live line and merge main forward**

```bash
git push origin feat/agent-profile-memory
git checkout -q rebuild/clinical-minimal && git merge -q --no-ff -m "$(cat <<'EOF'
Merge the live line: sub-project A (chart placeholders, erase and start over)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
EOF
)" feat/agent-profile-memory && git diff --stat feat/agent-profile-memory rebuild/clinical-minimal | tail -1 && git push -q origin rebuild/clinical-minimal && git checkout -q feat/agent-profile-memory
```

Expected: the `diff --stat` line is empty (identical trees), both pushes succeed.

- [ ] **Step 2: Leave the simulator on the new build**

```bash
xcrun simctl terminate booted harib.Hair-Compass-AI-5 2>/dev/null
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/Hair Compass AI 5.app"
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_NORITUAL
```

---

## Self-review notes

- Spec A1 sites: Trends rows (Task 2), journey (Task 2), Compare chart and association (Task 3), body signals (Task 4). The spec's per-metric wording for body signals is implemented as one placeholder for the whole card in the answered-but-empty state, because per-metric rows are deliberately not rendered below two readings; noted in Task 4.
- Spec A2: row, alert with Export first / Erase / Cancel (Task 6), wipe contents and the two preserved things (Task 5), tests (Tasks 5 and 6).
- Names used consistently: `ChartPlaceholder`, `ChartPlaceholderPill`, `ChartPlaceholderCopy.label(required:have:unit:)`, `ChartPlaceholderUnit`; `EraseAndStartOver.perform(context:defaults:defaultsDomain:photoStore:cancelNotifications:writeWidget:)`; `PhotoStore(directoryOverride:)`, `deleteAll()`; `BaselineFlow(profile:onEraseRequested:)`; `RootView.pendingErase`, `eraseAndStartOver()`.
