# Trends + widget + AI labs + ritual cadence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Trends from drifting horizontally, pin the widget snapshot to the app, feed labs into the daily AI insight, and show the ritual every 5th open.

**Architecture:** Three parallel Sonnet tracks, disjoint files. Spec: `docs/superpowers/specs/2026-07-11-trends-widget-ai-ritual-design.md`. Same global constraints (Clinical tokens, **agents do not run xcodebuild/git**, Swift Testing, quote paths). No cross-track shared symbols.

---

### Task A: Trends horizontal drift

**Files (owns exclusively):** `Hair Compass AI 5/Feature/TrendsView.swift`, `Hair Compass AI 5/Feature/JourneyChart.swift`.

- [ ] **A1: Pin the TrendsView leading-axis label width.** In `TrendsView.yAxis(_:labels:)` (~line 420), wrap the label in a fixed-width frame so the leading gutter can't resize:

```swift
private func yAxis(_ values: [Double], labels: [String]) -> some AxisContent {
    AxisMarks(position: .leading, values: values) { value in
        AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
        AxisValueLabel {
            if let v = value.as(Double.self), let idx = values.firstIndex(of: v) {
                Text(labels[idx])
                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                    .frame(width: 34, alignment: .trailing)   // pin gutter — stops horizontal breathing
            }
        }
    }
}
```

- [ ] **A2: Pin JourneyChart's leading axes.** In `JourneyChart.swift`, the shed chart's leading `AxisMarks(position: .leading, values: Self.shedAxisValues)` label and the intake-lane's `AxisMarks(position: .leading, values: [0.0])` label both get the same `.frame(width: 34, alignment: .trailing)` wrap on their `AxisValueLabel` `Text`, so the two stacked charts align on a constant gutter. Read the file first to match its label rendering exactly.

- [ ] **A3: Overflow check.** Build and open Trends with demo data (`HC_SEED_DEMO HC_TAB trends`); screenshot. If any chart's trailing x-axis month label overflows its plot (a known Swift Charts edge), add `.clipped()` to that specific `Chart`. Do NOT blanket-clip cards. Confirm the fixed-width labels didn't clip any legit label text (34pt fits "Heavy"/"Norm"/"16" at eyebrow(9); widen to 38 if any truncates).

- [ ] **A4:** No unit test (layout); orchestrator screenshots Trends.

### Task B: Widget alignment + ritual cadence

**Files (owns exclusively):** `Hair Compass AI 5/Service/WidgetBridge.swift`, `Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift`, `Hair Compass AI 5/Service/LaunchRitualCoordinator.swift`, `Hair Compass AI 5Tests/WidgetSnapshotTests.swift`, new `Hair Compass AI 5Tests/LaunchRitualCadenceTests.swift`.

- [ ] **B1: Pin the widget struct.** Add an identical `enum CodingKeys: String, CodingKey { case generatedAt, hasLoggedToday, score, ringLog, ringCare, ringLens, shedLabel, scalpLabel, streakDays, shieldsHeld, dueTitles }` inside BOTH `WidgetSnapshot` structs (app + widget file). Above each struct add a synced header:

```swift
// KEEP IN SYNC — WidgetSnapshot is duplicated in
//   Service/WidgetBridge.swift  and
//   Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift
// Stored fields (Codable): generatedAt, hasLoggedToday, score, ringLog, ringCare, ringLens,
//   shedLabel, scalpLabel, streakDays, shieldsHeld, dueTitles. Change both together.
```

Do not alter the fields or the widget-only `placeholder`/`isFreshInstall` helpers.

- [ ] **B2: Round-trip test.** In `WidgetSnapshotTests.swift` (read it first), add:

```swift
@Test func widgetSnapshotRoundTripsAndKeysAreStable() throws {
    let snap = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        hasLoggedToday: true, score: 71, ringLog: 1, ringCare: 0.5, ringLens: 0,
        shedLabel: "Elevated", scalpLabel: "Scalp mild", streakDays: 4, shieldsHeld: 1,
        dueTitles: ["Minoxidil · 21:00"])
    let data = try JSONEncoder().encode(snap)
    let back = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    #expect(back == snap)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(obj.keys) == ["generatedAt","hasLoggedToday","score","ringLog","ringCare",
        "ringLens","shedLabel","scalpLabel","streakDays","shieldsHeld","dueTitles"])
}
```

`WidgetSnapshot` must be `Equatable` for `==` — add `Equatable` conformance to the app-target struct if absent (it's a value type of Codable primitives, so `Equatable` synthesizes; add it to the widget copy too to stay in sync). `ringCare` is `Double?` and omitted-when-nil is fine (the test uses a non-nil value so the key is present).

- [ ] **B3: Ritual every-5 cadence.** In `LaunchRitualCoordinator.swift`:
  - Add `static var showEveryNOpens = 5` and `private enum Key { ... static let openCount = "ritualOpenCount" }`.
  - Add `private func shouldShowOnOpen() -> Bool { let n = defaults.integer(forKey: Key.openCount) + 1; defaults.set(n, forKey: Key.openCount); return n % Self.showEveryNOpens == 0 }`.
  - `rollOnLaunch`: keep the DEBUG overrides and the first-ever-launch guard (which returns nil WITHOUT calling shouldShowOnOpen, so the first launch doesn't consume a count) and the `hasOnboarded` guard; then replace `guard Double.random(in: 0..<1) < Self.frequency else { return nil }` with `guard shouldShowOnOpen() else { return nil }`.
  - `rollOnForeground`: replace its probability guard with `guard shouldShowOnOpen() else { return nil }` (after the DEBUG + hasOnboarded guards).
  - Remove `static var frequency` (or mark it deprecated/unused with a comment); it's no longer read.
  - Keep `pick()`, the >4h bookkeeping, logging, and all DEBUG overrides unchanged.

- [ ] **B4: Cadence test.** New `LaunchRitualCadenceTests.swift` (Swift Testing, `@MainActor`): construct `LaunchRitualCoordinator(defaults:)` with a fresh in-memory `UserDefaults(suiteName:)` (unique suite name; call `removePersistentDomain` first) and a `hasLaunchedBefore=true` seed so the first-launch guard is passed. Assert `rollOnLaunch(hasOnboarded: true)` returns nil for calls 1–4, non-nil on call 5, nil 6–9, non-nil on 10. Also assert a fresh coordinator with `hasLaunchedBefore` unset returns nil on its first call and does NOT advance toward 5 (call it once, then verify calls 2–5 make the 5th non-nil... i.e., first-launch nil didn't consume the counter). Keep `Self.showEveryNOpens` as-is (5).

### Task C: Labs into the daily AI insight

**Files (owns exclusively):** `Hair Compass AI 5/Service/InsightEngine.swift`, `Hair Compass AI 5/Feature/TodayView.swift`, new `Hair Compass AI 5Tests/InsightLabsTests.swift`.

- [ ] **C1: LabNote in InsightContext.** In `InsightEngine.swift`, add to `InsightContext`:

```swift
struct LabNote: Sendable { var name: String; var flag: String; var value: Double; var unit: String }
var labs: [LabNote]
```

`InsightContext.build` gains a `labs: [LabResult]` parameter (place it after `triggers`). Build `labs` = latest `LabResult` per `LabTest` (group by `test`, take max `collectedAt`), mapped to `LabNote(name: test.title, flag: {below range → "below", in → "in", above → "above"} from `LabResult.flag`, value: value, unit: test.unit)`. Read `LabTest`/`LabResult`/`LabFlag` in `Model/Enums.swift`+`Models.swift` first for the exact API (`.flag`, `.referenceRange`, `.unit`).

- [ ] **C2: Use labs in the rule-based insight.** In the deterministic `InsightEngine` insight builder (read how it currently composes `RuleBasedInsight`/the fallback text), add an honest lab note when a hair-relevant lab is out of range — prioritize a **below-range ferritin** and any out-of-range thyroid (TSH/Free T4), phrased as context not diagnosis, e.g. "Ferritin is below the range often cited for hair — worth raising with a clinician." Only surface when such a lab exists; never invent. Keep the existing insight logic; labs are an additional, lower-priority note.

- [ ] **C3: Prompt path.** If `InsightContext` is serialized/summarized for the on-device Foundation Models prompt, include the labs in that summary (a short "Recent labs: ferritin 22 ng/mL (below), TSH 2.1 (in range)" line) so the LLM path sees them too. Match the existing prompt-building style.

- [ ] **C4: TodayView passes labs.** In `TodayView.buildContext()` (which calls `InsightContext.build`), pass `labs: labs` (TodayView already has a `@Query ... labs: [LabResult]`). Confirm no other `InsightContext.build` call site exists (grep) — if one does, update it too.

- [ ] **C5: Verify AIContext (deep/chat) labs.** Read `Model/AIContextBuilder.swift`'s labs section; confirm `LabFacts` is populated from the `labs` param and that `DeepAnalysisSheet` + `CompareView` pass `labs`. No change expected — just confirm and note in the return.

- [ ] **C6: Test.** `InsightLabsTests.swift` (Swift Testing, `@MainActor`): build `LabResult`s (a below-range ferritin + an in-range TSH), call `InsightContext.build(...)` with them, assert `context.labs` has the latest-per-test with correct flags, and that a below-range ferritin yields the honest lab note in the rule-based insight output (call the deterministic insight function directly if exposed; else assert on `context.labs`).

### Task D (orchestrator): integrate, build, test, screenshot Trends, commit
- [ ] Build; unit tests; screenshot Trends with demo data (`HC_SEED_DEMO HC_TAB trends`) and eyeball the charts align on a constant gutter; commit per track + spec/plan.
