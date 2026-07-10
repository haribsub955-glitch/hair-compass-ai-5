# Onboarding Round 2 + Living Dashboard — Design (2026-07-11)

Four requests, confirmed with the user via AskUserQuestion (dashboard question = shedding
drag-dial on the hero; "high bar" = the family-history risk gauge).

## 1. Family-history risk gauge (onboarding step 9)

Replace the small static `RiskArc` (150×90 half-arc) with a **RiskGauge**:
- ~230pt wide, 180° arc, thicker stroke (14pt), gradient track fill (accentSoft → accent)
  that trims to the value with a spring; a thin copper **needle** sweeps to the value.
- Band labels around the arc: LOW · RAISED · HIGH · HIGHEST (eyebrow type, tertiary;
  active band in accent).
- Center readout: band word (Clinical.headline 22) + "relative odds" eyebrow.
- Context line UNDER the gauge, switching with selection (honest, never predictive):
  - none: "Baseline odds — no measured family signal."
  - extended: "Somewhat raised odds in studies — context, not a prediction."
  - oneParent: "Meaningfully raised odds (~2.7× in a 2026 meta-analysis) — context, not a prediction."
  - bothParents: "The strongest measured signal (~2.7× odds, both sides) — still context, not a prediction."
- Reduce Motion: needle/fill jump to position, no sweep. Haptic selection tick unchanged
  (lives on the option buttons).
- Same call-site shape: `RiskGauge(value: riskValue)` + the context line driven by
  `profile.familyHistory` in `familyStep`.

## 2. End-of-onboarding "difference" graph + generated image (plan step)

Everyone now gets a **graph** on the paywall projection card, not just male AGA:
- `ProjectionModel` gains `differenceCurve: [DifferencePoint]` (`week`, `withTracking`,
  `without`, both 0…1) — a universal, explicitly **illustrative** two-line chart whose
  y-axis is *signal clarity* ("how clearly you can see what's working"), NOT hair count.
  `withTracking` rises smoothstep 0→1 over 24 weeks; `without` stays low and flat (≤0.15,
  slight noise). Axis label: "Signal clarity (illustrative)". Legend: "Tracking daily"
  (copper solid) vs "Guessing" (tertiary dashed).
- Male AGA keeps its published hairs/cm² evidence chart **in addition**, above the
  difference chart. Citation + full disclaimer stay always-visible.
- A generated gouache illustration (`onboard-difference`, Higgsfield nano_banana, 3:2,
  split guessing-fog vs tracked-journal-with-compass) becomes the card's header banner
  (full-width, ~140pt, rounded top corners). It is decorative and honest — no
  hair-regrowth imagery, no before/after scalp.

## 3. Shedding drag-dial on the Today hero

The hero's falling-hair scene becomes the input (user-confirmed choice):
- `ConditionsHero` gains `xp`/`progressToNext` (item 4) and `onShedSet: ((ShedLevel) -> Void)?`.
- A vertical `DragGesture` on the hero scene: while dragging, a transient local intensity
  (1 − y/height, clamped 0…1) overrides the displayed intensity so `SheddingStatusScene`
  and the band word update live under the finger; band changes tick
  `UISelectionFeedbackGenerator`. On release: `onShedSet(SheddingDial.shedLevel(intensity))`
  + success haptic; transient state clears (display returns to the entry-driven value,
  which now matches).
- Affordance: a small trailing vertical "drag rail" chip (chevron.up + chevron.down +
  "SET" eyebrow) so the gesture is discoverable; when today isn't logged the hero's
  "Not logged" state adds "— drag to set" to the caption.
- `TodayView` implements the callback: upsert today's entry (mutate `todayEntry.shed`
  if an entry exists, else `context.insert(DailyEntry(date: .now, shed:))`). Quiet by
  design — no celebration sheet for a drag-set; queries refresh streak/XP naturally.
- Scroll-conflict rule: the drag activates only on the hero (which sits above the scroll
  content); `DragGesture(minimumDistance: 12)` + only claim vertical drags that START on
  the scene area, so page scrolling initiated below the hero is unaffected. Reduce Motion:
  scene still updates (it already honors reduced motion internally).
- Accessibility: the hero gains `.accessibilityAdjustableAction` mirroring ShedDialField.

## 4. XP on the first dashboard

The hero chip row currently shows streak + level name. Add the actual points:
- `TodayView` already computes XP for `levelName`; hoist to `xpTotal` and pass
  `xp: Int` + `progress: Double` (`GamificationLevel.progressToNext(xp:)`) into
  `ConditionsHero`.
- Chip: "`{xp}` XP · `{levelName}`" with a 16pt circular progress ring (accent on
  accentSoft track) showing progress to the next level. `.contentTransition(.numericText())`
  on the XP number so drag-logging visibly bumps it.
- Effort-only rule untouched — display only, no new awards. XP never shown negative.

## Non-goals
- No schema changes anywhere. No new questions in LogSheet. No paywall copy changes
  beyond adding the chart/banner. RiskArc's old shape code is deleted with it.

## Execution
Three Sonnet tracks over disjoint files (same discipline as round 1):
A) `OnboardingComponents.swift` (RiskGauge) + `OnboardingFlow.swift` (familyStep context line);
B) `ProjectionModel.swift` (differenceCurve + tests) + `OnboardingPlanStep.swift` (banner + chart);
C) `TodayTiles.swift` (hero drag + XP chip) + `TodayView.swift` (upsert + xp hoist).
Fable: generate/pick the banner asset, integrate, build, test, simulator-verify, commit.
