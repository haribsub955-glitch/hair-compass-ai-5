# Onboarding Upgrade — Design (2026-07-11)

Seven first-run improvements on branch `rebuild/clinical-minimal`. The onboarding grows from
9 to 14 screens, gains a paywall and a HealthKit ask, and hands off to a first-launch tutorial.

## Goals (from the request)

1. Keyboard appears automatically on the name step.
2. The pattern/condition step is easier to understand — plainer language, better animation.
3. Replace the schematic "gender" heads on the sex step with generated gouache illustrations
   (Higgsfield), matching the Clinical design system (ivory / copper / umber).
4. More "status" questions (oiliness, scalp symptoms, stress/sleep, recent triggers) so the
   user feels understood — and so the paywall projection is personalized.
5. End of onboarding: offer the Pro subscription with a *scientifically honest* projected
   view of what tracking + consistency gets them. No deception, no fake numbers.
6. A tutorial on first open, shown automatically once, right after onboarding.
7. Ask to connect Apple Health during onboarding; keep/strengthen the Trends fallback button.

## New step order (14 screens, index 0–13)

| # | Step | Status |
|---|------|--------|
| 0 | Welcome | unchanged |
| 1 | Name | + auto-focus keyboard, `.submitLabel(.continue)`, submit advances when valid |
| 2 | Biological sex | schematic replaced by generated pattern illustrations, simpler copy |
| 3 | Age band | unchanged |
| 4 | What you're noticing (condition) | plain-language titles, clinical name demoted to caption, per-condition demo animations |
| 5 | Shedding dial | unchanged |
| 6 | **NEW** Scalp feel | oiliness 0–3 segmented + flaking 0–3 + itch 0–3 chip rows |
| 7 | **NEW** Stress & sleep | stress 1–5, sleep quality 1–5 |
| 8 | **NEW** Recent triggers | multi-select TriggerType (or "none"); explains the 2–3-month TE lag |
| 9 | Family history | unchanged |
| 10 | Habits (tight styles / heat / chemical) | unchanged |
| 11 | **NEW** Connect Apple Health | benefits list + `requestAuthorization()`; "Not now" secondary |
| 12 | **NEW** Your plan (paywall) | projection + Pro offer; "Continue free" always visible |
| 13 | Finale | now mentions the tutorial handoff |

`finish()` day-one seeding extends from shed-only to a full `DailyEntry(shed, oiliness,
flaking, itch, stress, sleepQuality)`, plus one `TriggerEvent` per selected trigger. The
seeding is extracted to a pure, testable helper. No schema changes to `Profile` — answers
land in `DailyEntry`/`TriggerEvent`, which the app already trends.

## Item 2 — pattern clarity

- `HairCondition` gains `plainTitle` (new property; existing `title`/`shortLabel` untouched
  because charts and Care use them): e.g. "Gradual thinning in a pattern",
  "Sudden shedding all over", "Smooth round patches", "Loss where hair is pulled tight",
  "Flaky, itchy scalp", "Not sure yet". Summaries rewritten in plain language.
- Row layout: plain title primary, clinical name as small secondary text.
- `ConditionDemo` gets real per-condition animations instead of a generic pulsing SF symbol:
  - alopeciaAreata → `PatchDemoView`: top-down head with a soft patch that appears and fades.
  - traction → `TractionDemoView`: hairline strand pulled taut, tension released cyclically.
  - seborrheicDermatitis → `FlakeDemoView`: soft falling flakes over a scalp arc.
  - unsure → compass-needle motif (brand tie-in).
  - telogenEffluvium keeps `FallingHairView`, androgenetic keeps `DensityFadeView`.
- One caption line under the demo: "What you're seeing: …" in plain words.
- All demos respect Reduce Motion (static end-state frame).

## Item 3 — sex-step illustrations

Generated with Higgsfield `nano_banana_pro` (1:1, 1k): top-down male head with Norwood
M-recession + crown wash; top-down female head with widening Ludwig part. Muted ivory/copper
gouache to match `Clinical`. Stored as `onboard-pattern-male` / `onboard-pattern-female`
imagesets. `StagingScalePreview` shows the image in a rounded card with a crossfade on sex
change; the caption ("NORWOOD SCALE — assesses the hairline and crown") stays. Copy simplified:
"Men and women thin in different patterns — this picks the right map for yours."

## Item 5 — honest paywall (`OnboardingPlanStep`)

**Honesty rules (non-negotiable):**
- Tracking doesn't grow hair; consistency with evidence-based treatment does. The pitch is
  about adherence, early signal detection, and objective photo comparison.
- The projection chart is labeled "Illustrative — published clinical averages, not a
  prediction of your results. Individual results vary."
- Numbers come from `docs/TrackingSpec.md` (e.g. combination therapy ≈ +29.7 hairs/cm² at
  24 weeks in men, network meta-analysis; treatments need 3–6 months; TE recovery windows).
- No countdown timers, no fake discounts, no "93% of users saw regrowth" fabrications.
- "Continue free" is a visible, same-screen button. Restore purchases link present.

**Components:**
- `Service/PurchaseService.swift` — StoreKit 2, `@MainActor @Observable` (matches this
  branch's service style). Product IDs `com.harib.haircompass.pro.monthly` / `.yearly`
  (subscription group 21442176, same as main branch). `hasPro` from
  `Transaction.currentEntitlements`; transaction-update listener; `purchase()`, `restore()`.
  Injected via `.environment()` from RootView.
- `ProjectionModel` — pure struct: given condition/sex, returns 24-week curve points
  ("with a consistent, evidence-based plan" vs "no plan / not tracked" = flat-to-declining
  *dashed uncertainty band*, not a fabricated decline), plus the citation line. Unit-tested.
- `HairCompass.storekit` config file for local testing. UI degrades gracefully when products
  don't load (hides price buttons, keeps Continue free).
- Gating of features by `hasPro` is deliberately out of scope — this delivers the offer and
  the entitlement plumbing.

## Item 6 — first-launch tutorial (`TutorialOverlay`)

- Shown automatically once: `@AppStorage("hasSeenTutorial")`, triggered in RootView when
  onboarding completes (or at launch if onboarded but never seen). Ritual roll is suppressed
  while the tutorial is pending so covers never contend.
- ~5 cards anchored above the tab bar; advancing switches the live tab underneath
  (Today → Trends → Plan → Labs → Photos) so the user sees the real screens. Copy: one line
  of "what you do here". Skip button on every card. Reduce Motion honored.

## Item 7 — Apple Health

- Onboarding step 11 requests authorization via the existing `HealthKitService` (already in
  the environment); on grant it immediately `refreshSnapshot`s so Trends has data on day one.
- Trends fallback: `BodySignalsDashboard` already shows "Connect Apple Health" when
  unauthorized — verified kept; add an explicit "Update from Health" refresh affordance
  (with last-updated timestamp) when authorized, and refresh right after a grant from Trends.
- Entitlement + `NSHealthShareUsageDescription` already present. No Info.plist changes.

## Tests

- `OnboardingFlow.initialStep` clamp and `total` updated; UITests re-checked (first-run
  name-step test and replay test must still pass; add ids for new steps).
- New Swift Testing units: `ProjectionModel` (curve shape, citation non-empty, no negative
  values), day-one seeding helper (all answers land on the entry), `HairCondition.plainTitle`
  exhaustiveness.

## Execution

Fable plans/integrates; three Sonnet subagents implement in parallel (disjoint files):
A) OnboardingFlow overhaul (items 1, 2, 4, 7-step, renumbering, image wiring);
B) PurchaseService + ProjectionModel + paywall step + storekit config + unit tests;
C) TutorialOverlay + RootView wiring + Trends refresh button.
Fable generates the Higgsfield assets, integrates, builds, runs the suite, launches the
simulator for visual verification, then commits.
