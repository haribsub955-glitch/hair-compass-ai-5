//
//  HealthKitBootstrapTests.swift
//  Hair Compass AI 5Tests
//
//  The state machine behind `HealthKitService.bootstrap()`: after the very first session an
//  a previously presented request must come back as queryable on relaunch, without claiming
//  that any read type was authorized
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

    @Test func unnecessaryMeansRequestedQueryableNotAuthorized() {
        // A prior request must survive relaunch while remaining truthful about hidden grants.
        #expect(HealthKitService.resolvedAuthorization(for: .unnecessary, current: .notRequested) == .requestedQueryable)
        #expect(HealthKitService.resolvedAuthorization(for: .unnecessary, current: .requestedQueryable) == .requestedQueryable)
    }

    @Test func shouldRequestAlwaysResolvesToNotRequested() {
        #expect(HealthKitService.resolvedAuthorization(for: .shouldRequest, current: .requestedQueryable) == .notRequested)
        #expect(HealthKitService.resolvedAuthorization(for: .shouldRequest, current: .notRequested) == .notRequested)
    }

    @Test func unknownLeavesCurrentStateAlone() {
        // Apple genuinely can't say — a failed/ambiguous check must never demote an already-
        // authorized user back to looking never-asked.
        #expect(HealthKitService.resolvedAuthorization(for: .unknown, current: .requestedQueryable) == .requestedQueryable)
        #expect(HealthKitService.resolvedAuthorization(for: .unknown, current: .notRequested) == .notRequested)
    }
}
