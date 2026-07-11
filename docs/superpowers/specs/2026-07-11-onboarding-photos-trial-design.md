# Onboarding polish + Photos tab + 3-day free trial — Design (2026-07-11)

Five changes. Nearly everything reuses components that already ship, so risk is low.

## 1. "What are you noticing?" (concern step) — plainer + clearer demos

- **Language**: shorten each `HairCondition.plainSummary` to one plain clause and each
  `demoCaption` to a short "What you're seeing:" line. New copy (exact) in the plan.
  Keep `plainTitle` (already plain). Head copy unchanged.
- **Animations**: the per-condition `ConditionDemo` demos stay canvas-based (motion reads
  better than a static image here), but the two weakest get clarified:
  - `PatchDemoView` (alopecia areata): a clear, smooth **round bald patch** that fades in
    over a field of evenly rooted strands, holds, then regrows — the strands *inside* the
    circle disappear (not just dim) so the patch is unmistakable.
  - `FlakeDemoView` (seborrheic dermatitis): larger, more legible flakes detaching from a
    clearer scalp arc, with the warm itch blush a touch stronger.
  Leave `FallingHairView` (TE), `DensityFadeView` (AGA), `TractionDemoView`, `CompassDemoView`.
- No Higgsfield image on this step (animation is the point).

## 2. Scalp feel + Stress & sleep → log-style scrubbers

Replace the tappable `BandChipRow`s with the app's own `LivingGauge` scrubber — the same
control the daily **log sheet** uses — so onboarding and logging share one interaction
grammar ("similar to the log in").

- **Scalp feel step (6)** wraps its content in a `ScrollView` and shows three `LivingGauge`s,
  mirroring the log sheet's scalp gauges exactly:
  - Oiliness — `bandCount: 4`, `OilMotif`, zones `["NORMAL","SLIGHT","OILY","VERY"]`.
  - Flaking — `bandCount: 4`, `FlakeMotif`, zones `["NONE","POWDERY","VISIBLE","ADHERENT"]`.
  - Itch — `bandCount: 4`, `ItchMotif`, zones `["NONE","MILD","MODERATE","MARKED"]`.
- **Stress & sleep step (7)** shows two `LivingGauge`s:
  - Sleep quality — `bandCount: 5`, `SleepMotif`, ends `("POOR","DEEP")`.
  - Stress — `bandCount: 5`, `StressMotif`, ends `("CALM","HIGH")`.
- State becomes `@State` `CGFloat` intensities (0…1). `finish()` converts to the ints
  `OnboardingSeed.dayOneEntry` already takes, via `GaugeBand.index`:
  oiliness/flaking/itch = `GaugeBand.index(i, count: 4)`; stress/sleepQuality =
  `GaugeBand.index(i, count: 5) + 1`. Caption closures reuse the log sheet's copy shape.
- Remove `BandChipRow` (now unused — only these two steps referenced it).
- Reduce Motion + haptics already handled inside `LivingGauge`.

## 3. Habits illustration — hair dryer, not iron

`onboard-habits` imageset already re-generated (Higgsfield) to a hair dryer + braided
strand + dye bottle among sprigs, replacing the flat iron. Asset swapped; no code change.

## 4. Photos tab improvements

Focused, high-value additions to `PhotosView` (+ one small new detail view):
- **Coverage on region chips**: a small filled copper dot on any region that already has
  ≥1 photo, so the user sees their coverage at a glance across the 5 regions.
- **Progress summary line** under the header: "N photos · M of 5 regions · last capture
  {relative}" (12pt secondary), or an invitation when empty. Recency without guilt.
- **Tap-to-view**: tapping a grid tile opens a full-screen `PhotoDetailView` sheet — the
  image large on canvas, capture date, region, and the standardization metadata (lighting/
  distance/parting/wet), plus a Delete button. Today a photo can only be deleted via a
  hidden context menu and never viewed large; this is the real gap.
- Keep the compare slider and empty state as-is.

## 5. 3-day free trial (StoreKit intro offer)

**Plan doc** `docs/superpowers/plans/2026-07-11-free-trial-rollout.md` covers the App Store
Connect side (the real trial is configured there — one introductory offer per subscription
group, "Free" payment mode, 3-day duration; a user is eligible once per group). Code side,
implemented now:
- `HairCompass.storekit`: add an `introductoryOffer` (paymentMode `free`, `P3D`, one period)
  to BOTH the monthly and yearly subscriptions, so trials work in the simulator.
- `PurchaseService`: expose `introOffer(for:) -> Product.SubscriptionOffer?` and
  `isEligibleForIntro(_:) async -> Bool` (via `Product.SubscriptionInfo.isEligibleForIntroOffer`),
  plus a `trialDescriptor(for:) -> String?` ("3-day free trial, then {price}/{period}").
- `OnboardingPlanStep` + `ProGate`: when the product has an intro offer and the user is
  eligible, the primary CTA reads "Start 3-day free trial" with honest subtext
  "then {price}, cancel anytime — no charge for 3 days"; when not eligible it falls back to
  today's "Start with yearly — {price}/year". "Continue free" stays equally prominent. No
  countdown, no fake scarcity — the research doc's honesty rules hold.
- Purchase flow is unchanged (`product.purchase()` applies the eligible intro offer
  automatically). `hasPro` already reflects the entitlement during the trial.

**Honesty guardrails** (from `docs/research/2026-07-11-engagement-science.md`): the trial is
disclosed as a trial, the post-trial price is always shown next to the CTA, cancel-anytime is
stated, and the free path is never hidden.

## Tests

- `PurchaseService.trialDescriptor` formatting (unit test with a synthesized period/price is
  hard without StoreKit; instead unit-test the pure period→string helper if extracted).
- Onboarding seeding still lands all answers (existing `OnboardingUpgradeTests` — verify the
  intensity→int conversion produces the expected bands; add a `GaugeBand.index` mapping test).
- No new model/schema changes.

## Execution

Three Sonnet tracks (disjoint files): A onboarding (concern + scrubbers), B Photos, C trial.
Fable integrates, builds, tests, screenshots, commits.
