//
//  EntitlementsTests.swift
//  Hair Compass AI 5Tests
//
//  The one table that decides what is free. Every case is asserted
//  explicitly rather than by a rule, so widening the free tier by
//  accident fails a test instead of shipping.
//

import Foundation
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

    /// Export must survive a lapsed subscription — someone who paid, logged, then churned has
    /// to be able to retrieve their own data (App Store Guideline 3.1.2(a)). It is therefore
    /// deliberately absent from ProFeature, and this test is what stops someone adding it.
    @Test func exportIsNotGateable() {
        #expect(ProFeature.allCases.allSatisfy { $0.gateTitle != "Export" })
    }

    /// A free user must land on tabs that actually work, and the shop must be one of them — it is
    /// a revenue surface, not a feature, so it sits outside the wall on purpose.
    ///
    /// This used to assert only the shape of the enum (five cases, no `labs`), which is true of a
    /// build where every tab is free and equally true of one where all five are walled. It now
    /// pins the commercial invariant itself: exactly three of the five tabs are behind a
    /// `ProFeature` the free tier cannot access, and the other two carry no gate at all.
    ///
    /// (The `labs` assertion is written against the raw string deliberately: once `.labs` is
    /// removed as a case, `AppTab.allCases.contains(.labs)` no longer type-checks.)
    @Test func freeUsersGetTwoWorkingTabs() {
        let free = Entitlements(tier: .free)
        let taster = Entitlements(tier: .taster)
        let walledTabs: [AppTab: ProFeature] = [.trends: .trends, .care: .treatments, .photos: .photos]

        for (tab, feature) in walledTabs {
            #expect(free.canAccess(feature) == false,
                    "The \(tab.title) tab is \(feature) — it must be walled on the free tier.")
            #expect(taster.canAccess(feature),
                    "…and open for the taster, which is deliberately identical to Pro.")
        }

        let ungated = Set(AppTab.allCases.filter { walledTabs[$0] == nil })
        #expect(ungated == [.today, .shop],
                "Today (the free product) and Shop (a revenue surface) are the two ungated tabs.")
        #expect(AppTab.allCases.map(\.rawValue).contains("labs") == false, "Labs merged into the Plan tab.")
        #expect(AppTab.allCases.count == 5, "FloatingTabBar is laid out for five items.")
    }

    /// An unresolved StoreKit answer must never downgrade. `hasPro` starts `false` on every cold
    /// launch, and treating that as "not subscribed" briefly renders paywalls over a paid app and
    /// writes a suppressed snapshot into the App Group that outlives the launch if the app is
    /// killed first.
    @Test func anUnresolvedEntitlementFallsBackToTheLastKnownAnswer() {
        // Mid-launch: StoreKit hasn't replied, so last launch's answer stands.
        #expect(Entitlements.effectiveHasPro(resolved: false, current: false, lastKnown: true))
        #expect(Entitlements.effectiveHasPro(resolved: false, current: false, lastKnown: false) == false)
        // Once resolved, the live answer wins in BOTH directions — including a lapse.
        #expect(Entitlements.effectiveHasPro(resolved: true, current: false, lastKnown: true) == false)
        #expect(Entitlements.effectiveHasPro(resolved: true, current: true, lastKnown: false))
    }

    /// A paying subscriber mid-cold-launch resolves to `.pro`, not to the `.free` that four
    /// paywalls and a downgraded widget snapshot would have been rendered from.
    @Test func aSubscriberIsNotDowngradedWhileStoreKitIsStillThinking() {
        let launch = Date(timeIntervalSince1970: 1_760_000_000)
        let tier = Entitlements.resolve(
            hasPro: Entitlements.effectiveHasPro(resolved: false, current: false, lastKnown: true),
            firstLaunch: launch,
            now: day(90, from: launch)   // taster long expired, so only the entitlement can save them
        )
        #expect(tier == .pro)
    }

    #if DEBUG
    /// Every fresh install stamps `firstLaunchAt`, so every fresh install is a `.taster` for three
    /// days — which left the free tier unreachable for QA and for App Review alike. `HC_TIER` is
    /// the way in, and it is asserted here so the QA hook itself can't rot.
    @Test func theTierCanBeForcedForQA() {
        #expect(Entitlements.forcedTier(arguments: ["HC_TIER", "free"]) == .free)
        #expect(Entitlements.forcedTier(arguments: ["HC_TIER", "taster"]) == .taster)
        #expect(Entitlements.forcedTier(arguments: ["HC_SEED_DEMO", "HC_TIER", "pro"]) == .pro)
        #expect(Entitlements.forcedTier(arguments: []) == nil)
        #expect(Entitlements.forcedTier(arguments: ["HC_TIER"]) == nil, "A trailing flag with no value forces nothing.")
        #expect(Entitlements.forcedTier(arguments: ["HC_TIER", "premium"]) == nil, "Unknown tiers are ignored, not guessed.")
    }
    #endif
}
