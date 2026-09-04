import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor struct LaunchRitualCadenceTests {
    @Test func normalLaunchesNeverInterruptEvenWithLegacyCadence() {
        let suite = "ritual-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "hasLaunchedBefore")
        defaults.set(4, forKey: "ritualOpenCount")
        let coordinator = LaunchRitualCoordinator(defaults: defaults)
        for onboarded in [false, true] {
            for _ in 1...20 {
                #expect(coordinator.rollOnLaunch(hasOnboarded: onboarded) == nil)
                #expect(coordinator.rollOnForeground(hasOnboarded: onboarded) == nil)
            }
        }
        #expect(defaults.integer(forKey: "ritualOpenCount") == 4)
    }

    @Test func backgroundBookkeepingStillClears() {
        let suite = "ritual-background-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = LaunchRitualCoordinator(defaults: defaults)
        let now = Date()
        coordinator.markBackgrounded(now.addingTimeInterval(-18_000))
        #expect(coordinator.wasBackgroundedLongEnough(now: now))
        coordinator.clearBackgrounded()
        #expect(!coordinator.wasBackgroundedLongEnough(now: now))
    }
}
