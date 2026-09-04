import Foundation
import Testing
@preconcurrency import UserNotifications
@testable import Hair_Compass_AI_5

struct NotificationRegistryTests {
    @Test @MainActor func routineRequestsCarryTheCompleteActionAndSlot() async {
        let previous = UserDefaults.standard.object(forKey: NotificationService.enabledKey)
        UserDefaults.standard.set(true, forKey: NotificationService.enabledKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: NotificationService.enabledKey)
            } else {
                UserDefaults.standard.removeObject(forKey: NotificationService.enabledKey)
            }
        }

        // Simulates a repeating request installed by the previous app version. Reconciliation
        // must replace it even though the identifier is unchanged, or existing users never see
        // the new action.
        let client = NotificationClientFake(initial: [Self.request("treatment.21:00")])
        let service = NotificationService(client: client)
        await service.reschedule(treatments: [(name: "Minoxidil", slots: ["21:00"])])

        let routine = await client.request(identifier: "treatment.21:00")
        #expect(routine?.content.categoryIdentifier == NotificationService.routineCategoryID)
        #expect(routine?.content.userInfo["slot"] as? String == "21:00")
        let category = await client.category(identifier: NotificationService.routineCategoryID)
        #expect(category?.actions.contains {
            $0.identifier == NotificationService.completeActionID && $0.title == "Mark complete"
        } == true)
    }

    @Test func newerOverlappingPlannerWins() async {
        let client = NotificationClientFake(pendingDelayNanoseconds: 20_000_000)
        let registry = NotificationRegistry(client: client)
        async let old = registry.reconcile(key: "evening", generation: 1, prefixes: ["evening."],
                                           desired: [Self.request("evening.old")], limit: 64)
        try? await Task.sleep(for: .milliseconds(2))
        async let new = registry.reconcile(key: "evening", generation: 2, prefixes: ["evening."],
                                           desired: [Self.request("evening.new")], limit: 64)
        _ = await (old, new)
        #expect(await client.identifiers() == ["evening.new"])
    }

    @Test func cancellationAfterRemovalStillCompletesReplacement() async {
        let client = NotificationClientFake(initial: [Self.request("owned.old")])
        let registry = NotificationRegistry(client: client)
        let task = Task { await registry.reconcile(key: "owned", generation: 1, prefixes: ["owned."],
                                                   desired: [Self.request("owned.new")], limit: 64) }
        task.cancel()
        _ = await task.value
        #expect(await client.identifiers() == ["owned.new"])
    }

    @Test func addFailureIsReported() async {
        let client = NotificationClientFake(failingAdds: ["owned.bad"])
        let result = await NotificationRegistry(client: client).reconcile(
            key: "owned", generation: 1, prefixes: ["owned."], desired: [Self.request("owned.bad")], limit: 64)
        #expect(result.error?.contains("could not be scheduled") == true)
    }

    @Test func addFailureKeepsExistingStillDesiredReminder() async {
        let existing = Self.request("owned.existing")
        let client = NotificationClientFake(initial: [existing], failingAdds: ["owned.new"])
        let result = await NotificationRegistry(client: client).reconcile(
            key: "owned", generation: 1, prefixes: ["owned."],
            desired: [existing, Self.request("owned.new")], limit: 64)

        #expect(result.error?.contains("could not be scheduled") == true)
        #expect(await client.identifiers().contains("owned.existing"))
    }

    @Test func sixtyFourBoundaryCountsForeignRequestsOnce() async {
        let foreign = (0..<63).map { Self.request("foreign.\($0)") }
        let client = NotificationClientFake(initial: foreign)
        let desired = [Self.request("owned.a"), Self.request("owned.b")]
        let result = await NotificationRegistry(client: client).reconcile(
            key: "owned", generation: 1, prefixes: ["owned."], desired: desired, limit: 64)
        #expect(result.acceptedCount == 1)
        #expect(await client.identifiers().count == 64)
    }

    @Test func authorizationChangesAreReadFresh() async {
        let client = NotificationClientFake(statuses: [.denied, .authorized])
        #expect(await client.authorizationStatus() == .denied)
        #expect(await client.authorizationStatus() == .authorized)
    }

    private static func request(_ id: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
    }
}

private actor NotificationClientFake: NotificationCenterClient {
    private var pending: [UNNotificationRequest]
    private var statuses: [UNAuthorizationStatus]
    private var categories: Set<UNNotificationCategory> = []
    private let failingAdds: Set<String>
    private let pendingDelayNanoseconds: UInt64

    init(initial: [UNNotificationRequest] = [], statuses: [UNAuthorizationStatus] = [.authorized],
         failingAdds: Set<String> = [], pendingDelayNanoseconds: UInt64 = 0) {
        pending = initial; self.statuses = statuses; self.failingAdds = failingAdds
        self.pendingDelayNanoseconds = pendingDelayNanoseconds
    }
    func authorizationStatus() async -> UNAuthorizationStatus {
        if statuses.count > 1 { return statuses.removeFirst() }
        return statuses.first ?? .notDetermined
    }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func setCategories(_ categories: Set<UNNotificationCategory>) async {
        self.categories = categories
    }
    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        if pendingDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: pendingDelayNanoseconds) }
        return pending
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        pending.removeAll { identifiers.contains($0.identifier) }
    }
    func add(_ request: UNNotificationRequest) async throws {
        if failingAdds.contains(request.identifier) { throw CocoaError(.fileWriteUnknown) }
        pending.removeAll { $0.identifier == request.identifier }; pending.append(request)
    }
    func identifiers() -> [String] { pending.map(\.identifier).sorted() }
    func request(identifier: String) -> UNNotificationRequest? {
        pending.first { $0.identifier == identifier }
    }
    func category(identifier: String) -> UNNotificationCategory? {
        categories.first { $0.identifier == identifier }
    }
}
