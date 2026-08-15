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

    /// A free user must land on at least one tab that works, and the shop must be one of them —
    /// it is a revenue surface, not a feature, so it sits outside the wall on purpose.
    ///
    /// The brief's original draft wrote the second assertion as
    /// `AppTab.allCases.contains(.labs) == false` — that no longer compiles once `.labs` is
    /// actually removed as a case (`.labs` isn't a valid `AppTab` literal any more), so it's
    /// rewritten here against the raw string instead, which checks the same thing without
    /// requiring the case to exist in order to type-check.
    @Test func freeUsersGetTwoWorkingTabs() {
        #expect(AppTab.allCases.contains(.shop))
        #expect(AppTab.allCases.map(\.rawValue).contains("labs") == false, "Labs merged into the Plan tab.")
        #expect(AppTab.allCases.count == 5, "FloatingTabBar is laid out for five items.")
    }
}
