//
//  HealthKitBootstrapTests.swift
//  Hair Compass AI 5Tests
//
//  The state machine behind `HealthKitService.bootstrap()`: after the very first session an
//  already-granted user must come back as `.authorized` on every relaunch, not `.notDetermined`
//  (see the 2026-07-21 broken-step audit — without this, HealthKit signals silently stopped
//  updating past session one). `HKAuthorizationRequestStatus.unnecessary` is Apple's own signal
//  that this exact read set has already been asked for, so it's used in place of a hand-rolled
//  "ever connected" flag — it self-corrects on reinstall, where a UserDefaults flag would lie.
//

import Foundation
import HealthKit
import Testing
@testable import Hair_Compass_AI_5

struct HealthKitBootstrapTests {

    @Test func unnecessaryAlwaysResolvesToAuthorized() {
        // The exact bug: a prior-session grant must survive relaunch (current == .notDetermined,
        // HealthKitService.init()'s only possible starting value) as well as any other state.
        #expect(HealthKitService.resolvedAuthorization(for: .unnecessary, current: .notDetermined) == .authorized)
        #expect(HealthKitService.resolvedAuthorization(for: .unnecessary, current: .authorized) == .authorized)
        #expect(HealthKitService.resolvedAuthorization(for: .unnecessary, current: .denied) == .authorized)
    }

    @Test func shouldRequestAlwaysResolvesToNotDetermined() {
        #expect(HealthKitService.resolvedAuthorization(for: .shouldRequest, current: .authorized) == .notDetermined)
        #expect(HealthKitService.resolvedAuthorization(for: .shouldRequest, current: .notDetermined) == .notDetermined)
    }

    @Test func unknownLeavesCurrentStateAlone() {
        // Apple genuinely can't say — a failed/ambiguous check must never demote an already-
        // authorized user back to looking never-asked.
        #expect(HealthKitService.resolvedAuthorization(for: .unknown, current: .authorized) == .authorized)
        #expect(HealthKitService.resolvedAuthorization(for: .unknown, current: .notDetermined) == .notDetermined)
        #expect(HealthKitService.resolvedAuthorization(for: .unknown, current: .denied) == .denied)
    }
}
