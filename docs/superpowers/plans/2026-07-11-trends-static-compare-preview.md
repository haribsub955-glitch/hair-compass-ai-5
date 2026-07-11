# Static Trends + Compare dropdown/preview — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Trends page fully static (no entrance/reflow motion), and in Compare add a medication dropdown plus an honest faded "unlocks after 7 days" preview.

**Architecture:** Two parallel Sonnet tracks, one file each (disjoint). Spec: `docs/superpowers/specs/2026-07-11-trends-static-compare-preview-design.md`. Constraints: Clinical tokens, honesty (the faded chart must be clearly illustrative), keep the round-8 axis pinning, **agents do not run xcodebuild/git** (except a screenshot build for verification if useful), quote paths. No cross-track shared symbols.

---

### Task A: Static Trends

**File (owns exclusively):** `Hair Compass AI 5/Feature/TrendsView.swift`.

- [ ] **A1:** Remove every `.staggeredEntrance(index: N)` modifier from the Trends cards (there are 9, on the trajectory card, JourneyChart, ConsistencyCard, BodySignalsDashboard, compareEntryCard, emptyState, sheddingCard, scalpCard, adherenceCard, excludedCard). The cards then render in place with no slide/fade/spring.
- [ ] **A2:** Change the trajectory 7-day-average number from `.contentTransition(.numericText())` to a plain `Text` (drop the content transition) so it doesn't morph.
- [ ] **A3:** Leave the round-8 fixed-width axis labels, `CornerSprig`, `ClinicalSegmented`, and all data logic untouched. Do not remove the ScrollView or restructure layout.
- [ ] **A4: Verify.** Build the app scheme; launch `HC_SEED_DEMO HC_TAB trends`, screenshot; terminate; launch `HC_TAB trends` again, screenshot. Confirm the page is static (no card animates in) across both, and the charts still align on a constant left gutter. If any chart visibly shifts horizontally, pin its `AxisValueLabel` width (34pt, like round 8) or `.clipped()` that specific `Chart`. You MAY run xcodebuild/simctl for this. Do NOT run git.

### Task B: Compare medication dropdown + faded 7-day preview

**File (owns exclusively):** `Hair Compass AI 5/Feature/CompareView.swift`.

Read the whole file first (it has `activeTreatments`, `treatmentMetrics`, `treatment(forMetricID:)`, `series(for:)`, the `pickers`, and the `chartCard` with the `hairPts.count < 2 || overlayPts.count < 2` empty state).

- [ ] **B1: Medication dropdown.** Add a `medicationMenu` view shown only when `!activeTreatments.isEmpty`, placed just above `pickers` (or between presets and pickers). A SwiftUI `Menu` labeled "Compare a medication" (copper, chevron.down, `.clinicalPressable` or a capsule matching the presets style) whose items iterate `activeTreatments.enumerated()`:
  ```swift
  Menu {
      ForEach(Array(activeTreatments.enumerated()), id: \.element.persistentModelID) { i, t in
          Button {
              overlayID = "tx.\(i)"
              if !ChartMetric.hairFall.contains(where: { $0.id == hairID }) { hairID = "shed" }
          } label: {
              Label(t.name.isEmpty ? t.treatmentClass.title : t.name, systemImage: overlayID == "tx.\(i)" ? "checkmark" : t.treatmentClass.symbol)
          }
      }
  } label: {
      // capsule: "Compare a medication" + current selection when a tx.* is chosen + chevron.down
  }
  ```
  When the current `overlayID` is a `tx.*`, the label shows the chosen treatment's name. Keep the existing presets + `MetricScrubber`s intact.

- [ ] **B2: Faded 7-day preview.** In `chartCard`, replace the `if hairPts.count < 2 || overlayPts.count < 2` branch with a threshold of **7 overlapping days**: compute `let ready = min(hairPts.count, overlayPts.count) >= 7`. When NOT ready, render `previewLocked(daysLogged: min(hairPts.count, overlayPts.count))` instead of the bare text; when ready, render the existing real chart unchanged.

- [ ] **B3: previewLocked view.** Add it:
  - A `ZStack`: behind, a faded illustrative `Chart` (opacity ~0.28) drawn from a fixed static sample — two `LineMark` series with explicit `series:` (avoid the merge bug), `.monotone`, `Clinical.accent` (a gently declining "your signal") and `Clinical.sage` (a rising overlay), `.chartYScale(domain: 0...1)`, `.chartYAxis(.hidden)`, `.chartXAxis(.hidden)`, height 170 — matching the real chart's frame so the layout doesn't jump when it unlocks.
  - In front, centered, a `Clinical.surface`(opacity 0.9) chip: `Image(systemName: "lock.fill")` (13pt, `Clinical.tertiary`), then "Your real graph unlocks after 7 days of tracking" (14pt ink), and "\(daysLogged) of 7 days logged" (12pt secondary) — with a small `Eyebrow(text: "Sample — your data will replace this")` above the chip so the faded curve is unmistakably illustrative.
  - The sample arrays are `let` constants in `CompareView` (e.g. 14 points each); no model change. Reduce Motion: static (it already is).

- [ ] **B4:** Keep the legend/`readCard`/lag logic as-is (the read is already gated behind `minPairs`, so no false pattern is shown during preview). Do NOT change `series(for:)` or the honest association.

- [ ] **B5: Verify.** (Orchestrator, or you may build.) Screenshot Compare with the demo seed (real chart + the medication dropdown); and the preview state by selecting a treatment whose overlap is < 7 days, or a 1M window on sparse data.

### Task C (orchestrator): integrate, build, screenshot, commit
- [ ] Build app + widget (0 warnings); run unit tests (should be unaffected); screenshot static Trends (two entries) and Compare (dropdown + faded preview); commit per track + spec/plan.
