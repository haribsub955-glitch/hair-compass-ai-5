# Monetization Hard Wall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put every feature except the daily check-in behind Pro, decouple Pro from Apple Intelligence so it sells on every iPhone, and move the affiliate storefront onto the free side of the wall.

**Architecture:** One policy file (`Entitlements.swift`) answers "may this person use this feature", replacing a `hasPro` check scattered across views. Pure-logic types (`ProFeature`, `EntitlementTier`, `TasterWindow`, `HistoryAccess`) carry all the decisions and are unit-tested without a simulator; SwiftUI surfaces consume them through a `.proGated(_:)` modifier. Navigation restructures so free users land on two working tabs, one of which is the shop.

**Tech Stack:** SwiftUI, SwiftData, StoreKit 2, WidgetKit, Swift Testing (`@Test`/`#expect` — **not** XCTest).

## Global Constraints

- **Swift Testing, never XCTest**, in the unit bundle: `import Testing`, `@Test`, `#expect`. UI tests stay XCUITest.
- **Model names are the post-revamp ones**: `DailyEntry` (not `CheckInEntry`), `Profile`, `Treatment`, `TreatmentDose`, `PhotoRecord`, `LabResult`, `ProcedureAppointment`, `ProgressCheckIn`, `TriggerEvent`, `HealthSnapshot`, `SideEffectLog`, `MissedDoseRecord`.
- **Colours and fonts come from `Clinical`** (`Design/Clinical.swift`) — `Clinical.ink`, `.secondary`, `.tertiary`, `.accent`, `.accentSoft`, `.hairline`, `.canvas`, `.surface`, and `Clinical.headline(_:)`, `.body(_:weight:)`, `.caption(_:)`, `.number(_:weight:)`, `.eyebrow(_:)`. Never hardcode a colour.
- **Prices are never hardcoded in Swift.** $6.99/month and $39.99/year live in App Store Connect; the app renders `product.displayPrice`, `monthlyEquivalentDisplay`, and `yearlyVersusMonthly()`.
- **Export stays reachable on every tier** — App Store Guideline 3.1.2(a).
- **Paths contain spaces** — always quote them in shell commands.
- **Build/test destination:** pick a simulator that exists and runs iOS ≥ 26.2 (`xcrun simctl list devices`). This plan writes `iPhone 17 Pro`; substitute whatever is installed.

---

### Task 1: Entitlement policy core


The single table that decides what is free. Pure logic, no SwiftUI, no SwiftData — so it tests in milliseconds and every later task consumes it.

**Files:**
- Create: `Hair Compass AI 5/Feature/Entitlements.swift`
- Test: `Hair Compass AI 5Tests/EntitlementsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum ProFeature` (cases below, `var requiresAppleIntelligence: Bool`), `enum EntitlementTier { case free, taster, pro }`, `struct Entitlements { let tier: EntitlementTier; func canAccess(_ feature: ProFeature) -> Bool }`.

- [ ] **Step 1: Write the failing test**

Create `Hair Compass AI 5Tests/EntitlementsTests.swift`:

```swift
//
//  EntitlementsTests.swift
//  Hair Compass AI 5Tests
//
//  The one table that decides what is free. Every case is asserted
//  explicitly rather than by a rule, so widening the free tier by
//  accident fails a test instead of shipping.
//

import Testing
@testable import Hair_Compass_AI_5

struct EntitlementsTests {

    @Test func freeTierUnlocksNothing() {
        let free = Entitlements(tier: .free)
        for feature in ProFeature.allCases {
            #expect(free.canAccess(feature) == false,
                    "\(feature) must be Pro — the free tier is check-in only.")
        }
    }

    @Test func tasterUnlocksEverything() {
        let taster = Entitlements(tier: .taster)
        for feature in ProFeature.allCases {
            #expect(taster.canAccess(feature),
                    "The taster is the full app with no payment method — \(feature) must open.")
        }
    }

    @Test func proUnlocksEverything() {
        let pro = Entitlements(tier: .pro)
        for feature in ProFeature.allCases {
            #expect(pro.canAccess(feature))
        }
    }

    /// The split that lets Pro sell on an iPhone 14: exactly two features need
    /// on-device models, and every other one works on any supported phone.
    @Test func onlyTheTwoAIFeaturesNeedAppleIntelligence() {
        let needsAI = ProFeature.allCases.filter(\.requiresAppleIntelligence)
        #expect(Set(needsAI) == [.askWren, .deepAnalysis])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/EntitlementsTests" 2>&1 | tail -20
```

Expected: FAIL — "cannot find 'Entitlements' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `Hair Compass AI 5/Feature/Entitlements.swift`:

```swift
import Foundation

/// Everything Pro gates, as data rather than as twenty scattered `hasPro` checks.
///
/// Adding a feature here and applying `.proGated(_:)` at its surface is the whole job — the
/// policy stays readable in one place, and `EntitlementsTests` fails if the free tier ever
/// widens by accident.
enum ProFeature: CaseIterable, Hashable {
    case history, trends, compare, journey, photos, labs,
         procedures, treatments, reports, bodySignals
    case askWren, deepAnalysis

    /// The two features that run on Apple Intelligence with no cloud fallback.
    ///
    /// This is a property of the FEATURE, not of the subscription — which is the distinction
    /// that lets a subscription sell on hardware that can't run these two. Before this existed,
    /// `ProAvailability.sellable` withdrew the purchase buttons entirely and the app could not
    /// be sold on an iPhone 14 at all.
    var requiresAppleIntelligence: Bool {
        switch self {
        case .askWren, .deepAnalysis: true
        default: false
        }
    }
}

/// What someone is entitled to right now.
///
/// `taster` is deliberately identical to `pro`: three days of the real product, no payment
/// method, no turn caps. On-device inference means a farmed taster costs nothing to honour, so
/// there is no abuse defence to build and no reason to make it feel like a demo.
/// `Equatable` for the tier assertions in `EntitlementsTests`; `CustomStringConvertible` because
/// `RootView.widgetFingerprint` interpolates it (Task 9) and the default enum description would
/// change the fingerprint format if a case were ever renamed.
enum EntitlementTier: Equatable, CustomStringConvertible {
    case free
    case taster
    case pro

    var description: String {
        switch self {
        case .free: "free"
        case .taster: "taster"
        case .pro: "pro"
        }
    }
}

struct Entitlements {
    let tier: EntitlementTier

    func canAccess(_ feature: ProFeature) -> Bool {
        switch tier {
        case .free: false
        case .taster, .pro: true
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Feature/Entitlements.swift" "Hair Compass AI 5Tests/EntitlementsTests.swift"
git commit -m "Entitlements: what is free, as one readable table"
```

---

### Task 2: The 3-day taster window


**Files:**
- Modify: `Hair Compass AI 5/Feature/Entitlements.swift`
- Test: `Hair Compass AI 5Tests/EntitlementsTests.swift`

**Interfaces:**
- Consumes: `EntitlementTier` from Task 1.
- Produces: `struct TasterWindow { static let durationDays = 3; let firstLaunch: Date; func isActive(now:calendar:) -> Bool }` and `static func resolve(hasPro:firstLaunch:now:calendar:) -> EntitlementTier` on `Entitlements`.

- [ ] **Step 1: Write the failing test**

Append inside `struct EntitlementsTests`:

```swift
    private func day(_ offset: Int, from base: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: base)!
    }

    @Test func tasterIsActiveForThreeDaysThenExpires() {
        let launch = Date(timeIntervalSince1970: 1_760_000_000)
        let window = TasterWindow(firstLaunch: launch)
        #expect(window.isActive(now: launch))
        #expect(window.isActive(now: day(2, from: launch)))
        #expect(window.isActive(now: day(3, from: launch)) == false)
        #expect(window.isActive(now: day(9, from: launch)) == false)
    }

    /// An expired taster drops to free — never to trial. The trial needs a payment method the
    /// taster deliberately never asked for, so auto-starting it would charge someone who never
    /// entered a card.
    @Test func expiredTasterResolvesToFreeNotPro() {
        let launch = Date(timeIntervalSince1970: 1_760_000_000)
        let tier = Entitlements.resolve(hasPro: false, firstLaunch: launch, now: day(5, from: launch))
        #expect(tier == .free)
    }

    @Test func activeTasterResolvesToTaster() {
        let launch = Date(timeIntervalSince1970: 1_760_000_000)
        let tier = Entitlements.resolve(hasPro: false, firstLaunch: launch, now: day(1, from: launch))
        #expect(tier == .taster)
    }

    /// A real subscription outranks the taster clock in both directions — including a
    /// subscriber whose taster is long expired.
    @Test func proWinsRegardlessOfTasterClock() {
        let launch = Date(timeIntervalSince1970: 1_760_000_000)
        #expect(Entitlements.resolve(hasPro: true, firstLaunch: launch, now: day(1, from: launch)) == .pro)
        #expect(Entitlements.resolve(hasPro: true, firstLaunch: launch, now: day(90, from: launch)) == .pro)
    }
```

Add `Equatable` to the tier so `#expect(tier == .free)` compiles — see Step 3.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/EntitlementsTests" 2>&1 | tail -20
```

Expected: FAIL — "cannot find 'TasterWindow' in scope".

- [ ] **Step 3: Write minimal implementation**

In `Entitlements.swift`, append:

```swift
/// Three days of the whole app, no payment method, on the device's own clock.
///
/// Reinstalling resets it, and that is accepted rather than defended: the model runs on-device,
/// so a farmed taster costs nothing. Building device binding to protect $0 would be effort spent
/// on nothing.
struct TasterWindow {
    static let durationDays = 3

    let firstLaunch: Date

    func isActive(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let end = calendar.date(byAdding: .day, value: Self.durationDays, to: firstLaunch)
        else { return false }
        return now < end
    }
}

extension Entitlements {
    /// The one place a tier is decided. `hasPro` covers both a paid subscription and an active
    /// Apple trial, because `Transaction.currentEntitlements` reports them identically.
    static func resolve(
        hasPro: Bool,
        firstLaunch: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> EntitlementTier {
        if hasPro { return .pro }
        if TasterWindow(firstLaunch: firstLaunch).isActive(now: now, calendar: calendar) { return .taster }
        return .free
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Feature/Entitlements.swift" "Hair Compass AI 5Tests/EntitlementsTests.swift"
git commit -m "Taster: three days of the real product, no card, no abuse defence"
```

---

### Task 3: The history wall


Free users may log forever and see only today. Enforced as a pure function over fetched entries so no future surface can bypass it by writing its own view code.

**Files:**
- Create: `Hair Compass AI 5/Feature/HistoryAccess.swift`
- Test: `Hair Compass AI 5Tests/HistoryAccessTests.swift`

**Interfaces:**
- Consumes: `Entitlements`, `ProFeature.history` from Task 1.
- Produces: `enum HistoryAccess` with `static func visible(_:entitlements:now:calendar:) -> [DailyEntry]` and `static func lockedCount(_:entitlements:now:calendar:) -> Int`.

- [ ] **Step 1: Write the failing test**

Create `Hair Compass AI 5Tests/HistoryAccessTests.swift`:

```swift
//
//  HistoryAccessTests.swift
//  Hair Compass AI 5Tests
//
//  Free users log forever and see only today. The locked count is the
//  commercial mechanic — it grows every day they stay free — so it is
//  asserted as carefully as the visibility rule itself.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct HistoryAccessTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// Today plus `past` earlier days, newest first — the order `@Query` returns.
    private func entries(past: Int) -> [DailyEntry] {
        let calendar = Calendar.current
        return (0...past).map { offset in
            DailyEntry(date: calendar.date(byAdding: .day, value: -offset, to: now)!)
        }
    }

    @Test func freeSeesOnlyToday() {
        let visible = HistoryAccess.visible(entries(past: 22),
                                            entitlements: Entitlements(tier: .free),
                                            now: now)
        #expect(visible.count == 1)
        #expect(Calendar.current.isDate(visible[0].date, inSameDayAs: now))
    }

    @Test func proSeesEverything() {
        let all = entries(past: 22)
        let visible = HistoryAccess.visible(all, entitlements: Entitlements(tier: .pro), now: now)
        #expect(visible.count == all.count)
    }

    @Test func lockedCountExcludesTodayAndCountsTheRest() {
        #expect(HistoryAccess.lockedCount(entries(past: 22),
                                          entitlements: Entitlements(tier: .free),
                                          now: now) == 22)
    }

    /// Nothing is locked for someone who can see it all, so the card never renders for them.
    @Test func lockedCountIsZeroForPro() {
        #expect(HistoryAccess.lockedCount(entries(past: 22),
                                          entitlements: Entitlements(tier: .pro),
                                          now: now) == 0)
    }

    @Test func aBrandNewUserHasNothingLocked() {
        #expect(HistoryAccess.lockedCount(entries(past: 0),
                                          entitlements: Entitlements(tier: .free),
                                          now: now) == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/HistoryAccessTests" 2>&1 | tail -20
```

Expected: FAIL — "cannot find 'HistoryAccess' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `Hair Compass AI 5/Feature/HistoryAccess.swift`:

```swift
import Foundation

/// The free tier's defining restriction: log forever, see only today.
///
/// A function over already-fetched entries rather than a `@Query` predicate, so the rule stays
/// in one place, reads the same at every call site, and is unit-testable without a
/// `ModelContext`. It is a CONVENTION, not an access control: a view that fetches `DailyEntry`
/// directly still bypasses it, and no client-side check could prevent that anyway. Route every
/// history surface through here.
enum HistoryAccess {

    static func visible(
        _ entries: [DailyEntry],
        entitlements: Entitlements,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DailyEntry] {
        guard !entitlements.canAccess(.history) else { return entries }
        return entries.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// How much of their own record is sitting behind the wall. This number is the conversion
    /// mechanic — it grows every day someone stays free, which is why the free tier caps
    /// nothing: a capped check-in would stop this counter climbing.
    static func lockedCount(
        _ entries: [DailyEntry],
        entitlements: Entitlements,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard !entitlements.canAccess(.history) else { return 0 }
        return entries.filter { !calendar.isDate($0.date, inSameDayAs: now) }.count
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Feature/HistoryAccess.swift" "Hair Compass AI 5Tests/HistoryAccessTests.swift"
git commit -m "History wall: today only, and a locked count that compounds"
```

---

### Task 4: Pro sells on every iPhone

Today `ProAvailability.sellable()` decides whether the paywall sells **at all**, so Pro is unsellable on an Apple-Intelligence-ineligible iPhone. This task inverts that scope AND rewrites `ProGate` to consume `ProFeature`, in one commit — split apart, the first half orphans `sellable`'s callers and leaves the app target uncompilable, so they land together.

**This is the commercially load-bearing task in the plan.** Everything else packages a product that, before this change, could not be bought at all on a large share of iPhones.

**Files:**
- Modify: `Hair Compass AI 5/Feature/ProAvailability.swift:48-70`
- Modify: `Hair Compass AI 5/Feature/ProGate.swift`
- Modify: `Hair Compass AI 5/Feature/Onboarding/OnboardingPlanStep.swift`
- Modify: `Hair Compass AI 5/Feature/HairChatSheet.swift:34`, `Hair Compass AI 5/Feature/DeepAnalysisSheet.swift:33`
- Modify: `Hair Compass AI 5/Feature/Entitlements.swift` (gate copy)
- Create: `Hair Compass AI 5/Feature/ProGatedModifier.swift`
- Test: `Hair Compass AI 5Tests/SubmissionReadinessTests.swift`, `Hair Compass AI 5Tests/EntitlementsTests.swift`

**Interfaces:**
- Consumes: `ProFeature` (Task 1), `OnDeviceAvailability` (existing), `PurchaseService` (existing).
- Produces: `ProAvailability.canRun(_:status:) -> Bool`; `ProFeature.gateTitle/.gateSymbol/.gateDescription`; `extension View { func proGated(_:) -> some View }`. `ProAvailability.sellable(_:)` is **removed**.

**Every commit in this task must build.** Do not commit between the `canRun` change and the `ProGate` rewrite.

- [ ] **Step 1: Write the failing test**

In `SubmissionReadinessTests.swift`, replace the existing `sellable` assertions with:

```swift
    /// The commercial correctness of the whole paywall. Before this, an ineligible iPhone was
    /// offered nothing at all — a mostly-locked app with no button to unlock it, which is both a
    /// Guideline 3.1.2 risk and a dead end for the person holding the phone.
    @Test func proSellsOnHardwareThatCannotRunAppleIntelligence() {
        for feature in ProFeature.allCases where !feature.requiresAppleIntelligence {
            #expect(ProAvailability.canRun(feature, status: .deviceNotEligible),
                    "\(feature) has no on-device model dependency and must work on any iPhone.")
        }
    }

    @Test func theTwoAIFeaturesCannotRunOnIneligibleHardware() {
        #expect(ProAvailability.canRun(.askWren, status: .deviceNotEligible) == false)
        #expect(ProAvailability.canRun(.deepAnalysis, status: .deviceNotEligible) == false)
    }

    /// A switched-off or still-downloading model is something the person can fix themselves, so
    /// those states stay runnable-once-fixed and the notice tells them how.
    @Test func fixableStatesStillCountAsRunnable() {
        for status in [OnDeviceAvailability.available, .notEnabled, .modelNotReady] {
            #expect(ProAvailability.canRun(.askWren, status: status))
        }
    }
```

Keep the existing message assertions (`message(for:)` non-empty for unavailable states, empty for `.available`, `.deviceNotEligible` mentioning "Apple Intelligence" and "free") — they still hold.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/SubmissionReadinessTests" 2>&1 | tail -20
```

Expected: FAIL — "type 'ProAvailability' has no member 'canRun'".

- [ ] **Step 3: Write minimal implementation**

In `ProAvailability.swift`, delete `static func sellable(_:)` and add:

```swift
    /// Whether a given Pro feature can actually run on this device right now.
    ///
    /// This replaced `sellable(_:)`, and the change of scope is the point. `sellable` asked "may
    /// we sell a subscription at all", which tied the entire product to Apple Intelligence and
    /// left ineligible hardware with nothing to buy. This asks the narrower, correct question:
    /// the subscription always sells, and only the two on-device-model features are withheld.
    static func canRun(_ feature: ProFeature, status: OnDeviceAvailability) -> Bool {
        guard feature.requiresAppleIntelligence else { return true }
        return status != .deviceNotEligible
    }
```

Update the type's doc comment: the sentence saying both purchase surfaces "check `sellable` before offering them at all" is now false — they always offer, and hide only the AI rows.

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, and the app target compiles — the `ProGate` rewrite in the same task has already replaced every `sellable` caller.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Feature/" "Hair Compass AI 5Tests/"
git commit -m "Pro sells on every iPhone; only the two AI features carry the notice"
```

---


---

#### Also in this task: feature-aware `ProGate`
- [ ] **Step 1: Write the failing test**

Append to `EntitlementsTests.swift`:

```swift
    /// Copy for every gate lives in one switch so a new feature cannot ship with an empty
    /// paywall card. Asserted rather than reviewed, because an empty string renders as a
    /// blank sheet that looks like a bug.
    @Test func everyFeatureHasGateCopy() {
        for feature in ProFeature.allCases {
            #expect(!feature.gateTitle.isEmpty, "\(feature) needs a title")
            #expect(!feature.gateDescription.isEmpty, "\(feature) needs a description")
            #expect(!feature.gateSymbol.isEmpty, "\(feature) needs an SF Symbol")
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/EntitlementsTests" 2>&1 | tail -20
```

Expected: FAIL — "value of type 'ProFeature' has no member 'gateTitle'".

- [ ] **Step 3: Write minimal implementation**

Append to `Entitlements.swift`:

```swift
extension ProFeature {
    var gateTitle: String {
        switch self {
        case .history: "Your full record"
        case .trends: "Trends"
        case .compare: "Compare"
        case .journey: "Your journey"
        case .photos: "Photos"
        case .labs: "Lab results"
        case .procedures: "Procedures"
        case .treatments: "Treatments"
        case .reports: "Progress reports"
        case .bodySignals: "Body signals"
        case .askWren: "Ask Wren"
        case .deepAnalysis: "Deep analysis"
        }
    }

    var gateSymbol: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .trends: "chart.xyaxis.line"
        case .compare: "rectangle.split.2x1"
        case .journey: "map"
        case .photos: "camera"
        case .labs: "testtube.2"
        case .procedures: "cross.case"
        case .treatments: "pills"
        case .reports: "doc.text"
        case .bodySignals: "heart.text.square"
        case .askWren: "bubble.left.and.text.bubble.right"
        case .deepAnalysis: "sparkles"
        }
    }

    var gateDescription: String {
        switch self {
        case .history: "Every check-in you've recorded, not just today."
        case .trends: "How shed, scalp and consistency move over weeks."
        case .compare: "Two dates side by side, on the same scale."
        case .journey: "Your whole record as one timeline."
        case .photos: "Capture, revisit and compare your own photos."
        case .labs: "Record results and see which are flagged."
        case .procedures: "Keep appointments and outcomes in one place."
        case .treatments: "Track what you're using and whether you're consistent."
        case .reports: "A summary you can read or hand to a clinician."
        case .bodySignals: "Sleep, stress and the rest, next to your hair record."
        case .askWren: "Ask about your own record, answered on your iPhone."
        case .deepAnalysis: "A closer read of everything you've logged."
        }
    }
}
```

Create `Hair Compass AI 5/Feature/ProGatedModifier.swift`:

```swift
import SwiftUI

/// Applies the wall at a surface. One line per gated view, so the policy stays in
/// `Entitlements.swift` and call sites carry no decision of their own.
struct ProGatedModifier: ViewModifier {
    let feature: ProFeature

    func body(content: Content) -> some View {
        ProGate(feature: feature) { content }
    }
}

extension View {
    func proGated(_ feature: ProFeature) -> some View {
        modifier(ProGatedModifier(feature: feature))
    }
}
```

In `ProGate.swift`: replace the `let feature: String` / `let symbol: String` / `var description: String` stored properties with `let feature: ProFeature`, and read copy from `feature.gateTitle` / `.gateSymbol` / `.gateDescription`. Change the entitlement check at `:35` from `purchases.hasPro` to the resolved tier (Task 6 injects it; until then use `purchases.hasPro`). Replace the `sellable` branch at `:83-86` with:

```swift
            // The notice only speaks for features that actually need the model, so gating
            // Trends no longer tells someone their iPhone is the problem.
            if feature.requiresAppleIntelligence {
                ProAvailabilityNotice(status: availability)
            }

            // The purchase buttons are now UNCONDITIONAL. Even where this particular feature
            // can never run, the subscription still unlocks the other ten, so withdrawing the
            // sale would be wrong — it is what left ineligible iPhones with nothing to buy.
            if !purchases.products.isEmpty {
                purchaseButtons
            } else {
                StoreUnavailableView(isLoading: purchases.isLoading) {
                    Task { await purchases.load() }
                }
            }
```

Extract the existing yearly/monthly button stack into a `private var purchaseButtons: some View`
so the branch above reads cleanly. Delete the `if !ProAvailability.sellable(availability)` guard
entirely, and change `PaywallLegal(showsRenewalDisclosure: ProAvailability.sellable(availability))`
to `PaywallLegal(showsRenewalDisclosure: true)` — there is always something to sell now, so the
renewal disclosure always applies. In `OnboardingPlanStep.swift`, replace its `ProAvailability.sellable(availability)` call with `true` for the purchase buttons and keep `PaywallLegal(showsRenewalDisclosure: true)`; show `ProAvailabilityNotice` beside the two AI rows only.

Update the two existing call sites to the new initialiser:

```swift
// HairChatSheet.swift:34
ProGate(feature: .askWren) { ... }

// DeepAnalysisSheet.swift:33
ProGate(feature: .deepAnalysis) { ... }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/EntitlementsTests" \
  -only-testing:"Hair Compass AI 5Tests/SubmissionReadinessTests" 2>&1 | tail -20
```

Expected: PASS — and the app target now compiles, closing Task 4's deferred build.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Feature/"
git commit -m "ProGate speaks ProFeature, and the AI notice stops speaking for everything"
```

---

### Task 5: Resolve the tier once, at the root


**Files:**
- Modify: `Hair Compass AI 5/App/RootView.swift` (add `@AppStorage` first-launch stamp, inject `Entitlements`)
- Create: `Hair Compass AI 5/Feature/EntitlementsEnvironment.swift`
- Modify: `Hair Compass AI 5/Feature/ProGate.swift` (read the injected value)

**Interfaces:**
- Consumes: `Entitlements.resolve(hasPro:firstLaunch:now:calendar:)`, `PurchaseService.hasPro`.
- Produces: `EnvironmentValues.entitlements`, defaulting to `Entitlements(tier: .free)`.

- [ ] **Step 1: Write the failing test**

Append to `EntitlementsTests.swift`:

```swift
    /// A missing stamp must resolve to "first launch is now", not to 1970 — otherwise every
    /// existing installation wakes up with an already-expired taster.
    @Test func absentStampMeansTheTasterStartsNow() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let stamp = Entitlements.firstLaunchStamp(stored: 0, now: now)
        #expect(stamp == now)
        #expect(Entitlements.resolve(hasPro: false, firstLaunch: stamp, now: now) == .taster)
    }

    @Test func storedStampIsHonoured() {
        let stored = Date(timeIntervalSince1970: 1_759_000_000)
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        #expect(Entitlements.firstLaunchStamp(stored: stored.timeIntervalSince1970, now: now) == stored)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/EntitlementsTests" 2>&1 | tail -20
```

Expected: FAIL — "type 'Entitlements' has no member 'firstLaunchStamp'".

- [ ] **Step 3: Write minimal implementation**

Append to `Entitlements.swift`:

```swift
extension Entitlements {
    /// `@AppStorage` cannot store an optional `Date`, so the stamp is a `TimeInterval` with `0`
    /// meaning "never written". Treating `0` as 1970 would hand every existing installation an
    /// expired taster on the update that ships this.
    static func firstLaunchStamp(stored: TimeInterval, now: Date = .now) -> Date {
        stored > 0 ? Date(timeIntervalSince1970: stored) : now
    }
}
```

Create `Hair Compass AI 5/Feature/EntitlementsEnvironment.swift`:

```swift
import SwiftUI

private struct EntitlementsKey: EnvironmentKey {
    /// The least-privileged default. A surface that somehow renders outside the injection
    /// should lock, never open.
    static let defaultValue = Entitlements(tier: .free)
}

extension EnvironmentValues {
    var entitlements: Entitlements {
        get { self[EntitlementsKey.self] }
        set { self[EntitlementsKey.self] = newValue }
    }
}
```

In `RootView.swift`, add beside the other `@AppStorage` properties:

```swift
    @AppStorage("firstLaunchAt") private var firstLaunchAt: TimeInterval = 0
```

and a computed value:

```swift
    private var entitlements: Entitlements {
        Entitlements(
            tier: Entitlements.resolve(
                hasPro: purchases.hasPro,
                firstLaunch: Entitlements.firstLaunchStamp(stored: firstLaunchAt)
            )
        )
    }
```

Stamp on first appearance and inject on `styledContent`:

```swift
        .onAppear { if firstLaunchAt == 0 { firstLaunchAt = Date.now.timeIntervalSince1970 } }
        .environment(\.entitlements, entitlements)
```

In `ProGate.swift`, replace `@Environment(PurchaseService.self) private var purchases`'s use at `:35` with:

```swift
    @Environment(\.entitlements) private var entitlements
    ...
    if entitlements.canAccess(feature) {
        content()
    } else {
```

Keep the `PurchaseService` environment for the purchase buttons.

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/App/RootView.swift" "Hair Compass AI 5/Feature/"
git commit -m "Resolve the tier once at the root and hand it down"
```

---

### Task 6: The locked-history card


**Files:**
- Create: `Hair Compass AI 5/Feature/LockedHistoryCard.swift`
- Modify: `Hair Compass AI 5/Feature/TodayView.swift` (insert the card)

**Interfaces:**
- Consumes: `HistoryAccess.lockedCount`, `Entitlements`.
- Produces: `struct LockedHistoryCard: View { let lockedCount: Int; var onUnlock: () -> Void }`.

- [ ] **Step 1: Write the failing test**

Append to `HistoryAccessTests.swift`:

```swift
    /// The card must not render at zero — a brand-new free user should see an empty Today, not
    /// "0 days recorded", which reads as a broken feature rather than an offer.
    @Test func cardVisibilityFollowsTheLockedCount() {
        #expect(LockedHistoryCard.shouldShow(lockedCount: 0) == false)
        #expect(LockedHistoryCard.shouldShow(lockedCount: 1))
        #expect(LockedHistoryCard.shouldShow(lockedCount: 22))
    }

    @Test func cardCopyIsSingularOnTheFirstLockedDay() {
        #expect(LockedHistoryCard.headline(lockedCount: 1) == "1 day recorded")
        #expect(LockedHistoryCard.headline(lockedCount: 22) == "22 days recorded")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/HistoryAccessTests" 2>&1 | tail -20
```

Expected: FAIL — "cannot find 'LockedHistoryCard' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `Hair Compass AI 5/Feature/LockedHistoryCard.swift`:

```swift
import SwiftUI

/// What the free tier sees instead of its own history: a count that grows every day.
///
/// This is the conversion mechanic of the whole free tier. It is deliberately not a locked
/// button — the check-in above it always works, so the number keeps climbing, and the offer
/// gets stronger the longer someone stays. Never show it at zero: "0 days recorded" reads as a
/// bug rather than an invitation.
struct LockedHistoryCard: View {
    let lockedCount: Int
    var onUnlock: () -> Void

    static func shouldShow(lockedCount: Int) -> Bool { lockedCount > 0 }

    static func headline(lockedCount: Int) -> String {
        "\(lockedCount) day\(lockedCount == 1 ? "" : "s") recorded"
    }

    var body: some View {
        if Self.shouldShow(lockedCount: lockedCount) {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .font(Clinical.caption(13))
                            .foregroundStyle(Clinical.tertiary)
                        Text(Self.headline(lockedCount: lockedCount))
                            .font(Clinical.headline(17))
                            .foregroundStyle(Clinical.ink)
                    }
                    Text("You haven't seen any of it yet. Unlock to read your own record.")
                        .font(Clinical.caption(13))
                        .foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Unlock my history", action: onUnlock)
                        .buttonStyle(ClinicalButtonStyle())
                        .accessibilityIdentifier("lockedHistoryUnlock")
                }
            }
            .accessibilityIdentifier("lockedHistoryCard")
        }
    }
}
```

In `TodayView.swift`, add `@Environment(\.entitlements) private var entitlements` and place the card directly beneath the check-in hero:

```swift
LockedHistoryCard(
    lockedCount: HistoryAccess.lockedCount(entries, entitlements: entitlements)
) { showPaywall = true }
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Feature/LockedHistoryCard.swift" "Hair Compass AI 5/Feature/TodayView.swift" "Hair Compass AI 5Tests/HistoryAccessTests.swift"
git commit -m "The counter that grows: locked history on Today"
```

---

### Task 7: Gate the Pro surfaces


**Files:**
- Modify: `Hair Compass AI 5/Feature/TrendsView.swift`, `CompareView.swift`, `JourneyChart.swift`, `PhotosView.swift`, `LabsView.swift`, `ProceduresView.swift`, `CareView.swift`, `ProgressReportSheet.swift`, `BodySignalsDashboard.swift`

**Interfaces:**
- Consumes: `.proGated(_:)` from Task 5.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test**

Append to `EntitlementsTests.swift`:

```swift
    /// Export must survive a lapsed subscription — someone who paid, logged, then churned has
    /// to be able to retrieve their own data (App Store Guideline 3.1.2(a)). It is therefore
    /// deliberately absent from ProFeature, and this test is what stops someone adding it.
    @Test func exportIsNotGateable() {
        #expect(ProFeature.allCases.allSatisfy { $0.gateTitle != "Export" })
    }
```

- [ ] **Step 2: Run the test — it is GREEN on arrival, by design**

**This is a regression guard, not a red-green cycle, and that is deliberate — do not "fix" it into
one.** It cannot fail today because nothing gates Export yet. Its job is to fail *later*, the day
someone adds `case export` to `ProFeature` and silently breaks Guideline 3.1.2(a) compliance for a
lapsed subscriber trying to retrieve their own data. A guard that can only fail in the future is
still worth writing when the failure it prevents is a compliance breach.

Run it, confirm green, record that, and move on.

- [ ] **Step 3: Apply the modifier**

Wrap each view's top-level body content:

```swift
// TrendsView.swift          → .proGated(.trends)
// CompareView.swift         → .proGated(.compare)
// JourneyChart.swift        → .proGated(.journey)
// PhotosView.swift          → .proGated(.photos)
// LabsView.swift            → .proGated(.labs)
// ProceduresView.swift      → .proGated(.procedures)
// CareView.swift            → .proGated(.treatments)
// ProgressReportSheet.swift → .proGated(.reports)
// BodySignalsDashboard.swift→ .proGated(.bodySignals)
```

Apply **inside** each view's own chrome so titles and Close buttons stay reachable, matching how `ProGate` is already used in `HairChatSheet`. Do **not** gate `ExportSheet.swift`, `LearnView.swift`, `RecommenderView.swift`, `ScienceProductsView.swift`, or `InClinicOptionsView.swift`.

- [ ] **Step 4: Verify the full suite and a manual pass**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -30
```

Expected: PASS. Then launch and confirm by hand that Today's check-in still saves on a free tier and every other tab shows its gate.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Feature/"
git commit -m "Apply the wall: nine surfaces behind Pro, export deliberately outside it"
```

---

### Task 8: Widget must not leak locked history


**Files:**
- Modify: `Hair Compass AI 5/App/RootView.swift` (snapshot construction)
- Modify: `Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift` if the struct changes
- Test: `Hair Compass AI 5Tests/HistoryAccessTests.swift`

**Interfaces:**
- Consumes: `Entitlements`, `HistoryAccess`.
- Produces: `static func snapshotEntries(_:entitlements:now:calendar:) -> [DailyEntry]` on `HistoryAccess`.

- [ ] **Step 1: Write the failing test**

```swift
    /// The App Group snapshot is a second read path. Whatever the free tier may not see in-app,
    /// it must not see on the Home Screen either — otherwise the wall leaks through a widget.
    @Test func widgetSnapshotCarriesNoHistoryForFreeUsers() {
        let fed = HistoryAccess.snapshotEntries(entries(past: 22),
                                                entitlements: Entitlements(tier: .free),
                                                now: now)
        #expect(fed.count == 1)
    }

    @Test func widgetSnapshotIsCompleteForPro() {
        let fed = HistoryAccess.snapshotEntries(entries(past: 22),
                                                entitlements: Entitlements(tier: .pro),
                                                now: now)
        #expect(fed.count == 23)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/HistoryAccessTests" 2>&1 | tail -20
```

Expected: FAIL — "type 'HistoryAccess' has no member 'snapshotEntries'".

- [ ] **Step 3: Write minimal implementation**

Append to `HistoryAccess.swift`:

```swift
extension HistoryAccess {
    /// What the widget snapshot is allowed to contain. Identical to `visible`, named separately
    /// because the widget is a distinct read path and a future change to one should be a
    /// deliberate decision about the other.
    static func snapshotEntries(
        _ entries: [DailyEntry],
        entitlements: Entitlements,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DailyEntry] {
        visible(entries, entitlements: entitlements, now: now, calendar: calendar)
    }
}
```

In `RootView.swift`, feed the snapshot builder `HistoryAccess.snapshotEntries(entries, entitlements: entitlements)` instead of `entries`. Add the tier to `widgetFingerprint` so the snapshot rewrites when someone subscribes:

```swift
        return "\(entitlements.tier)-\(entries.count)-..."
```

Make `EntitlementTier` conform to `CustomStringConvertible` or use `String(describing:)`.

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Feature/HistoryAccess.swift" "Hair Compass AI 5/App/RootView.swift" "Hair Compass AI 5Tests/HistoryAccessTests.swift"
git commit -m "Close the widget leak: the wall reaches the Home Screen too"
```

---

### Task 9: Navigation — merge Labs into Plan, promote Shop


**Files:**
- Modify: `Hair Compass AI 5/App/RootView.swift:36-57` (`AppTab`), `:154-164` (`tabContent`)
- Create: `Hair Compass AI 5/Feature/ShopView.swift`
- Modify: `Hair Compass AI 5/Feature/CareView.swift:207,220` (remove shop presentations, absorb Labs)
- Test: `Hair Compass AI 5Tests/EntitlementsTests.swift`

**Interfaces:**
- Consumes: `RecommenderView(condition:sex:onAction:)`, `ScienceProductsSection()`, `InClinicOptionsView()`, `LabsView`.
- Produces: `AppTab` cases `today, shop, trends, care, photos`; `struct ShopView: View`.

- [ ] **Step 1: Write the failing test**

```swift
    /// A free user must land on at least one tab that works, and the shop must be one of them —
    /// it is a revenue surface, not a feature, so it sits outside the wall on purpose.
    @Test func freeUsersGetTwoWorkingTabs() {
        #expect(AppTab.allCases.contains(.shop))
        #expect(AppTab.allCases.contains(.labs) == false, "Labs merged into the Plan tab.")
        #expect(AppTab.allCases.count == 5, "FloatingTabBar is laid out for five items.")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/EntitlementsTests" 2>&1 | tail -20
```

Expected: FAIL — "type 'AppTab' has no member 'shop'".

- [ ] **Step 3: Write minimal implementation**

In `RootView.swift`:

```swift
enum AppTab: String, CaseIterable, Identifiable {
    case today, shop, trends, care, photos
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .shop: return "Shop"
        case .trends: return "Trends"
        case .care: return "Plan"
        case .photos: return "Photos"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "checkmark.circle"
        case .shop: return "bag"
        case .trends: return "chart.xyaxis.line"
        case .care: return "checklist"
        case .photos: return "camera"
        }
    }
}
```

`tabContent` becomes:

```swift
        case .today: TodayView(profile: profile,
                               onOpenBaseline: { showProfileEdit = true },
                               onOpenPlan: { tab = .care })
        case .shop: ShopView()
        case .trends: TrendsView()
        case .care: CareView()
        case .photos: PhotosView()
```

Create `Hair Compass AI 5/Feature/ShopView.swift`. Note the real type names: the products list is
`ScienceProductsSection` (**not** `ScienceProductsView` — that file holds
`ScienceProductsSection`, `ProductRow` and `ManageLinksSheet`), and `RecommenderView` takes
`(condition:sex:onAction:)`.

```swift
import SwiftData
import SwiftUI

/// The storefront, deliberately outside the wall.
///
/// This is a revenue surface, not a feature: an affiliate link earns nothing from someone who
/// cannot reach it, so gating this would cost money rather than make it. It used to live inside
/// `CareView` — which this release puts behind Pro — so it moved here rather than being locked
/// away from exactly the free users it exists to serve.
struct ShopView: View {
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]

    /// Shown above the product list, in body text rather than a footnote — 16 CFR Part 255
    /// wants it clear and conspicuous, and this codebase's honesty rules want it plain.
    static let affiliateDisclosure =
        "Some links here earn us a commission if you buy. It never changes the price you pay, "
        + "and it never affects which products appear or how they're ranked."

    @State private var showInClinicOptions = false

    private var profile: Profile? { profiles.first }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Shop", title: "Products & options")
                    .padding(.top, 8)

                Text(Self.affiliateDisclosure)
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("affiliateDisclosure")

                RecommenderView(condition: profile?.condition ?? .unsure,
                                sex: profile?.sex ?? .male)

                ScienceProductsSection()

                Button("In-clinic options") { showInClinicOptions = true }
                    .buttonStyle(ClinicalButtonStyle(filled: false))
            }
            .padding(.horizontal, 20)
        }
        .clinicalScreen()
        .sheet(isPresented: $showInClinicOptions) { InClinicOptionsView() }
    }
}
```

Remove the `showInClinicOptions` sheet and the `showRecommender` sheet from `CareView.swift`
(`:207` and `:218-226`) along with their `@State` flags, and add `LabsView`'s content as a
section within `CareView` so nothing is lost.

`TutorialOverlay` drives `tab` — check it for a `.labs` reference and repoint it to `.care`.

- [ ] **Step 4: Run the full suite**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -30
```

Expected: PASS. `HC_TAB labs` no longer resolves, which is correct.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/"
git commit -m "Shop takes a tab; Labs joins Plan behind the wall"
```

---

### Task 10: Affiliate disclosure (catalogue deferred)


**Files:**
- Modify: `Hair Compass AI 5/Resources/AffiliateLinks.json`
- Modify: `Hair Compass AI 5/Service/AffiliateStore.swift` (`RemoteConfig.catalogURLString`)
- Modify: `Hair Compass AI 5/Feature/ShopView.swift` (disclosure)
- Test: `Hair Compass AI 5Tests/AffiliateStoreTests.swift`

**Interfaces:**
- Consumes: `AffiliateStore`.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test**

Append to `AffiliateStoreTests.swift`:

```swift
    /// 16 CFR Part 255 requires a clear, conspicuous disclosure wherever an affiliate link is
    /// presented. Asserted here so the shop cannot ship without it.
    @Test func shopCarriesAnAffiliateDisclosure() {
        #expect(ShopView.affiliateDisclosure.isEmpty == false)
        #expect(ShopView.affiliateDisclosure.lowercased().contains("commission"))
    }

    /// Counts ids that resolve across the whole resolution order. It is legitimately ZERO today —
    /// there is no Amazon Associates tag yet, so `AffiliateLinks.json` still ships `"links": {}`
    /// and every buy button stays hidden. Asserting non-empty is deferred with the catalogue
    /// itself; what is asserted here is that the counter reads the store correctly.
    @Test func resolvedLinkCountReflectsTheCatalogue() {
        let store = AffiliateStore(bundledLinks: [:])
        #expect(store.resolvedLinkCount == 0)

        let stocked = AffiliateStore(bundledLinks: ["minoxidil-topical-5": "https://example.com/a"])
        #expect(stocked.resolvedLinkCount == 1)
    }
```

**Scope note — the catalogue itself is deferred.** Filling `AffiliateLinks.json` and setting
`RemoteConfig.catalogURLString` both need a real Amazon Associates tag, which does not exist yet.
This task ships the FTC disclosure and the counter only; the catalogue is listed under "Blocked on
external input". Do **not** invent placeholder links — a key matching no product resolves to
nothing and would make the counter lie.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/haribazri/Hair Compass AI 5"
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hair Compass AI 5Tests/AffiliateStoreTests" 2>&1 | tail -20
```

Expected: FAIL — `ShopView` has no `affiliateDisclosure` if Task 9 did not add it, and
`AffiliateStore` has no `resolvedLinkCount`.

- [ ] **Step 3: Write minimal implementation**

`ShopView.affiliateDisclosure` was added in Task 9 when `ShopView` was created. Verify it is
present and rendered; if not, add it there per Task 9's code block.

Add to `AffiliateStore`:

```swift
    /// How many product ids currently resolve to a link, across every source in the resolution
    /// order. Zero is the honest current answer — there is no Associates tag yet — and this
    /// exists so the moment a catalogue lands, a test can prove the buy buttons actually appear.
    var resolvedLinkCount: Int {
        var ids = Set(bundledLinks.keys)
        ids.formUnion(remoteLinks.keys)
        return ids.filter { link(for: $0) != nil }.count
    }
```

Use whatever the existing per-id lookup is named in place of `link(for:)` — check the file; the
resolution order (debug override → remote cache → bundled → nil) already lives in one method. If
`AffiliateStore.init` does not already accept `bundledLinks:`, it does — see the existing
`init(defaults:bundledLinks:)`, which `AffiliateStoreTests` already uses.

**Leave `AffiliateLinks.json` as `"links": {}` and `RemoteConfig.catalogURLString` as `""`.** Both
need a real Amazon Associates tag. Placeholder links would resolve to nothing, make
`resolvedLinkCount` lie, and risk shipping a dead outbound link in a released build.

**Region routing, recorded rather than decided:** Amazon links are storefront-locked, so a UK tap
on a US link earns nothing. Add a comment at `RemoteConfig` noting the decision is pending until a
tag exists — do not build `Locale`-based routing against a catalogue that is empty.

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Service/AffiliateStore.swift" "Hair Compass AI 5/Feature/ShopView.swift" "Hair Compass AI 5Tests/AffiliateStoreTests.swift"
git commit -m "Disclose what the shop earns, and count what it can resolve"
```

---

## Blocked on external input

These cannot be completed from the codebase and are **not** tasks above:

1. **App Store Connect** — create the 7-day → **14-day** introductory offer on both products, and set $6.99/month and $39.99/year. `PurchaseService.trialDescriptor(for:)` already renders whatever is configured; no Swift change is needed.
2. **Product-ID mismatch with Mohammed** — the app sells `com.harib.haircompass.pro.monthly`; `agent_core/plans.py` joins on `harib.haircompass.pro.monthly`. Raised on PR #1; his side needs the fix.
3. **Amazon Associates account** — needed before `Resources/AffiliateLinks.json` can be filled and
   `RemoteConfig.catalogURLString` pointed at a hosted catalogue. Task 10 deliberately ships the
   disclosure and the counter WITHOUT the links; the catalogue is a follow-on once a tag exists.
   At that point also decide region routing (`Locale.current.region`) or accept the storefront
   mismatch knowingly, and add the non-empty assertion the counter was built for.
