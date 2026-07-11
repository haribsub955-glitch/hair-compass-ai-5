# Trends drift + widget alignment + AI labs + ritual cadence — Design (2026-07-11)

Four independent fixes (user numbered them 1, 2, 3, 5).

## 1. Trends elements drift left/right

**Diagnosis:** Trends stacks several Swift Charts, each with a **leading Y-axis whose label
widths differ and are not pinned** — `TrendsView.yAxis(_:labels:)` renders "Min/Norm/Elev/
Heavy" (shedding) and "0/5/10/16" (scalp); `JourneyChart` has its own leading axes. Swift
Charts sizes the leading gutter to the widest label *per chart and re-measures on layout/
animation*, so the plot origin isn't stable and the chart content visibly shifts horizontally
relative to the card — the "moves left and right" the user sees. Other tabs don't stack
leading-axis charts, so they don't drift. (Belt-and-suspenders: also confirm no card/chart
overflows the content width, which would let the vertical ScrollView pan sideways.)

**Fix:** pin every leading `AxisValueLabel` to a fixed width so the gutter is constant.
- `TrendsView.yAxis`: wrap the label `Text` in `.frame(width: 34, alignment: .trailing)`.
- `JourneyChart`'s leading axes (shed axis + the intake-lane single "0"): same fixed-width
  wrap (width consistent between the stacked charts so they align).
- Verify (build + a Trends screenshot with demo data) nothing overflows horizontally; if any
  chart's trailing x-axis label overflows the plot, add `.clipped()` to that chart only.

No behavior change beyond stable layout.

## 2. Widget snapshot aligned with the app

**Current state:** the `WidgetSnapshot` **stored fields are already identical** across
`Service/WidgetBridge.swift` and `Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift`
(the only diff is widget-only display helpers `placeholder`/`isFreshInstall`, which don't
affect the Codable wire format). The risk is silent future drift.

**Fix (pin + guard):**
- Add an explicit `enum CodingKeys` listing all 11 fields to BOTH structs (identical), so the
  encoded key set is pinned and any rename becomes a visible per-side change.
- Add a synchronized `// KEEP IN SYNC — fields must match <other file>` header block listing
  the canonical field list above each struct.
- Add an app-target round-trip test (`WidgetSnapshotTests.swift`): encode a fully-populated
  snapshot, decode it back, assert equality, and assert the exact JSON key set (so any
  app-side field change trips the test). Include a note that the widget copy must be updated
  in lockstep (the test can't see the widget target).

## 3. AI reads all sources, including labs, organized

**Current state:** the deep-analysis + chat path already builds the full `AIContext`
(profile, dailySeries, treatments **with side effects**, **labs**, triggers, bodySignals,
photo metadata) — comprehensive. The gap is the **Today daily insight**, which uses the
lighter `InsightContext` that has **no lab data**, so the daily insight can't reference a low
ferritin or an out-of-range thyroid result.

**Fix:** add labs to `InsightContext`:
- New field `var labs: [LabNote]` where `LabNote { var name: String; var flag: String
  (below/in/above range); var value: Double; var unit: String }`, built from the latest
  `LabResult` per `LabTest` (most recent `collectedAt`), reusing `LabResult.flag`.
- `InsightContext.build` gains a `labs: [LabResult]` parameter; `TodayView.buildContext`
  passes its existing `labs` @Query.
- The rule-based insight (`InsightEngine`) and the on-device prompt use them: e.g. surface a
  below-range ferritin as a relevant, honest note ("Ferritin is below the range often cited
  for hair — worth discussing with a clinician"), never as diagnosis. Add the labs to the
  prompt's structured context so the LLM path sees them too.
- Confirm the deep-analysis/chat `AIContext` labs are populated (they are) — no change needed
  there beyond a verification note.

## 5. Ritual every 5th open, not 1-in-3 random

Replace the probability roll in `LaunchRitualCoordinator` with a deterministic **open
counter**.
- New `Key.openCount`. A single private `shouldShowOnOpen()` increments the counter on each
  *eligible* open and returns true exactly when `openCount % 5 == 0` (i.e., the 5th, 10th, …).
- `rollOnLaunch` and `rollOnForeground` both call `shouldShowOnOpen()` instead of
  `Double.random < frequency`. The first-ever-launch guard (never show on the very first
  launch; onboarding owns it) stays and does NOT increment the counter for that first launch.
- Keep: the not-onboarded guard, the no-repeat `pick()`, the >4h-foreground bookkeeping, and
  all DEBUG overrides (`HC_RITUAL` still forces show; `HC_RITUAL_KIND` still forces a kind).
- `static var frequency` is removed (or left unused and documented); the cadence is now the
  count constant `showEveryNOpens = 5` (a `static var` so it stays tweakable).
- Tests (`LaunchRitualCadenceTests`): opens 1–4 → nil, open 5 → a kind, opens 6–9 → nil, open
  10 → a kind; first-ever launch returns nil and doesn't consume a count.

## Non-goals
No new charts, no widget UI change, no new AI features beyond labs-in-daily-insight, no change
to ritual visuals or kinds.

## Execution
Three Sonnet tracks (disjoint files): A Trends chart axis fix; B widget alignment + ritual
cadence; C AI labs in the daily insight. Fable integrates, builds, tests, screenshots Trends,
commits.
