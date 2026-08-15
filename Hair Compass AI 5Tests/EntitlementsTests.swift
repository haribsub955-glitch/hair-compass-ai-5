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
}
