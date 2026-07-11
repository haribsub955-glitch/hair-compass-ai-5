# Adherence in Compare + Photo Journey — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users overlay a treatment's trailing-14-day usage against shedding/scalp in Compare, and play their same-region photos (any N) as a scrubbable journey timelapse with a realistic generated example.

**Architecture:** Two parallel Sonnet tracks, disjoint files. Spec: `docs/superpowers/specs/2026-07-11-adherence-journey-design.md`. Same global constraints as prior plans (Clinical tokens, Reduce Motion, honesty framing, **agents do not run xcodebuild / git**, Swift Testing, quote paths). The 4 example imagesets `journey-example-1..4` are bundled by the orchestrator — Track B references them by name.

**No cross-track shared symbols.**

---

### Task A: Treatment adherence in Compare

**Files (owns exclusively):** Create `Hair Compass AI 5/Model/TreatmentAdherence.swift`, `Hair Compass AI 5Tests/TreatmentAdherenceTests.swift`; Modify `Hair Compass AI 5/Model/ChartMetric.swift`, `Hair Compass AI 5/Feature/CompareView.swift`.

- [ ] **A1: Pure adherence model.** Create `TreatmentAdherence.swift`:

```swift
import Foundation

/// Turns a treatment's discrete logged doses into a smooth daily "usage intensity" line —
/// the trailing `averagingDays`-day average doses/day — so consistent use reads against a
/// shedding trend. Pure + deterministic; doses matched to the treatment by persistentModelID.
enum TreatmentAdherence {
    static func dailyAverage(
        treatment: Treatment,
        doses: [TreatmentDose],
        window: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        averagingDays: Int = 14
    ) -> [(day: Date, value: Double)] {
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(window - 1), to: today) else { return [] }
        let startDay = max(cutoff, calendar.startOfDay(for: treatment.startDate))
        guard startDay <= today else { return [] }

        // Dose days for THIS treatment (start-of-day → count).
        var countByDay: [Date: Int] = [:]
        for d in doses where d.treatment?.persistentModelID == treatment.persistentModelID && d.loggedAt <= now {
            countByDay[calendar.startOfDay(for: d.loggedAt), default: 0] += 1
        }

        var out: [(day: Date, value: Double)] = []
        var day = startDay
        while day <= today {
            var total = 0
            for k in 0..<averagingDays {
                if let d = calendar.date(byAdding: .day, value: -k, to: day) { total += countByDay[d] ?? 0 }
            }
            out.append((day: day, value: Double(total) / Double(averagingDays)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }
}
```

- [ ] **A2: MetricGroup + treatment.** In `ChartMetric.swift`, add `case treatment = "Plan"` to `MetricGroup`. `ChartMetric.lifestyle` (defined as `group != .hairFall`) already includes it — no change to that computed prop. Add a doc note that treatment metrics are dynamic (not in `catalog`).

- [ ] **A3: CompareView dynamic metrics.** In `CompareView`:
  - Add computed `activeTreatments: [Treatment] { treatments.filter { $0.isActive }.sorted { $0.startDate < $1.startDate } }`.
  - `treatmentMetrics: [ChartMetric] { activeTreatments.enumerated().map { i, t in ChartMetric(id: "tx.\(i)", title: t.name.isEmpty ? t.treatmentClass.title : t.name, group: .treatment, unit: "14-day avg") } }`.
  - `treatment(forMetricID:) -> Treatment?` parsing `tx.<i>` → `activeTreatments[i]` (bounds-checked).
  - The Lifestyle `MetricScrubber` options become `ChartMetric.lifestyle + treatmentMetrics`; relabel its title "Lifestyle & plan". The `overlay` computed metric lookup must also resolve `tx.` ids: change `overlay` to `ChartMetric[overlayID] ?? treatmentMetrics.first { $0.id == overlayID } ?? ChartMetric.lifestyle[0]`.
  - In `series(for:)`, before `default:`, add: `case let id where id.hasPrefix("tx."): if let t = treatment(forMetricID: id) { pairs = TreatmentAdherence.dailyAverage(treatment: t, doses: doses, window: window.days).map { ($0.day, $0.value) } } else { pairs = [] }`. (Return already sorts.)
  - Add a preset that only renders when `!activeTreatments.isEmpty`: `presetChip("Shedding vs \(activeTreatments[0].name.isEmpty ? activeTreatments[0].treatmentClass.title : activeTreatments[0].name)", "shed", "tx.0")`. Keep it last in the presets HStack, guarded by `if !activeTreatments.isEmpty`.

- [ ] **A4: Tests.** `TreatmentAdherenceTests.swift` (Swift Testing, `@testable import Hair_Compass_AI_5`, `@MainActor` — building `@Model` instances). Build a `Treatment` (startDate 30 days ago) + `TreatmentDose`s. Cases:
  - Twice-daily for the last 14 days (28 doses across 14 days) → the final day's value ≈ 2.0 (`abs(last - 2.0) < 0.001`).
  - A single dose exactly `averagingDays` days before `now` is NOT counted on `now`'s point (outside the trailing 14-day window `[now-13, now]`); a dose 13 days before IS counted.
  - No doses → every point == 0, and the series spans startDay…today (count == 30).
  - Days before `startDate` are omitted (a treatment starting 5 days ago over a 30-day window yields ≤ 6 points).
  Use a fixed `now` and `Calendar(identifier: .gregorian)` for determinism. To attach doses to a treatment without a ModelContext, set `dose.treatment = t` directly (the code reads `d.treatment?.persistentModelID`); if persistentModelID requires insertion, insert both into an in-memory `ModelContainer` (see `Hair_Compass_AI_5Tests.swift` for the pattern) — pick whichever compiles.

### Task B: Photo journey timelapse

**Files (owns exclusively):** Create `Hair Compass AI 5/Feature/JourneyPlayerView.swift`; Modify `Hair Compass AI 5/Feature/PhotosView.swift`.

- [ ] **B1: JourneyPlayerView.** Create it:

```swift
import SwiftUI

struct JourneyFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let caption: String
}

/// Plays a same-region photo series (any count) as a scrubbable timelapse. The count is
/// explicit ("aggregating N photos") so the journey reads as an aggregation of real captures.
struct JourneyPlayerView: View {
    let frames: [JourneyFrame]
    var isExample: Bool = false
    // play/pause + scrubber + crossfade; Reduce Motion → hard cut; timer ~0.6s/frame, looping.
}
```

Requirements: `NavigationStack` with a Done cancellation button; title "Journey". Large 3:4 image on `Clinical.canvas` (rounded, hairline). When `isExample`, a copper `Eyebrow`/badge "EXAMPLE — a tracked 6-month journey" over the image. Below: the current frame's caption (headline date/month) + "frame k of N" (`Clinical.eyebrow`). Transport row: a play/pause `Button` (SF `play.fill`/`pause.fill`), a `Slider(value:in:)` bound to a `Double` current-index (snap to `Int` on change), and an "Aggregating N photos" subtitle. A `Timer.publish` (0.6s) advances the index while playing, looping to 0 after the last frame; pause stops it. Crossfade via `.id(index) + .transition(.opacity)` inside a `withAnimation(reduceMotion ? nil : .easeInOut(0.35))`. N ≤ 1: show the single frame, hide play/slider. Honor Reduce Motion (no crossfade). Accessibility: label the play button, the slider ("Journey timeline").

- [ ] **B2: PhotosView wiring.** In `PhotosView`:
  - `@State private var journeyFrames: [JourneyFrame]? = nil` and `@State private var journeyIsExample = false`; `.sheet(item:)` needs Identifiable — wrap in a tiny `struct JourneyPresentation: Identifiable { let id = UUID(); let frames: [JourneyFrame]; let isExample: Bool }` and use `@State private var journey: JourneyPresentation?` + `.sheet(item: $journey) { JourneyPlayerView(frames: $0.frames, isExample: $0.isExample) }`.
  - `regionFrames() -> [JourneyFrame]`: `regionPhotos` (already oldest→newest) mapped to frames via `PhotoStore.shared.loadThumbnail(record.imagePath, maxPixel: 1200)` (skip nils), caption = `record.createdAt.formatted(.dateTime.month().day().year())`.
  - `exampleFrames() -> [JourneyFrame]`: `["journey-example-1","journey-example-2","journey-example-3","journey-example-4"]` via `UIImage(named:)` (compactMap), captions `["Baseline","Month 2","Month 4","Month 6"]`.
  - A **Journey card** placed right under the `regionPicker` (before the compareCard): a `ClinicalCard` with an `Eyebrow("Journey")`, a one-line description, and a primary-styled button. When `regionPhotos.count >= 2`: button "Play journey · \(regionPhotos.count) photos" → `journey = .init(frames: regionFrames(), isExample: false)`. Else: text "Capture a few {region} photos to build your own — here's what one looks like." + a secondary "See an example journey" button → `journey = .init(frames: exampleFrames(), isExample: true)`. Give it `.staggeredEntrance(index: 2)` and bump the compare/empty/grid indices by 1.
  - Keep everything else (region dots, summary line, grid tap-to-detail from round 5) intact.

- [ ] **B3:** No unit test; orchestrator screenshots the example player.

### Task C (orchestrator): example asset generation + integration
- [ ] Generate + review the 4 realistic regrowth frames (Higgsfield), bundle as `journey-example-1..4` imagesets.
- [ ] Build; unit tests; install; screenshot Compare with a treatment overlay (seed demo has treatments — use HC_SEED_DEMO HC_TAB trends HC_COMPARE) and the example journey player (Photos → See an example journey; drive headlessly if possible, else code-verify); commit per track + spec/plan + assets.
