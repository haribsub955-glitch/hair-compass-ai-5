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
}

@MainActor
private final class RitualActivityClientFake: RitualActivityClient, @unchecked Sendable {
    var activitiesEnabled = true
    var endAllCount = 0
    func start(_ snapshot: RitualActivitySnapshot) throws {}
    func update(_ snapshot: RitualActivitySnapshot) async {}
    func endCurrent(_ snapshot: RitualActivitySnapshot, completed: Bool) async {}
    func endAll() async { endAllCount += 1 }
}
