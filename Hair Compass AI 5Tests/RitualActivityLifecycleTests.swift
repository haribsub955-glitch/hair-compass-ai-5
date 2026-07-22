import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct RitualActivityLifecycleTests {
    @Test func expiryUsesHardLimitForInteractiveRitual() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(RitualActivityPolicy.staleDate(startDate: start, estimatedEndDate: nil)
                == start.addingTimeInterval(RitualActivityPolicy.maximumLifetime))
        #expect(RitualActivityPolicy.staleDate(startDate: start,
                                               estimatedEndDate: start.addingTimeInterval(30))
                == start.addingTimeInterval(90))
    }

    @Test func foregroundDecisionEndsInactiveOrUnpresentedRitual() {
        #expect(!RitualActivityPolicy.shouldEnd(isRitualPresented: true, sceneIsActive: true))
        #expect(RitualActivityPolicy.shouldEnd(isRitualPresented: true, sceneIsActive: false))
        #expect(RitualActivityPolicy.shouldEnd(isRitualPresented: false, sceneIsActive: true))
    }

    @Test func launchReconciliationEndsOrphans() async {
        let client = RitualActivityClientFake()
        let service = RitualActivityService(client: client)
        await service.reconcileOrphans()
        #expect(client.endAllCount == 1)
    }

    @Test func hardDeadlineEndsCurrentActivity() async {
        let client = RitualActivityClientFake()
        let scheduler = RitualExpirySchedulerFake()
        let service = RitualActivityService(client: client, expiryScheduler: scheduler)
        let start = Date(timeIntervalSince1970: 1_000)
        service.start(kind: .comb, title: "Comb", startDate: start)

        #expect(scheduler.deadlines == [start.addingTimeInterval(RitualActivityPolicy.maximumLifetime)])
        await scheduler.fireLatest()
        await Task.yield()
        #expect(client.endCurrentCount == 1)
    }

    @Test func earlyEndAndReplacementCancelTheirExpiry() async throws {
        let client = RitualActivityClientFake()
        let scheduler = RitualExpirySchedulerFake()
        let service = RitualActivityService(client: client, expiryScheduler: scheduler)
        service.start(kind: .comb, title: "Comb", startDate: .now)
        let first = try #require(scheduler.cancellations.first)

        service.start(kind: .massage, title: "Massage", startDate: .now)
        #expect(first.isCancelled)
        let second = try #require(scheduler.cancellations.last)

        service.end(stepName: "Massage", progress: 0.5, completed: false)
        #expect(second.isCancelled)
    }
}

@MainActor
private final class RitualActivityClientFake: RitualActivityClient, @unchecked Sendable {
    var activitiesEnabled = true
    var endAllCount = 0
    var endCurrentCount = 0
    func start(_ snapshot: RitualActivitySnapshot) throws {}
    func update(_ snapshot: RitualActivitySnapshot) async {}
    func endCurrent(_ snapshot: RitualActivitySnapshot, completed: Bool) async { endCurrentCount += 1 }
    func endAll() async { endAllCount += 1 }
}

@MainActor
private final class RitualExpirySchedulerFake: RitualExpiryScheduling, @unchecked Sendable {
    final class Cancellation: RitualExpiryCancellation, @unchecked Sendable {
        var isCancelled = false
        func cancel() { isCancelled = true }
    }
    var deadlines: [Date] = []
    var cancellations: [Cancellation] = []
    private var actions: [@MainActor @Sendable () async -> Void] = []

    func schedule(deadline: Date, action: @escaping @MainActor @Sendable () async -> Void)
        -> any RitualExpiryCancellation {
        let cancellation = Cancellation()
        deadlines.append(deadline); cancellations.append(cancellation); actions.append(action)
        return cancellation
    }

    func fireLatest() async { await actions.last?() }
}
