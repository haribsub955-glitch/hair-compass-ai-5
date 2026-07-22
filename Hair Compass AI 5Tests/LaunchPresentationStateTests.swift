import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct LaunchPresentationStateTests {
    private struct Case: CustomStringConvertible {
        let name: String
        let input: LaunchPresentationState.Input
        let expected: LaunchPresentationState.Surface

        var description: String { name }
    }

    @Test func launchSurfacePrecedenceTable() {
        let clear = LaunchPresentationState.Input(
            persistenceFailed: false,
            isLocked: false,
            hasOnboarded: true,
            hasPendingRoute: false,
            hasSeenTutorial: true,
            ritualDueOrForced: false,
            appActive: true
        )
        let cases: [Case] = [
            Case(name: "persistence recovery wins over every other request",
                 input: .init(persistenceFailed: true, isLocked: true,
                              hasOnboarded: false, hasPendingRoute: true,
                              hasSeenTutorial: false, ritualDueOrForced: true, appActive: false),
                 expected: .persistenceRecovery),
            Case(name: "privacy wins while the app is inactive",
                 input: .init(persistenceFailed: false, isLocked: true,
                              hasOnboarded: false, hasPendingRoute: true,
                              hasSeenTutorial: false, ritualDueOrForced: true, appActive: false),
                 expected: .privacy),
            Case(name: "lock wins over every active in-app request",
                 input: .init(persistenceFailed: false, isLocked: true,
                              hasOnboarded: false, hasPendingRoute: true,
                              hasSeenTutorial: false, ritualDueOrForced: true, appActive: true),
                 expected: .lock),
            Case(name: "onboarding wins over a pending route tutorial and ritual",
                 input: .init(persistenceFailed: false, isLocked: false,
                              hasOnboarded: false, hasPendingRoute: true,
                              hasSeenTutorial: false, ritualDueOrForced: true, appActive: true),
                 expected: .onboarding),
            Case(name: "pending route wins over tutorial and ritual",
                 input: .init(persistenceFailed: false, isLocked: false,
                              hasOnboarded: true, hasPendingRoute: true,
                              hasSeenTutorial: false, ritualDueOrForced: true, appActive: true),
                 expected: .pendingRoute),
            Case(name: "tutorial wins over ritual",
                 input: .init(persistenceFailed: false, isLocked: false,
                              hasOnboarded: true, hasPendingRoute: false,
                              hasSeenTutorial: false, ritualDueOrForced: true, appActive: true),
                 expected: .tutorial),
            Case(name: "ritual appears only when every higher request is clear",
                 input: .init(persistenceFailed: false, isLocked: false,
                              hasOnboarded: true, hasPendingRoute: false,
                              hasSeenTutorial: true, ritualDueOrForced: true, appActive: true),
                 expected: .ritual),
            Case(name: "normal appears only when all requests are clear",
                 input: clear,
                 expected: .normal)
        ]

        for testCase in cases {
            #expect(LaunchPresentationState.reduce(testCase.input).surface == testCase.expected,
                    "\(testCase)")
        }
    }

    @Test func ritualNeverAppearsOverLockOrOnboarding() {
        let locked = LaunchPresentationState.Input(
            persistenceFailed: false, isLocked: true, hasOnboarded: true,
            hasPendingRoute: false, hasSeenTutorial: true, ritualDueOrForced: true,
            appActive: true
        )
        let onboarding = LaunchPresentationState.Input(
            persistenceFailed: false, isLocked: false, hasOnboarded: false,
            hasPendingRoute: false, hasSeenTutorial: true, ritualDueOrForced: true,
            appActive: true
        )

        #expect(LaunchPresentationState.reduce(locked).surface == .lock)
        #expect(LaunchPresentationState.reduce(onboarding).surface == .onboarding)
    }

    @Test func pendingDeepLinkSurvivesLockedLaunch() {
        var input = LaunchPresentationState.Input(
            persistenceFailed: false, isLocked: true, hasOnboarded: true,
            hasPendingRoute: true, hasSeenTutorial: false, ritualDueOrForced: true,
            appActive: true
        )

        #expect(LaunchPresentationState.reduce(input).surface == .lock)
        #expect(input.hasPendingRoute)

        input.isLocked = false
        #expect(LaunchPresentationState.reduce(input).surface == .pendingRoute)
        #expect(input.hasPendingRoute)
    }

    @MainActor
    @Test func urlRouteIsRecordedDuringOnboardingAndConsumedAfterward() throws {
        let router = DeepLinkRouter()
        let destination = try #require(DeepLinkRouter.destination(for: URL(string: "haircompass://log")!))

        router.record(destination)
        #expect(router.openLogRequested)
        #expect(!router.consumeLogRequest())
        #expect(router.openLogRequested)

        router.canConsumeRoutes = true
        #expect(router.consumeLogRequest())
        #expect(!router.openLogRequested)
    }

    @MainActor
    @Test func pendingRouteIsNotConsumedWhileLocked() {
        let router = DeepLinkRouter()
        router.openProceduresRequested = true

        #expect(!router.consumeProceduresRequest())
        #expect(router.openProceduresRequested)

        router.canConsumeRoutes = true
        #expect(router.consumeProceduresRequest())
        #expect(!router.openProceduresRequested)
    }

    @Test func reducerAlwaysYieldsExactlyOneSurface() {
        for mask in 0..<(1 << 7) {
            let input = LaunchPresentationState.Input(
                persistenceFailed: mask & 1 != 0,
                isLocked: mask & 2 != 0,
                hasOnboarded: mask & 4 != 0,
                hasPendingRoute: mask & 8 != 0,
                hasSeenTutorial: mask & 16 != 0,
                ritualDueOrForced: mask & 32 != 0,
                appActive: mask & 64 != 0
            )
            let result = LaunchPresentationState.reduce(input)
            let surfaced = [
                .persistenceRecovery, .privacy, .lock, .onboarding,
                .pendingRoute, .tutorial, .ritual, .normal
            ].filter { $0 == result.surface }
            #expect(surfaced.count == 1, "mask \(mask) must select exactly one top surface")
        }
    }
}
