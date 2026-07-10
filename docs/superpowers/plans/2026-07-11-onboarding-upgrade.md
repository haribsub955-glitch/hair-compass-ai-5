# Onboarding Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild first-run onboarding into a 14-step flow with auto-keyboard, plain-language patterns, generated pattern art, richer status questions, an honest Pro paywall, a first-launch tutorial, and a HealthKit ask.

**Architecture:** Three parallel tracks with **disjoint file ownership** (A: onboarding flow; B: commerce + paywall; C: tutorial + trends/root wiring). Interfaces between tracks are frozen in this plan. The orchestrator integrates, builds, tests, and commits.

**Tech Stack:** SwiftUI, SwiftData, StoreKit 2, HealthKit, Swift Testing (`@Test`/`#expect`, NOT XCTest), Swift Charts. iOS 26.2 target, Xcode project with filesystem-synchronized groups (new files are picked up automatically — no pbxproj edits).

## Global Constraints

- Branch: `rebuild/clinical-minimal`. Paths contain spaces — always quote.
- Design tokens come from `Hair Compass AI 5/Design/Clinical.swift` (`Clinical.canvas/surface/ink/secondary/tertiary/accent/accentSoft/hairline/sage/warning`, `Clinical.headline()/eyebrow()`, `ClinicalButtonStyle`, `Eyebrow`). No hardcoded colors.
- Every animation must honor `@Environment(\.accessibilityReduceMotion)` (static end-state when reduced).
- Honesty rules for anything premium-facing: no fabricated statistics, no countdown/urgency, disclaimer "Illustrative — published clinical averages, not a prediction of your results." on any projection, visible "Continue free" path.
- **Agents do NOT run xcodebuild and do NOT git commit** — the orchestrator builds, fixes, tests, and commits at integration (parallel agents share one working tree).
- Unit tests go in NEW files inside `Hair Compass AI 5Tests/` using Swift Testing with `@testable import Hair_Compass_AI_5`.
- The assets `onboard-pattern-male` / `onboard-pattern-female` already exist in `Assets.xcassets`.

---

### Task A: Onboarding flow overhaul (items 1, 2, 3-wiring, 4, 7-step)

**Files (Track A owns these exclusively):**
- Modify: `Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift`
- Modify: `Hair Compass AI 5/Feature/Onboarding/OnboardingComponents.swift`
- Modify: `Hair Compass AI 5/Feature/Onboarding/StagingScalePreview.swift`
- Modify: `Hair Compass AI 5/Model/Enums.swift` (additive only)
- Create: `Hair Compass AI 5/Feature/Onboarding/OnboardingSeed.swift`
- Create: `Hair Compass AI 5Tests/OnboardingUpgradeTests.swift`
- Modify (only if a test breaks): `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift`

**Interfaces:**
- Consumes: `OnboardingPlanStep(profile: Profile, onContinue: @escaping () -> Void)` — Track B's view, referenced as `case 12`. Do not create this type; reference it. The tree may not compile until B lands — that is expected; do not build.
- Consumes: `HealthKitService` via `@Environment(HealthKitService.self)` (Track C injects it onto the onboarding cover content), `healthKit.requestAuthorization()`, `healthKit.refreshSnapshot(context:)`, `healthKit.authorization.isUsable`.
- Produces: 14-step flow (indices below, frozen); `HairCondition.plainTitle`; `OnboardingSeed.buildDayOneEntry(...)`.

**Step order (frozen):** 0 welcome · 1 name · 2 sex · 3 age · 4 concern · 5 shedding · 6 scalp feel · 7 stress & sleep · 8 recent triggers · 9 family · 10 habits · 11 health connect · 12 plan/paywall · 13 finale. `total = 14`; `initialStep` clamp becomes `min(13, n)`.

- [ ] **A1: Name step keyboard.** Add to `OnboardingFlow`:

```swift
@FocusState private var nameFocused: Bool
```

On the name `TextField`: `.focused($nameFocused)`, `.submitLabel(.continue)`, `.onSubmit { if nameValid { next() } }` where `nameValid` is the existing `count >= 2` check. Focus when the step appears (delay lets the transition settle):

```swift
// on the nameStep container
.onAppear {
    Task { try? await Task.sleep(for: .milliseconds(450)); nameFocused = true }
}
```

Also set `nameFocused = false` inside `next()`/`back()` so the keyboard drops when leaving the step.

- [ ] **A2: Plain-language conditions.** In `Enums.swift`, add to `HairCondition` (do NOT touch `title`/`shortLabel` — charts and Care use them):

```swift
var plainTitle: String {
    switch self {
    case .androgenetic: return "Gradual thinning in a pattern"
    case .alopeciaAreata: return "Smooth round patches"
    case .telogenEffluvium: return "Sudden shedding all over"
    case .traction: return "Loss where hair is pulled tight"
    case .seborrheicDermatitis: return "Flaky, itchy scalp"
    case .unsure: return "Not sure yet"
    }
}
var plainSummary: String {
    switch self {
    case .androgenetic: return "Slow thinning at the hairline, crown, or part. The most common kind — driven by genes and hormones."
    case .alopeciaAreata: return "Coin-sized smooth patches that can appear quickly — an immune response."
    case .telogenEffluvium: return "Lots of extra hairs everywhere, often 2–3 months after stress, illness, or a diet change."
    case .traction: return "Thinning at the hairline or part from tight braids, buns, or ponytails."
    case .seborrheicDermatitis: return "Dandruff-like flaking with redness and itch."
    case .unsure: return "No problem — we'll track broadly until a pattern shows."
    }
}
/// One plain line describing what the demo animation is showing.
var demoCaption: String {
    switch self {
    case .androgenetic: return "What you're seeing: strands thinning gradually at the crown."
    case .alopeciaAreata: return "What you're seeing: a smooth patch appearing, then regrowing."
    case .telogenEffluvium: return "What you're seeing: extra hairs falling all over."
    case .traction: return "What you're seeing: a strand strained where it's pulled tight."
    case .seborrheicDermatitis: return "What you're seeing: flakes shedding from an itchy scalp."
    case .unsure: return "We'll help you find your pattern as you track."
    }
}
```

In `concernStep`, rows show `c.plainTitle` primary (15pt medium, ink), `c.title` as small eyebrow-style secondary (10pt, tertiary, uppercased — the clinical name stays visible but demoted), then `c.plainSummary` (12pt secondary). Below the demo card, show `profile.condition.demoCaption` (12pt, secondary, animated `.contentTransition(.opacity)` on change). Head copy becomes: `head("What are you noticing?", "Pick the closest match", "Plain words — the clinical name is underneath. You can change this anytime.")`

- [ ] **A3: Per-condition demo animations.** In `OnboardingComponents.swift`, replace `MotifView` usage inside `ConditionDemo` with dedicated demos (keep `FallingHairView` for `.telogenEffluvium`, `DensityFadeView` for `.androgenetic`):

```swift
struct ConditionDemo: View {
    let condition: HairCondition
    var body: some View {
        switch condition {
        case .telogenEffluvium: FallingHairView(intensity: 0.5)
        case .androgenetic: DensityFadeView()
        case .alopeciaAreata: PatchDemoView()
        case .traction: TractionDemoView()
        case .seborrheicDermatitis: FlakeDemoView()
        case .unsure: CompassDemoView()
        }
    }
}
```

Implement the four new views in the same file, following the existing `MotionTimeline`/`Canvas` idiom (see `DensityFadeView`/`StressStrandView` for the pattern — all `.accessibilityHidden(true)`, all static under Reduce Motion):
  - `PatchDemoView`: a field of short rooted strands (like `DensityFadeView`'s grid); a circular patch (off-center) whose strands fade out and back in on a slow ~6 s cycle — appear → hold → regrow.
  - `TractionDemoView`: 5–6 strands anchored along a hairline arc at the bottom; the outermost strands angle and straighten toward a pull direction on a ~3 s cycle, with tiny stress ticks (short accent-colored dashes) at the anchor of the most-strained strand while taut.
  - `FlakeDemoView`: a scalp arc across the top third; small rounded flakes (2–4 pt) detach and drift down with slight sway; a soft warm blush (`Clinical.warning.opacity(0.12)`) pulses under the arc for the itch/redness.
  - `CompassDemoView`: a thin circle with a copper needle that gently swings and settles — brand tie-in for "not sure yet".

- [ ] **A4: Sex step with generated art.** Rewrite `StagingScalePreview` to show the generated images instead of the schematic (delete the shape-drawing code — `TopDownHeadShape`, `NorwoodZonesShape`, `LudwigZoneShape` — it is being replaced, keep the file lean):

```swift
struct StagingScalePreview: View {
    let sex: BiologicalSex
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isLudwig: Bool { sex == .female }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Image("onboard-pattern-male")
                    .resizable().scaledToFill()
                    .opacity(isLudwig ? 0 : 1)
                Image("onboard-pattern-female")
                    .resizable().scaledToFill()
                    .opacity(isLudwig ? 1 : 0)
            }
            .frame(width: 168, height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
            .shadow(color: Clinical.cardShadow, radius: 10, y: 4)

            VStack(spacing: 3) {
                Text("\(sex.stagingScaleName.uppercased()) SCALE")
                    .font(Clinical.eyebrow(10)).tracking(1.4).foregroundStyle(Clinical.accent)
                Text(isLudwig ? "Thinning shows as a widening part" : "Thinning shows at the hairline and crown")
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isLudwig)
        .accessibilityHidden(true)
    }
}
```

Sex step copy simplifies to: `head("About you", "Your biological sex", "Men and women thin in different patterns — this picks the right map for yours.")`

- [ ] **A5: Three new question steps.** Add `@State` in `OnboardingFlow`: `oiliness = 0`, `flaking = 0`, `itch = 0` (all `Int`, 0–3), `stress = 3`, `sleepQuality = 3` (1–5), `selectedTriggers = Set<TriggerType>()`. Build the steps with a shared chip-row control (add to `OnboardingComponents.swift`):

```swift
/// A labeled row of 4 tappable band chips (e.g. None/Mild/Moderate/Severe). Selection binds 0–3.
struct BandChipRow: View {
    let title: String
    let bands: [String]
    @Binding var value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
            HStack(spacing: 8) {
                ForEach(Array(bands.enumerated()), id: \.offset) { i, band in
                    let on = value == i
                    Button {
                        value = i
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(band)
                            .font(.system(size: 13, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(on ? Clinical.accent : Clinical.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
```

  - **Step 6 scalp feel** — `head("Your scalp", "How does your scalp feel?", "Day to day, on average.")` then three `BandChipRow`s: Oiliness `["Dry", "Balanced", "Oily", "Very oily"]`, Flaking `["None", "A little", "Visible", "Heavy"]`, Itch `["None", "Mild", "Comes and goes", "Constant"]`. Always continuable.
  - **Step 7 stress & sleep** — `head("Lifestyle", "Stress and sleep lately?", "Both can show up in your hair 2–3 months later.")` Two `BandChipRow`-style rows but 5 bands mapping to 1–5 (bind through a local `Binding(get: { stress - 1 }, set: { stress = $0 + 1 })` or add an offset parameter): Stress `["Very low", "Low", "Medium", "High", "Very high"]`, Sleep `["Poor", "Fair", "OK", "Good", "Great"]`.
  - **Step 8 recent triggers** — `head("The last 3 months", "Did any of these happen?", "Shedding often follows a trigger by 2–3 months. Knowing the date makes your chart make sense.")` Multi-select rows over `TriggerType.allCases` (icon `t.symbol`, title `t.title`, checkmark when selected, `Clinical.accentSoft` background when on) plus a final exclusive "None of these" row that clears the set. Continue always enabled.

- [ ] **A6: Health connect step (11).** `head("Automatic signals", "Connect Apple Health?", "Sleep, body weight, and recovery fill in automatically — no typing. You control exactly what's shared, and you can change it anytime in Settings.")` Benefit rows (SF symbol + line, surface cards): `bed.double.fill` "Sleep hours, every night", `figure` "Body weight and BMI", `heart.fill` "Recovery (HRV) as a stress signal". Primary button "Connect Apple Health" → 

```swift
Task {
    await healthKit.requestAuthorization()
    if healthKit.authorization.isUsable { await healthKit.refreshSnapshot(context: context) }
    next()
}
```

Secondary plain button "Not now" (13pt, `Clinical.tertiary`) → `next()`. If `healthKit.authorization` is already `.authorized` or `.unavailable` when the step would show, keep the step but swap the primary CTA to "Continue" (state it plainly: "Health is connected ✓" / on unavailable devices show "Health isn't available on this device"). Add `.accessibilityIdentifier("onboardHealthConnect")` on the primary button.

- [ ] **A7: Day-one seeding.** Create `Hair Compass AI 5/Feature/Onboarding/OnboardingSeed.swift`:

```swift
import Foundation

/// Pure builders for the data onboarding seeds on finish — kept free of SwiftUI/SwiftData
/// context so they are unit-testable.
enum OnboardingSeed {
    /// Day-one entry from the onboarding answers. `stress`/`sleepQuality` are 1–5,
    /// `oiliness`/`flaking`/`itch` are 0–3 bands; everything is clamped defensively.
    static func dayOneEntry(
        shedIntensity: CGFloat,
        oiliness: Int, flaking: Int, itch: Int,
        stress: Int, sleepQuality: Int,
        date: Date = .now
    ) -> DailyEntry {
        DailyEntry(
            date: date,
            shed: SheddingDial.shedLevel(shedIntensity),
            flaking: min(max(flaking, 0), 3),
            erythema: 0,
            itch: min(max(itch, 0), 3),
            sleepQuality: min(max(sleepQuality, 1), 5),
            stress: min(max(stress, 1), 5),
            oiliness: min(max(oiliness, 0), 3)
        )
    }

    /// One TriggerEvent per selected trigger, dated `date` with an onboarding note.
    static func triggerEvents(_ selected: Set<TriggerType>, date: Date = .now) -> [TriggerEvent] {
        selected.sorted { $0.rawValue < $1.rawValue }.map {
            TriggerEvent(type: $0, date: date, note: "Reported during onboarding — happened in the last 3 months.")
        }
    }
}
```

In `finish()`, replace the bare `DailyEntry(date:shed:)` insert with `OnboardingSeed.dayOneEntry(...)` (same has-today guard) and insert `OnboardingSeed.triggerEvents(selectedTriggers)`.

- [ ] **A8: Renumber + finale.** Update `content` switch to the frozen order, `total = 14`, `initialStep` clamp to 13, `case 12: OnboardingPlanStep(profile: profile) { next() }`. Finale sub-copy becomes "Your compass is calibrated. A quick tour starts when you close this." Keep the topBar back button hidden on 0 and 13 (existing `step > 0 && step < total - 1` logic still works). The paywall step must not show a back button either — extend the condition to also exclude `step == 12` (a paywall you can only move forward from or through is the honest shape; "Continue free" is the exit).

- [ ] **A9: Tests.** Create `Hair Compass AI 5Tests/OnboardingUpgradeTests.swift` (Swift Testing):

```swift
import Foundation
import Testing
@testable import Hair_Compass_AI_5

@Test func dayOneEntryCarriesAllAnswers() {
    let e = OnboardingSeed.dayOneEntry(shedIntensity: 0.9, oiliness: 2, flaking: 3, itch: 1, stress: 4, sleepQuality: 2)
    #expect(e.shed == .heavy)
    #expect(e.oiliness == 2); #expect(e.flaking == 3); #expect(e.itch == 1)
    #expect(e.stress == 4); #expect(e.sleepQuality == 2); #expect(e.erythema == 0)
}

@Test func dayOneEntryClampsOutOfRange() {
    let e = OnboardingSeed.dayOneEntry(shedIntensity: 0, oiliness: 9, flaking: -2, itch: 5, stress: 0, sleepQuality: 99)
    #expect(e.oiliness == 3); #expect(e.flaking == 0); #expect(e.itch == 3)
    #expect(e.stress == 1); #expect(e.sleepQuality == 5)
}

@Test func triggerEventsMatchSelection() {
    let events = OnboardingSeed.triggerEvents([.illness, .majorStress])
    #expect(events.count == 2)
    #expect(Set(events.map(\.type)) == Set([TriggerType.illness, .majorStress]))
    #expect(events.allSatisfy { !$0.note.isEmpty })
}

@Test func plainLanguageIsExhaustiveAndDistinct() {
    for c in HairCondition.allCases {
        #expect(!c.plainTitle.isEmpty)
        #expect(!c.plainSummary.isEmpty)
        #expect(!c.demoCaption.isEmpty)
    }
    #expect(Set(HairCondition.allCases.map(\.plainTitle)).count == HairCondition.allCases.count)
}
```

- [ ] **A10: UITests sanity.** Read `Hair_Compass_AI_5UITests.swift`; the first-run test (Begin → `onboardName`) and replay test must remain valid against the new flow. Update only if the new step order breaks an assumption (e.g. `HC_ONBOARD_STEP` bounds).

---

### Task B: PurchaseService, honest paywall, Pro gating

**Files (Track B owns these exclusively):**
- Create: `Hair Compass AI 5/Service/PurchaseService.swift`
- Create: `Hair Compass AI 5/Model/ProjectionModel.swift`
- Create: `Hair Compass AI 5/Feature/Onboarding/OnboardingPlanStep.swift`
- Create: `Hair Compass AI 5/Feature/ProGate.swift`
- Create: `HairCompass.storekit` (repo root)
- Modify: `Hair Compass AI 5/Feature/HairChatSheet.swift` (gate behind Pro)
- Modify: `Hair Compass AI 5/Feature/DeepAnalysisSheet.swift` (gate behind Pro)
- Create: `Hair Compass AI 5Tests/ProjectionModelTests.swift`

**Interfaces:**
- Produces: `OnboardingPlanStep(profile: Profile, onContinue: @escaping () -> Void)` — consumed by Track A as onboarding step 12.
- Produces: `PurchaseService` — `@MainActor @Observable final class`, **empty init** (Track C injects `PurchaseService()` via `.environment(...)` in RootView). Views read it with `@Environment(PurchaseService.self)`.
- Consumes: `HairCondition`, `BiologicalSex`, `Profile` (existing), `Clinical` tokens.

- [ ] **B1: PurchaseService.** StoreKit 2, matching this branch's service style:

```swift
import Foundation
import StoreKit

/// StoreKit 2 wrapper for the Pro subscription. Entitlement-driven: `hasPro` reflects
/// `Transaction.currentEntitlements`, refreshed on launch, after purchases, and on
/// transaction updates. Fully usable with the store unreachable — products just stay empty
/// and the UI degrades to the free path.
@MainActor
@Observable
final class PurchaseService {
    static let monthlyID = "com.harib.haircompass.pro.monthly"
    static let yearlyID  = "com.harib.haircompass.pro.yearly"

    private(set) var products: [Product] = []
    private(set) var hasPro = false
    private(set) var isLoading = false
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.refreshEntitlement()
            }
        }
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        products = (try? await Product.products(for: [Self.monthlyID, Self.yearlyID])) ?? []
        await refreshEntitlement()
    }

    /// Returns true when the purchase completed (verified). Pending/cancelled return false.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard let result = try? await product.purchase() else { return false }
        switch result {
        case .success(let verification):
            if case .verified(let t) = verification { await t.finish() }
            await refreshEntitlement()
            return hasPro
        default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement,
               t.productID == Self.monthlyID || t.productID == Self.yearlyID,
               t.revocationDate == nil {
                hasPro = true
                return
            }
        }
        hasPro = false
    }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
}
```

- [ ] **B2: ProjectionModel — the honest projection.** Pure, unit-testable. The ONLY hard number allowed is the one verified in `docs/TrackingSpec.md`: combination therapy (finasteride + minoxidil) ≈ **+29.7 hairs/cm² vs minoxidil alone at 24 weeks in men** (network meta-analysis, SUCRA 80.2%). Everything else is qualitative milestones. Read `docs/TrackingSpec.md` first.

```swift
import Foundation

/// The end-of-onboarding "what tracking gets you" model. Deliberately honest:
/// tracking does not grow hair — consistency with an evidence-based plan does, and
/// tracking is how you keep consistency and see whether the plan works. The only
/// quantitative curve shown is the published male-AGA combination-therapy average;
/// every other profile gets qualitative milestones.
struct ProjectionModel {
    struct Milestone: Equatable {
        let week: Int
        let label: String
    }
    struct CurvePoint: Equatable {
        let week: Int
        let hairsPerCm2: Double  // delta vs baseline
    }

    let headline: String
    let milestones: [Milestone]
    /// Non-nil only when a published average exists for this profile (male androgenetic).
    let evidenceCurve: [CurvePoint]?
    let citation: String
    let disclaimer: String

    static let disclaimerText = "Illustrative — published clinical averages, not a prediction of your results. Individual results vary. Tracking itself doesn't grow hair; it helps you stay consistent and see what works."

    static func make(condition: HairCondition, sex: BiologicalSex) -> ProjectionModel {
        let base: [Milestone] = [
            .init(week: 0, label: "Baseline set — photos, shedding, scalp"),
            .init(week: 6, label: "Where most people quit — reminders keep you going"),
            .init(week: 12, label: "First trend signal is usually readable"),
            .init(week: 24, label: "Published studies measure response here"),
        ]
        switch (condition, sex) {
        case (.androgenetic, .male):
            // Smooth ease-in toward the published 24-week average.
            let target = 29.7
            let curve = [0, 4, 8, 12, 16, 20, 24].map { week in
                CurvePoint(week: week, hairsPerCm2: target * easeIn(Double(week) / 24))
            }
            return .init(
                headline: "Consistency is measurable",
                milestones: base,
                evidenceCurve: curve,
                citation: "Combination therapy averaged +29.7 hairs/cm² at 24 weeks in men (network meta-analysis; see a clinician about what fits you).",
                disclaimer: disclaimerText
            )
        case (.telogenEffluvium, _):
            return .init(
                headline: "Shedding after a trigger usually recovers",
                milestones: [
                    .init(week: 0, label: "Baseline set — daily shed level"),
                    .init(week: 8, label: "Trigger window — shedding often peaks 2–3 months after"),
                    .init(week: 12, label: "Recovery typically begins once the trigger passes"),
                    .init(week: 24, label: "Your chart shows the full arc"),
                ],
                evidenceCurve: nil,
                citation: "Telogen effluvium typically follows a trigger by 2–3 months and recovers over the following months.",
                disclaimer: disclaimerText
            )
        default:
            return .init(
                headline: "Seeing clearly beats guessing",
                milestones: base,
                evidenceCurve: nil,
                citation: "Evidence-based treatments take 3–6 months to show measurable change — objective tracking is how you know.",
                disclaimer: disclaimerText
            )
        }
    }

    private static func easeIn(_ t: Double) -> Double {
        let c = min(max(t, 0), 1)
        return c * c * (3 - 2 * c)  // smoothstep
    }
}
```

- [ ] **B3: OnboardingPlanStep.** `OnboardingPlanStep(profile: Profile, onContinue: @escaping () -> Void)`. Layout top-to-bottom:
  1. `Eyebrow("Your plan")` + `Text("Make the next 6 months count")` (Clinical.headline(28)).
  2. Personal line built from answers: "You told us: {plainTitle lowercased}{", family history" if familyHistory != .none}{", high stress" if applicable}. Here's what consistent tracking does with that."
  3. Projection card (`Clinical.surface`, radius 18): if `evidenceCurve != nil`, a Swift Charts `LineMark` (week → hairs/cm²) in `Clinical.accent` with the milestones as `PointMark`/annotations; otherwise a vertical milestone timeline (week badge + label rows). Under either: the `citation` (11pt, secondary) and `disclaimer` (11pt, tertiary) — **always visible, never truncated**.
  4. "What Pro adds" rows (3, surface cards, SF symbol + title + one line): AI hair chat ("Ask anything about your data"), AI deep photo analysis ("Standardized, objective photo reads"), Smart reminders & trends ("Stay consistent through week 6").
  5. Purchase buttons from `@Environment(PurchaseService.self)`: yearly first (`ClinicalButtonStyle`, shows `yearly.displayPrice` + "/year" and the real per-month equivalent computed from `yearly.price / 12` formatted with the product's `priceFormatStyle`), monthly as a bordered secondary. If `purchases.products.isEmpty`, show neither — only the free path (no fake prices ever).
  6. `Button("Continue free")` — always visible, 15pt medium, `Clinical.ink`, directly under the purchase buttons (not buried). Calls `onContinue()`.
  7. `Button("Restore purchases")` (12pt, tertiary) → `await purchases.restore()`.
  On successful purchase → `onContinue()`. No back navigation, no timers, no "offer expires".
  Add `.accessibilityIdentifier("onboardContinueFree")` on the free button.

- [ ] **B4: ProGate + gating.** Create `ProGate.swift`:

```swift
/// Wraps premium content: shows it for Pro users, otherwise an inline, honest upsell
/// (feature name + the two Pro purchase buttons + restore). Used by the AI sheets.
struct ProGate<Content: View>: View { ... }
```

`ProGate(feature: "AI hair chat", symbol: "bubble.left.and.text.bubble.right") { ...existing content... }`. The locked state: symbol in accentSoft circle, feature title, one-line honest description, purchase buttons (same behavior as B3.5), restore link. NO dark patterns. Then wrap the main content of `HairChatSheet` and `DeepAnalysisSheet` in `ProGate` — read both files first and gate at the top-level body so the sheet chrome (nav title, Done button) stays.

- [ ] **B5: StoreKit config.** Create `HairCompass.storekit` at repo root: subscription group "Pro" (id 21442176), two auto-renewables — monthly `com.harib.haircompass.pro.monthly` $4.99/1-month, yearly `com.harib.haircompass.pro.yearly` $29.99/1-year. Use the standard `.storekit` JSON schema (`"version" : { "major" : 4, "minor" : 0 }`, `subscriptionGroups` array). This file is for local testing; it is not wired into a scheme automatically.

- [ ] **B6: Tests.** `Hair Compass AI 5Tests/ProjectionModelTests.swift`:

```swift
import Testing
@testable import Hair_Compass_AI_5

@Test func maleAGAGetsTheOnlyQuantitativeCurve() {
    let p = ProjectionModel.make(condition: .androgenetic, sex: .male)
    let curve = try! #require(p.evidenceCurve)
    #expect(curve.first?.hairsPerCm2 == 0)
    #expect(abs((curve.last?.hairsPerCm2 ?? 0) - 29.7) < 0.01)
    #expect(curve.map(\.hairsPerCm2) == curve.map(\.hairsPerCm2).sorted())  // monotonic
}

@Test func everyoneElseGetsMilestonesOnly() {
    for c in HairCondition.allCases where !(c == .androgenetic) {
        for s in BiologicalSex.allCases {
            let p = ProjectionModel.make(condition: c, sex: s)
            #expect(p.evidenceCurve == nil)
            #expect(!p.milestones.isEmpty)
            #expect(!p.citation.isEmpty)
        }
    }
    #expect(ProjectionModel.make(condition: .androgenetic, sex: .female).evidenceCurve == nil)
}

@Test func disclaimerIsAlwaysPresentAndHonest() {
    for c in HairCondition.allCases {
        for s in BiologicalSex.allCases {
            let p = ProjectionModel.make(condition: c, sex: s)
            #expect(p.disclaimer.contains("not a prediction"))
        }
    }
}
```

---

### Task C: First-launch tutorial + RootView wiring + Trends refresh

**Files (Track C owns these exclusively):**
- Create: `Hair Compass AI 5/Feature/TutorialOverlay.swift`
- Modify: `Hair Compass AI 5/App/RootView.swift`
- Modify: `Hair Compass AI 5/Feature/BodySignalsDashboard.swift`

**Interfaces:**
- Consumes: `PurchaseService()` (Track B — empty init; just construct and inject).
- Consumes: `AppTab` (existing), `HealthKitService.refreshSnapshot(context:)`, `lastRefresh`.
- Produces: `TutorialOverlay(tab: Binding<AppTab>, onDone: @escaping () -> Void)`.

- [ ] **C1: TutorialOverlay.** A card-above-the-tab-bar coach sequence. 5 pages, advancing switches the LIVE tab underneath so the user sees real screens:

| page | tab | title | line |
|---|---|---|---|
| 0 | .today | Today | "Log your day in seconds — shedding, scalp, and treatments live here." |
| 1 | .trends | Trends | "Every log builds these charts. Apple Health fills in sleep and recovery automatically." |
| 2 | .care | Plan | "Your treatments and routines, with reminders and refill tracking." |
| 3 | .labs | Labs | "The blood work that matters for hair — ferritin, thyroid, vitamin D." |
| 4 | .photos | Photos | "Standardized progress photos — your most objective signal." |

Structure: a dimmed scrim (`Clinical.ink.opacity(0.25)`) that does NOT dim the tab bar area, a floating surface card bottom-anchored above the tab bar with eyebrow "QUICK TOUR · {n} of 5", title, line, page dots, "Next"/"Done" primary (ClinicalButtonStyle) and "Skip tour" plain button (every page). On page change set `tab.wrappedValue = page.tab` with the app's standard `.easeOut(duration: 0.22)`. Reduce Motion: no slide, opacity only. Accessibility ids: `tutorialNext`, `tutorialSkip`. Both Skip and final Done call `onDone()`.

- [ ] **C2: RootView wiring.** Add:

```swift
@AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
@State private var showTutorial = false
@State private var purchases = PurchaseService()
```

`.environment(purchases)` alongside the existing `.environment(...)` calls. Onboarding handoff — in the existing fullScreenCover, `onFinish` becomes:

```swift
OnboardingFlow(profile: profile, onFinish: {
    showOnboarding = false
    if !hasSeenTutorial { showTutorial = true }
})
.environment(healthKit)
.environment(purchases)
```

**Why the two `.environment` calls:** presented covers inherit the environment from where `.fullScreenCover` is attached, which in RootView is OUTSIDE the existing `.environment(healthKit)` modifier — without re-injecting, the onboarding's health step (Track A) and paywall step (Track B) would crash reading `@Environment(HealthKitService.self)` / `@Environment(PurchaseService.self)`. Do not remove the existing `.environment(...)` calls.

Also cover the "onboarded but never toured" relaunch (user killed the app mid-tutorial): in the bootstrap `.task`, after the `showOnboarding` decision — `if !showOnboarding, profile?.hasOnboarded == true, !hasSeenTutorial { showTutorial = true }`. Suppress the ritual roll while a tutorial is pending: extend the bootstrap guard to `if !showOnboarding && !showTutorial && !suppressRitual && !appLock.isLocked` and the foreground re-roll guard similarly (`!showTutorial`). Render the overlay INSIDE the outer ZStack, after the tab Group, so the safeAreaInset tab bar stays interactive-looking but above the scrim visually — concretely:

```swift
.overlay {
    if showTutorial {
        TutorialOverlay(tab: $tab) {
            hasSeenTutorial = true
            showTutorial = false
        }
        .transition(.opacity)
    }
}
```

placed on the ZStack before `.safeAreaInset` so the tab bar draws above it (`zIndex(100)` on the bar already handles stacking). Verify the overlay does not block the tab bar's hit-testing while active — the tour drives tab switching itself, so blocking taps on content behind the scrim is fine, but the card's own buttons must work.

- [ ] **C3: Trends refresh affordance.** In `BodySignalsDashboard.swift` (read it fully first): in the **authorized** state, add a quiet row under the signals: "Updated {healthKit.lastRefresh, relative}" (11pt tertiary) + Button "Update from Health" (13pt medium, accent) → `await healthKit.refreshSnapshot(context: context)` (needs `@Environment(\.modelContext)` — check what the view already has). In the **unauthorized** state, after a successful `requestAuthorization()` from the existing Connect button, add the missing `await healthKit.refreshSnapshot(context: context)` so data appears immediately. Accessibility id `trendsHealthRefresh` on the refresh button.

---

### Task D (orchestrator): integration, build, test, verify, commit

- [ ] **D1:** After A+B+C complete, read the diff; fix interface drift.
- [ ] **D2:** `xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — fix until green.
- [ ] **D3:** Run unit tests (full suite). Fix failures.
- [ ] **D4:** Launch in simulator with a fresh store (delete stale `HairCompassAI5.store*` per memory note), walk all 14 onboarding steps + tutorial with `xcrun simctl` + screenshots; verify keyboard pops on name step, images show on sex step, paywall shows free path (products may be empty without a StoreKit config in the scheme — acceptable), tutorial autostarts, Health prompt appears.
- [ ] **D5:** Run UI tests. Fix failures.
- [ ] **D6:** Commit in logical chunks (flow, commerce, tutorial/trends, assets+spec/plan docs).
