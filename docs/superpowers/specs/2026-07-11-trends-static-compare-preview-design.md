# Static Trends + Compare medication dropdown & 7-day preview — Design (2026-07-11)

Two independent changes, disjoint files.

## 1. Make Trends static — elements do not move

**Diagnosis:** Round 8 pinned the chart axes (killed the horizontal drift). The remaining
movement is the **`.staggeredEntrance(index:)`** on all nine Trends cards: each card starts
offset +10pt and springs up + fades in on `.onAppear`. Because `RootView` swaps tab views
(`switch tab`), navigating to Trends re-creates `TrendsView`, so the entrance's `@State shown`
resets and the whole page slides/springs in **every time the user opens the tab**. The
sub-components have no continuous animation (verified: `BodySignalsDashboard` charts use
`.chartYAxis(.hidden)`; `ConsistencyCard`'s only animation is a badge reveal that fires only
when a new badge is earned; `JourneyChart` is static). The trajectory card's 7-day average also
uses `.contentTransition(.numericText())`.

**Fix (Track A, `TrendsView.swift` only):**
- Remove `.staggeredEntrance(index:)` from all nine cards so they render **in place** — no
  slide, no fade, no spring — on every entry.
- Remove `.contentTransition(.numericText())` on the trajectory average (plain `Text`), so the
  number doesn't morph.
- Keep the round-8 fixed-width axis labels and the `CornerSprig` (static background).
- Result: opening/re-opening Trends and scrolling it is completely static. (Other tabs keep
  their entrance — this is deliberately Trends-only, per the request.)
- Verify on the simulator: launch to Trends, screenshot; re-launch to Trends, screenshot;
  confirm nothing animates in and the charts share a constant gutter. If any chart still shifts
  horizontally, pin its axis/clip it (belt-and-suspenders).

## 2. Compare — medication dropdown + faded 7-day preview

Today the user's tracked treatments are only reachable inside the "Lifestyle & plan"
`MetricScrubber` (as `tx.N` options) — hard to discover. And when a comparison lacks data the
chart shows a bare "Not enough data" line. Two improvements (Track B, `CompareView.swift` only):

### 2a. Propose tracked medications via a dropdown
- When `!activeTreatments.isEmpty`, show a **`Menu` dropdown** above/beside the pickers:
  "Compare a medication ▾" listing each active treatment (name + `TreatmentClass` symbol).
  Selecting one sets `overlayID = "tx.\(i)"` (the existing treatment-metric id) and, for
  clarity, sets `hairID = "shed"` if the current hair metric isn't a hair-fall one. A trailing
  check marks the currently-selected treatment. This *proposes* the user's tracked meds for
  overlay without removing the existing scrubbers.
- Keep the existing presets + scrubbers; the dropdown is an additional, clearer entry.

### 2b. Faded illustrative preview until 7 days of data
Replace the bare-text empty state with an honest locked preview whenever the current comparison
has **fewer than 7 overlapping days** of data
(`min(hairPts.count, overlayPts.count) < 7`):
- Draw a **faded illustrative dummy chart** — a fixed sample of two smooth curves (a copper
  "your signal" line trending down + a sage overlay line), rendered at ~0.28 opacity using the
  same `Chart` styling, so the user sees *what the real chart will look like*.
- Overlaid center message (in a soft `Clinical.surface` chip): a small `lock` glyph + "Your
  real graph unlocks after 7 days of tracking" and, when computable, "{n} of 7 days logged."
- **Honesty:** a clear "Sample — your data will replace this" eyebrow so the faded curve is
  never mistaken for real data (matches the app's illustrative-chart stance). The `readCard`
  association stays as-is (already gated behind `minPairs`), so no false pattern is claimed.
- At ≥ 7 overlapping days, the real chart renders exactly as today.

The dummy sample data is a small static array defined in `CompareView` (no model/schema
change). "7 days" = overlapping logged days in the selected window.

## Non-goals
No schema changes, no new files, no change to the honest `association`/read logic, no change to
other tabs' entrance animation.

## Tests
None (both are pure UI/layout). Verified by build + simulator screenshots (Trends static;
Compare dropdown + faded preview via `HC_SEED_DEMO`, and the preview state by picking a
freshly-tracked treatment or a short window).

## Execution
Two parallel Sonnet tracks: A `TrendsView.swift`; B `CompareView.swift`. Orchestrator builds,
screenshots, commits.
