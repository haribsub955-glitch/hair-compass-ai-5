# Onboarding polish + Photos + Free trial — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simpler/clearer "what are you noticing" step, log-style scrubbers for scalp/stress/sleep, hair-dryer habits art (done), Photos-tab improvements, and a 3-day free trial.

**Architecture:** Three parallel Sonnet tracks, disjoint files. Spec: `docs/superpowers/specs/2026-07-11-onboarding-photos-trial-design.md`. Trial rollout playbook: `docs/superpowers/plans/2026-07-11-free-trial-rollout.md`. Same global constraints as prior plans (Clinical tokens, Reduce Motion, honesty rules on paywall, **agents do not run xcodebuild / git**, Swift Testing, quote paths). The `onboard-habits` asset is already swapped to the hair dryer — no track owns it.

**No cross-track shared symbols** — the three tracks touch fully disjoint files.

---

### Task A: Onboarding — concern clarity + log-style scrubbers

**Files (owns exclusively):** `Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift`, `Hair Compass AI 5/Feature/Onboarding/OnboardingComponents.swift`, `Hair Compass AI 5/Model/Enums.swift` (copy strings only).

- [ ] **A1: Plainer condition copy.** In `Enums.swift`, shorten `HairCondition.plainSummary` and `demoCaption` (keep `plainTitle`, `title`, `shortLabel`):

```swift
var plainSummary: String {
    switch self {
    case .androgenetic: return "Slow thinning at the hairline, crown, or part — the most common kind."
    case .alopeciaAreata: return "Smooth, coin-sized bald patches that can show up fast."
    case .telogenEffluvium: return "Lots of extra shedding all over, often after stress or illness."
    case .traction: return "Thinning where hair is pulled tight — braids, buns, ponytails."
    case .seborrheicDermatitis: return "A flaky, itchy, sometimes red scalp."
    case .unsure: return "Not sure yet? We'll track broadly until a pattern shows."
    }
}
var demoCaption: String {
    switch self {
    case .androgenetic: return "What you're seeing: the crown slowly thinning."
    case .alopeciaAreata: return "What you're seeing: a smooth patch appear, then regrow."
    case .telogenEffluvium: return "What you're seeing: extra hairs shedding all over."
    case .traction: return "What you're seeing: a strand strained where it's pulled."
    case .seborrheicDermatitis: return "What you're seeing: flakes lifting from an itchy scalp."
    case .unsure: return "We'll help you find your pattern as you track."
    }
}
```

- [ ] **A2: Clearer demos.** In `OnboardingComponents.swift`, rework `PatchDemoView` and `FlakeDemoView` (leave the others). Study the existing `DensityFadeView`/`FlakeMotif` idiom.
  - `PatchDemoView`: draw an even grid of short rooted strands (like `DensityFadeView`), plus one off-center circle; strands whose center is inside the circle **fade fully out** (alpha → ~0) over a ~2.2 s ease, hold ~1 s, regrow, loop (~6 s cycle). The empty circle must read as a clean bald patch, not just dimmer strands. Reduce Motion: draw the patch at its half-faded steady state, static.
  - `FlakeDemoView`: a clearer scalp arc across the top third (a filled `Clinical.secondary.opacity(0.15)` band), larger flakes (3–5 pt rounded copper/ivory), a slightly stronger warm blush (`Clinical.warning.opacity(0.16)`) pulsing under the arc. Reduce Motion: static mid-frame.

- [ ] **A3: Scalp feel step → LivingGauge.** Replace `scalpFeelStep`'s `BandChipRow`s. Add `@State` intensities `oilI/flakeI/itchI: CGFloat = 0` (replacing the `oiliness/flaking/itch` Ints — see A5 for the finish() conversion). Wrap content in a `ScrollView(showsIndicators: false)`:

```swift
private var scalpFeelStep: some View {
    VStack(spacing: 0) {
        head("Your scalp", "How does your scalp feel?", "Drag each — the preview reacts as you go.")
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                LivingGauge(title: "Oiliness", intensity: $oilI, bandCount: 4,
                            tint: Clinical.accent, zones: ["NORMAL","SLIGHT","OILY","VERY"], ends: nil,
                            caption: { i in Self.scalpCaption(i, count: 4,
                                titles: ["Balanced","Slightly oily","Oily","Very oily"],
                                subs: ["comfortable","a little greasy","greasy by midday","greasy fast"]) }) { i in OilMotif(intensity: i) }
                LivingGauge(title: "Flaking", intensity: $flakeI, bandCount: 4,
                            tint: Clinical.accent, zones: ["NONE","POWDERY","VISIBLE","ADHERENT"], ends: nil,
                            caption: { i in Self.scalpCaption(i, count: 4,
                                titles: ["No flaking","Powdery","Visible flakes","Sticky flakes"],
                                subs: ["clear","fine dust","you can see it","clings to the scalp"]) }) { i in FlakeMotif(intensity: i) }
                LivingGauge(title: "Itch", intensity: $itchI, bandCount: 4,
                            tint: Clinical.accent, zones: ["NONE","MILD","COMES & GOES","CONSTANT"], ends: nil,
                            caption: { i in Self.scalpCaption(i, count: 4,
                                titles: ["No itch","Mild","Comes and goes","Constant"],
                                subs: ["clear","barely there","on and off","hard to ignore"]) }) { i in ItchMotif(intensity: i) }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        }
        primary("Continue") { next() }
    }
}

/// Shared caption builder: band index → (title, subtitle) from parallel arrays.
private static func scalpCaption(_ i: CGFloat, count: Int, titles: [String], subs: [String]) -> (String, String) {
    let b = GaugeBand.index(i, count: count)
    return (titles[b], subs[b])
}
```

- [ ] **A4: Stress & sleep step → LivingGauge.** Replace `stressSleepStep`'s chips. Add `@State` `sleepI/stressI: CGFloat = 0.5`. Two gauges in a `ScrollView`:

```swift
LivingGauge(title: "Sleep quality", intensity: $sleepI, bandCount: 5,
            tint: Clinical.sage, zones: nil, ends: ("POOR","DEEP"),
            caption: { i in Self.fiveCaption(i,
                titles: ["Poor","Fair","OK","Good","Great"],
                subs: ["restless nights","broken sleep","average","mostly solid","deeply rested"]) }) { i in SleepMotif(intensity: i) }
LivingGauge(title: "Stress", intensity: $stressI, bandCount: 5,
            tint: Clinical.accent, zones: nil, ends: ("CALM","HIGH"),
            caption: { i in Self.fiveCaption(i,
                titles: ["Very low","Low","Medium","High","Very high"],
                subs: ["calm","steady","some pressure","stretched","overwhelmed"]) }) { i in StressMotif(intensity: i) }
```

with `fiveCaption` analogous to `scalpCaption` (count 5). Head: `head("Lifestyle", "Stress and sleep lately?", "Both can show up in your hair 2–3 months later.")`.

- [ ] **A5: finish() conversion.** Where `finish()` builds the seed, convert intensities to the ints `OnboardingSeed.dayOneEntry` takes:
```swift
oiliness: GaugeBand.index(oilI, count: 4),
flaking:  GaugeBand.index(flakeI, count: 4),
itch:     GaugeBand.index(itchI, count: 4),
stress:   GaugeBand.index(stressI, count: 5) + 1,
sleepQuality: GaugeBand.index(sleepI, count: 5) + 1
```
Delete the old `oiliness/flaking/itch/stress/sleepQuality` Int `@State`. Confirm `OnboardingSeed.dayOneEntry` signature is unchanged; only the call site changes.

- [ ] **A6: Remove `BandChipRow`** from `OnboardingComponents.swift` (now unreferenced — verify with grep first).

- [ ] **A7: Test.** Add to the existing `OnboardingUpgradeTests.swift` a `GaugeBand.index` mapping test: `index(0, 4)==0`, `index(1, 4)==3`, `index(0.5, 5)==2`, and that `+1` yields the 1–5 range for stress/sleep. (Pure; no view instantiation.)

### Task B: Photos tab improvements

**Files (owns exclusively):** `Hair Compass AI 5/Feature/PhotosView.swift`, new `Hair Compass AI 5/Feature/PhotoDetailView.swift`.

- [ ] **B1: Region-chip coverage dots.** In `regionPicker`, overlay a 6pt `Clinical.accent` filled circle on the top-trailing of any chip whose region has ≥1 photo. Compute `regionsWithPhotos: Set<PhotoRegion>` from `photos`. Dot hidden on the selected chip's own state only if it muddies contrast — keep it visible but use `Clinical.surface` ring. Accessibility: append ", has photos" to the chip hint when applicable.

- [ ] **B2: Progress summary line.** Under the `ScreenHeader`, a line (12pt `Clinical.secondary`): when photos exist, `"\(photos.count) photo\(photos.count == 1 ? "" : "s") · \(regionsWithPhotos.count) of 5 regions · last \(latest.createdAt.formatted(.relative(presentation: .named)))"`; when empty, `"Capture your first region to start a comparable series."`. `latest` = `photos.first` (already sorted desc).

- [ ] **B3: PhotoDetailView.** New sheet: large image on `Clinical.canvas` (scaledToFit, rounded, hairline), then the capture date (headline), region title, and a metadata row for any non-empty of lighting/distance/parting + wet flag (small labeled chips using `Clinical.eyebrow`), and a destructive "Delete photo" button that removes the file (`PhotoStore.shared.delete`) + `context.delete` then dismisses. `NavigationStack` with a Done cancellation button. Reduce Motion irrelevant (no animation).

```swift
struct PhotoDetailView: View {
    let record: PhotoRecord
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    // ... image + metadata + delete
}
```

- [ ] **B4: Wire tap-to-view.** In `PhotosView.grid`, make each tile a `Button` presenting `PhotoDetailView(record:)` via `@State private var detailRecord: PhotoRecord?` + `.sheet(item:)` (PhotoRecord is a SwiftData `@Model`, already `Identifiable` via `persistentModelID` — use a small `Identifiable` wrapper if needed, or `.sheet(item: $detailRecord)`). Keep the existing context-menu Delete as a shortcut. The detail's `onDelete` clears `detailRecord`.

- [ ] **B5:** No test (pure UI); verified via screenshots at integration.

### Task C: 3-day free trial

**Files (owns exclusively):** `HairCompass.storekit`, `Hair Compass AI 5/Service/PurchaseService.swift`, `Hair Compass AI 5/Feature/Onboarding/OnboardingPlanStep.swift`, `Hair Compass AI 5/Feature/ProGate.swift`.

- [ ] **C1: StoreKit intro offer.** In `HairCompass.storekit`, set each subscription's `introductoryOffer` (currently `null`) to a 3-day free offer:
```json
"introductoryOffer" : {
  "displayPrice" : "0.00",
  "internalID" : "9C1A4E31",   // monthly; use 9C1A4E32 for yearly — must be unique
  "numberOfPeriods" : 1,
  "paymentMode" : "free",
  "subscriptionPeriod" : "P3D"
}
```
(Give each a distinct `internalID`.) Validate the file parses as JSON.

- [ ] **C2: PurchaseService trial API.** Add:
```swift
/// The product's introductory offer, if any (e.g. the 3-day free trial).
func introOffer(for product: Product) -> Product.SubscriptionOffer? {
    product.subscription?.introductoryOffer
}
/// Whether THIS Apple ID can still use the group's intro offer (one per group).
func isEligibleForIntro(_ product: Product) async -> Bool {
    guard let sub = product.subscription else { return false }
    return await sub.isEligibleForIntroOffer
}
/// "3-day free trial, then $4.99/month" — nil when no offer / ineligible handled by caller.
func trialDescriptor(for product: Product) -> String? {
    guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial
    else { return nil }
    let period = offer.period
    let unit: String
    switch period.unit {
    case .day: unit = period.value == 1 ? "day" : "days"
    case .week: unit = period.value == 1 ? "week" : "weeks"
    case .month: unit = period.value == 1 ? "month" : "months"
    case .year: unit = period.value == 1 ? "year" : "years"
    @unknown default: unit = "days"
    }
    return "\(period.value)-\(unit) free trial, then \(product.displayPrice)"
}
```
(Verify `Product.SubscriptionOffer.PaymentMode.freeTrial` and `.period` against the iOS 26.2 SDK `.swiftinterface` before finalizing.)

- [ ] **C3: Paywall CTA.** In `OnboardingPlanStep`, the yearly primary button (read the current `buy(yearly)` block first): compute trial eligibility once via a `@State private var yearlyIntroEligible = false` set in a `.task { yearlyIntroEligible = await purchases.isEligibleForIntro(yearly) }` (guard `yearly` non-nil). When eligible AND an intro offer exists, the button label becomes "Start 3-day free trial" and a subtext line reads "then \(yearly.displayPrice)/year · cancel anytime — no charge for 3 days" (11pt `Clinical.secondary`). Otherwise keep today's "Start with yearly — {price}/year". Monthly button unchanged. "Continue free" + Restore unchanged. No timers/scarcity.

- [ ] **C4: ProGate CTA.** Same treatment on `ProGate`'s primary purchase button (read it first): show the trial descriptor when eligible. Keep it minimal — the gate's job is unchanged, only the CTA copy adapts.

- [ ] **C5:** No unit test for StoreKit-bound code (can't synthesize `Product` offline); the trial descriptor's period→unit mapping is trivial and covered by review. Orchestrator verifies the `.storekit` change loads and the CTA renders (screenshot with the config selected, if feasible).

### Task D (orchestrator): integrate, build, test, verify, commit
- [ ] Build; unit tests; screenshot onboarding steps 4 (concern), 6 (scalp scrubbers), 7 (stress/sleep), 10 (hair-dryer art); Photos tab (coverage dots + summary) and a PhotoDetailView; verify `.storekit` parses; commit per track + the two plan/spec docs + the swapped asset.
