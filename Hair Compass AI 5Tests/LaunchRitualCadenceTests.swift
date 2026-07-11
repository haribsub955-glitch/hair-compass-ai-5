//
//  LaunchRitualCadenceTests.swift
//  Hair Compass AI 5Tests
//
//  LaunchRitualCoordinator's every-5th-eligible-open cadence (replaces the old 1-in-3 random
//  roll): opens 1–4 stay quiet, the 5th surfaces a ritual, 6–9 stay quiet, the 10th surfaces one
//  — and the very-first-ever launch (onboarding's own moment) never consumes a count.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct LaunchRitualCadenceTests {

    /// Throwaway defaults so tests never touch the app's real preferences.
    private func makeDefaults() -> (UserDefaults, cleanup: () -> Void) {
        let suite = "ritual-cadence-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    // MARK: - Every 5th eligible open, past the first-launch guard

    @Test func rollOnLaunchShowsOnlyEveryFifthEligibleOpen() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        // Seed past the first-ever-launch guard so every call below is "eligible".
        defaults.set(true, forKey: "hasLaunchedBefore")

        let coordinator = LaunchRitualCoordinator(defaults: defaults)

        for open in 1...4 {
            #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil, "open \(open) should stay quiet")
        }
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) != nil, "open 5 should surface a ritual")

        for open in 6...9 {
            #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil, "open \(open) should stay quiet")
        }
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) != nil, "open 10 should surface a ritual")
    }

    // MARK: - First-ever launch returns nil and does NOT consume a count

    @Test func firstEverLaunchDoesNotConsumeTheOpenCounter() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        // hasLaunchedBefore is unset — this is a genuinely fresh install.

        let coordinator = LaunchRitualCoordinator(defaults: defaults)

        // The very first call is the first-ever launch: always nil, and must not advance the
        // counter (onboarding owns this moment, not the ritual cadence).
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil)

        // If that first-ever-launch call had secretly consumed a count, it would only take 4 more
        // calls to reach n=5. Instead the counter starts fresh at the first *eligible* call, so it
        // takes a full 5 more calls (counts 1–5) — proof the guarded call didn't advance it.
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil) // eligible count 1
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil) // eligible count 2
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil) // eligible count 3
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil) // eligible count 4
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) != nil) // eligible count 5 → surfaces
    }

    // MARK: - hasOnboarded guard still blocks, and still doesn't consume a count

    @Test func notOnboardedNeverShowsAndDoesNotConsumeACount() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        defaults.set(true, forKey: "hasLaunchedBefore")

        let coordinator = LaunchRitualCoordinator(defaults: defaults)

        for _ in 1...10 {
            #expect(coordinator.rollOnLaunch(hasOnboarded: false) == nil)
        }
        // Once onboarded, the counter should start fresh from 1 (not onboarded calls never
        // reached shouldShowOnOpen(), so nothing was consumed) — open 5 is the first non-nil.
        for open in 1...4 {
            #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil, "open \(open) should stay quiet")
        }
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) != nil)
    }

    // MARK: - rollOnForeground shares the same cadence counter as rollOnLaunch

    @Test func rollOnForegroundSharesCadenceWithRollOnLaunch() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        defaults.set(true, forKey: "hasLaunchedBefore")

        let coordinator = LaunchRitualCoordinator(defaults: defaults)

        #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil)      // count 1
        #expect(coordinator.rollOnForeground(hasOnboarded: true) == nil) // count 2
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) == nil)      // count 3
        #expect(coordinator.rollOnForeground(hasOnboarded: true) == nil) // count 4
        #expect(coordinator.rollOnLaunch(hasOnboarded: true) != nil)      // count 5
    }
}
