# Medication adherence in Compare + Photo journey timelapse — Design (2026-07-11)

Two features. Both reuse existing machinery (Compare's metric/series pipeline; the Photos
region series).

## 1. Treatment adherence as a Compare variable

Today the Compare builder overlays a hair-fall metric (shedding / scalp / oiliness) against a
lifestyle/body metric. This adds the user's **treatments** (minoxidil, finasteride, rosemary
oil — anything in their plan that they log doses for) as an overlay variable, so they can see
how their shedding or scalp health moved relative to how consistently they used a treatment.

**Why a trailing 14-day average, not raw daily doses:** a treatment is logged as discrete
on/off dose events, which is far too spiky to read against a shedding trend, and hair
responds to *sustained* use over weeks, not single days. A trailing-14-day average turns the
on/off logging into a smooth "how consistently am I using this lately" line that lines up
meaningfully with the lagged shedding trend.

**Pure model** — `Model/TreatmentAdherence.swift`:
```swift
enum TreatmentAdherence {
    /// One point per calendar day in the window (from max(cutoff, treatment.startDate) to now):
    /// value = average doses/day over the trailing 14 days = doses in [day-13, day] / 14.
    /// Unit-agnostic "usage intensity" (≈2.0 for fully-adhered twice-daily; ≈0.14 for weekly);
    /// ChartMath.normalize scales it per-metric for the overlay. Pure + deterministic.
    static func dailyAverage(
        treatment: Treatment, doses: [TreatmentDose],
        window: Int, now: Date = .now, calendar: Calendar = .current,
        averagingDays: Int = 14
    ) -> [(day: Date, value: Double)]
}
```
Doses are matched to a treatment by `persistentModelID`. Days before the treatment's
`startDate` are omitted (no usage to show).

**Catalog wiring** — `ChartMetric` gains a `.treatment` group (add to `MetricGroup`; it's not
`.hairFall`, so `ChartMetric.lifestyle` — which is `group != .hairFall` — already includes it).
Treatment metrics are **dynamic** (one per active treatment), so they aren't in the static
`catalog`. CompareView builds them per-render.

**CompareView changes:**
- `treatmentMetrics: [ChartMetric]` — one `ChartMetric(id: "tx.\(i)", title: name, group:
  .treatment, unit: "14-day avg")` per active treatment (index `i` into the sorted active
  list; ids are stable within a render — the view is ephemeral).
- `treatmentByMetricID: [String: Treatment]` — id → Treatment lookup.
- The Lifestyle scrubber's options become `ChartMetric.lifestyle + treatmentMetrics` (relabel
  the scrubber "Lifestyle & plan").
- `series(for:)` handles `tx.` ids: look up the treatment, call
  `TreatmentAdherence.dailyAverage(...)`.
- Add a preset "Shedding vs {first treatment}" that appears only when ≥1 active treatment.
- Legend/read copy is metric-agnostic already; the hedged phrasing works verbatim
  ("When your {treatment} was higher, shedding tended to be lower…" — still a noticed pattern,
  never proof — matching the app's honesty stance).
- Empty case: when a treatment has no doses in the window, its series is short and the
  existing "Not enough data" guard fires — no special handling.

**Tests** (`TreatmentAdherenceTests.swift`, Swift Testing): fully-adhered twice-daily over 14
days → last value ≈ 2.0; a single dose 14 days ago → decays out of the trailing window; days
before startDate omitted; empty doses → all-zero series over the active span.

## 2. Photo journey timelapse

A player that aggregates the user's same-region photos (works for 2, 30, 60, 180 — any N)
into a progression you can play and scrub, plus a **realistic generated example** so users see
the payoff before they've built their own series.

**`Feature/JourneyPlayerView.swift`** — `JourneyPlayerView(frames: [JourneyFrame])` where
`JourneyFrame` is `{ image: UIImage, caption: String }` (caption = the photo date, or for the
example, a synthetic "Month 0/2/4/6"). Full-screen sheet on `Clinical.canvas`:
- Large 3:4 frame; crossfade between frames (Reduce Motion → hard cut).
- Transport: play/pause button; a scrubber (`Slider` 0…N-1) to scrub by hand; the current
  caption + "frame k of N" shown. Auto-advance on a timer (~0.6 s/frame) when playing, looping.
- A small "aggregating N photos" subtitle so the count is explicit.
- Handles N==0/1 gracefully (single frame, no transport).

**Building frames — `PhotosView`:**
- `regionFrames(_:) -> [JourneyFrame]` loads the region's photos (oldest→newest) via
  `PhotoStore.shared.loadThumbnail(maxPixel: 1200)`, caption = capture date.
- A **"Play journey"** button in the region section, enabled when the region has ≥2 photos;
  opens `JourneyPlayerView` with the real frames.
- An **"See an example journey"** affordance (shown when the region has <2 photos) that plays
  the bundled example sequence — 4 realistic generated frames (`journey-example-1…4`) captioned
  "Baseline / Month 2 / Month 4 / Month 6", clearly labeled **"Example — a tracked 6-month
  journey"** so it's never mistaken for the user's own data.
- The example frames are loaded from the asset catalog (`UIImage(named:)`).

**Generated example (Higgsfield):** 4 realistic top-down crown frames — the same man's scalp
progressing from a thinning vertex to full regrowth — generated with the first frame as a
consistency reference. Bundled as `journey-example-1..4` imagesets. Honest framing: this is an
illustrative example of what consistent tracking *can* look like, not a promise; the label and
the app's existing "record-keeping, not diagnosis / results vary" stance cover it.

**Tests:** none (pure UI + asset load); verified by building frames from the example in the
simulator and screenshotting the player.

## Non-goals
No video export/sharing of the journey, no ML alignment/registration of photos (the guided
capture already standardizes framing), no adherence in the Today insight card (Compare only).

## Execution
Two Sonnet tracks (disjoint files): A adherence-in-Compare, B journey player. Fable generates
+ bundles the 4 example frames, integrates, builds, tests, screenshots, commits.
