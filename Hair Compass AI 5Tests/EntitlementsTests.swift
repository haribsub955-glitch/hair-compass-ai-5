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
