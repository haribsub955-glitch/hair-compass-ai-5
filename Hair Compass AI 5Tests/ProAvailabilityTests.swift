//
//  ProAvailabilityTests.swift
//  Hair Compass AI 5Tests
//
//  The paywall's availability gate. Oracle source: App Review rejection of build 4
//  (Guidelines 2.1 App Completeness + 3.1.2 Subscriptions, 2026-08) — a subscription must not
//  be sold in a state where its features cannot run on this device right now. The pre-fix
//  behavior (sell in .notEnabled/.modelNotReady) fails `sellableOnlyWhenModelCanActuallyRun`.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct ProAvailabilityTests {

    // MARK: - The purchase gate

    @Test func sellableOnlyWhenModelCanActuallyRun() {
        #expect(ProAvailability.sellable(.available))
        #expect(!ProAvailability.sellable(.notEnabled))
        #expect(!ProAvailability.sellable(.modelNotReady))
        #expect(!ProAvailability.sellable(.deviceNotEligible))
    }

    // MARK: - Paywall copy contract

    /// Every withheld state explains itself; `.available` adds nothing above the buttons.
    @Test func everyUnavailableStateCarriesAnActionableMessage() {
        #expect(ProAvailability.message(for: .available).isEmpty)
        for status: OnDeviceAvailability in [.notEnabled, .modelNotReady, .deviceNotEligible] {
            #expect(!ProAvailability.message(for: status).isEmpty)
        }
    }

    /// The fixable state must carry the manual Settings path in words — there is no
    /// "Open Settings" button anymore (`UIApplication.openSettingsURLString` opens this app's
    /// own settings page, not Apple Intelligence & Siri, so a button would mislead).
    @Test func notEnabledCopyNamesTheSettingsPath() {
        #expect(ProAvailability.message(for: .notEnabled).contains("Apple Intelligence & Siri"))
    }

    /// The permanent state says the honest things: what's required, that paying here would buy
    /// nothing, and that the rest of the app stays free. Losing any turns the notice into a trap.
    @Test func deviceNotEligibleCopySaysItIsPermanent() {
        let msg = ProAvailability.message(for: .deviceNotEligible)
        #expect(msg.contains("Apple Intelligence"))
        #expect(msg.contains("wouldn't work"))
        #expect(msg.lowercased().contains("free"))
    }
}
