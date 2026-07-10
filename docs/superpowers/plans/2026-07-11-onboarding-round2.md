# Onboarding Round 2 + Living Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the family-risk gauge, add an honest tracked-vs-guessing graph + gouache banner to the paywall, make the Today hero a drag-to-log shedding dial, and surface XP points on the dashboard.

**Architecture:** Three parallel tracks with disjoint file ownership, interfaces frozen here. Spec: `docs/superpowers/specs/2026-07-11-onboarding-round2-design.md` (user-confirmed choices: hero drag-dial; "high bar" = risk gauge).

**Tech Stack:** SwiftUI, SwiftData, Swift Charts, Swift Testing. Same global constraints as `docs/superpowers/plans/2026-07-11-onboarding-upgrade.md`: Clinical tokens only, Reduce Motion honored, honesty rules on anything paywall-facing, **agents do not run xcodebuild and do not git commit**, quote all paths.

The asset `onboard-difference` (3:2 gouache split-panel) already exists in Assets.xcassets.

---

### Task A: RiskGauge (family step)

**Files (Track A owns exclusively):**
- Modify: `Hair Compass AI 5/Feature/Onboarding/OnboardingComponents.swift` (replace `RiskArc`)
- Modify: `Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift` (`familyStep` only)

**Interfaces:**
- Produces: `RiskGauge(value: Double)` (0…1). Delete `RiskArc` (verify no other callers with grep first; onboarding's `familyStep` is the only one today).

- [ ] **A1:** Build `RiskGauge` in OnboardingComponents.swift per spec §1: ~230×130pt, 180° arc, 14pt stroke; track in `Clinical.hairline`, value fill an `AngularGradient` accentSoft→accent trimmed to `value` with `.spring(response: 0.6, dampingFraction: 0.8)`; a 2pt copper needle (rounded capsule, pivot at arc center) rotating from −90°…+90° to the value with the same spring; band labels LOW/RAISED/HIGH/HIGHEST placed around the arc (`Clinical.eyebrow(9)`, tertiary; the active band — derived from the same thresholds as the old RiskArc label (`<0.15`, `<0.5`, `<0.8`, else) — rendered in accent + semibold); center readout of the active band word (`Clinical.headline(22)`, ink) over "relative odds" (`Clinical.eyebrow(9)`, tertiary). Reduce Motion: `nil` animation (position jumps). `.accessibilityHidden(true)` (the option buttons below carry the semantics).
- [ ] **A2:** In `familyStep`, keep `RiskGauge(value: riskValue)` where RiskArc was, and add the switching context line under the gauge (12pt, `Clinical.secondary`, center, `.contentTransition(.opacity)`), copy exactly per spec §1 (none/extended/oneParent/bothParents lines, each ending "context, not a prediction." except the baseline line). Keep step copy and options untouched otherwise.

### Task B: Difference graph + banner (plan step)

**Files (Track B owns exclusively):**
- Modify: `Hair Compass AI 5/Model/ProjectionModel.swift`
- Modify: `Hair Compass AI 5/Feature/Onboarding/OnboardingPlanStep.swift`
- Modify: `Hair Compass AI 5Tests/ProjectionModelTests.swift` (append tests)

**Interfaces:**
- Produces on `ProjectionModel`: `struct DifferencePoint: Equatable { let week: Int; let withTracking: Double; let without: Double }` and `let differenceCurve: [DifferencePoint]`, populated for EVERY condition×sex by `make(...)`.

- [ ] **B1:** Add the universal curve. Weeks `[0, 4, 8, 12, 16, 20, 24]`; `withTracking = smoothstep(week/24)` (reuse the existing private `easeIn`); `without = 0.12 + 0.03 * sin(Double(week))` clamped to `0…0.15` (low, flat, slightly wavy — visibly "noise", never negative). Same `disclaimerText` continues to apply.
- [ ] **B2:** Append Swift Testing cases to ProjectionModelTests.swift: every condition×sex has a 7-point `differenceCurve`; `withTracking` is monotonic non-decreasing ending at 1.0 (±0.001); every `without` ≤ 0.15 and ≥ 0; week span is 0…24.
- [ ] **B3:** In OnboardingPlanStep's projection card: (1) add the banner — `Image("onboard-difference").resizable().scaledToFill()` full-card-width, height 132, clipped with the card's top corners, above the headline; (2) render the difference chart for EVERYONE (below the male-AGA evidence chart when that exists): Swift Charts with two `LineMark` series — "Tracking daily" (`Clinical.accent`, 2.5pt, `.monotone`) and "Guessing" (`Clinical.tertiary`, dashed `[4,4]`, `.monotone`), legend as small inline swatch rows (not `.chartLegend`), y-axis hidden except the label "Signal clarity (illustrative)" (11pt tertiary, above or as `.chartYAxisLabel`), x-axis marks at weeks 0/12/24 ("W0" style). Height ~140. The chart must visually read at a glance: copper line rises, grey dashed line stays flat-low.
- [ ] **B4:** Keep citation + disclaimer always visible below the charts (unchanged). No copy changes elsewhere; purchase-button and free-path behavior untouched.

### Task C: Hero shed drag-dial + XP chip (Today)

**Files (Track C owns exclusively):**
- Modify: `Hair Compass AI 5/Feature/TodayTiles.swift` (`ConditionsHero`)
- Modify: `Hair Compass AI 5/Feature/TodayView.swift`

**Interfaces:**
- `ConditionsHero` gains parameters (all with the existing call-site updated in TodayView): `xp: Int`, `levelProgress: Double` (0…1), `onShedSet: ((ShedLevel) -> Void)? = nil`. Existing params unchanged.
- Consumes: `SheddingDial.band(_:)/shedLevel(_:)/bandCaption(_:)` (OnboardingComponents), `GamificationLevel.progressToNext(xp:)` (Gamification.swift — read to confirm the exact signature before use), `XP.total(...)` already computed in TodayView.

- [ ] **C1: Drag-to-set.** In `ConditionsHero`: add `@State private var dragIntensity: CGFloat?` and `@GestureState`-free vertical `DragGesture(minimumDistance: 12)` attached to the hero's scene area only. While dragging: `dragIntensity = clamp(1 − location.y/height)`; the displayed intensity becomes `dragIntensity ?? heroIntensity`, so `SheddingStatusScene` and the band word follow the finger live (band word from `SheddingDial.bandCaption(dragIntensity).0` while dragging); tick `UISelectionFeedbackGenerator` on band change. On `.onEnded`: call `onShedSet?(SheddingDial.shedLevel(intensity))`, `UINotificationFeedbackGenerator().notificationOccurred(.success)`, clear `dragIntensity`. If `onShedSet == nil`, attach no gesture (hero stays passive, e.g. previews).
- [ ] **C2: Affordance.** A slim trailing vertical rail chip inside the hero (top-right of the scene, under the profile button row): chevron.up over "SET" eyebrow over chevron.down, 10pt icons, tertiary on `Clinical.surface.opacity(0.82)` capsule with hairline border (mirrors ShedDialField's "Live portrait" chip styling). When `hasLoggedToday == false`, the existing "Not logged" caption gains "— drag to set". `.accessibilityElement` on the hero scene with `.accessibilityAdjustableAction` incrementing/decrementing the band and calling `onShedSet` (mirror ShedDialField's implementation).
- [ ] **C3: Upsert in TodayView.** Pass the new params: `xp: xpTotal`, `levelProgress: GamificationLevel.progressToNext(xp: xpTotal)`, and `onShedSet: { level in ... }` which mutates `todayEntry?.shed = level` when today's entry exists, else `context.insert(DailyEntry(date: .now, shed: level))`. Hoist the existing XP computation: `private var xpTotal: Int { XP.total(entries:..., doses:..., photos:..., labs:..., triggers:...) }` and derive `levelName` from it (one computation, two uses). No celebration sheet from drag-sets.
- [ ] **C4: XP chip.** In the hero's chip row (beside streak/level): show `"\(xp) XP"` with `.contentTransition(.numericText())` (`.animation(.easeOut(duration: 0.3), value: xp)`) and a 16pt `Circle().trim(to: levelProgress)` accent-on-accentSoft mini ring before the level name. Keep the row to one line — if tight, the level name and XP live in ONE chip: `[ring] 240 XP · Sapling`.
- [ ] **C5: Scroll safety.** Verify the gesture only claims drags that begin on the hero scene (the scene sits at the top; `minimumDistance: 12` + `DragGesture` on that subview is sufficient — do NOT use `.highPriorityGesture` on the whole hero, and do not attach anything to the ScrollView). Mention in your report how you verified the reasoning.

### Task D (orchestrator): integrate, build, test, verify, commit
- [ ] Build; run unit tests; force-screenshot family step (HC_ONBOARD + HC_ONBOARD_STEP 9) and plan step (12); fresh-launch Today for hero XP chip; drag can't be simulated headlessly — verify via code review + accessibility action path; commit per track.
