import ActivityKit
import Foundation

struct RitualActivitySnapshot: Sendable, Equatable {
    var kind: RitualKind
    var title: String
    var startDate: Date
    var stepName: String
    var progress: Double
    var endDate: Date?
    var staleDate: Date
}

protocol RitualActivityClient: Sendable {
    @MainActor var activitiesEnabled: Bool { get }
    @MainActor func start(_ snapshot: RitualActivitySnapshot) throws
    @MainActor func update(_ snapshot: RitualActivitySnapshot) async
    @MainActor func endCurrent(_ snapshot: RitualActivitySnapshot, completed: Bool) async
    @MainActor func endAll() async
}

protocol RitualExpiryCancellation: Sendable {
    func cancel()
}

@MainActor
protocol RitualExpiryScheduling: Sendable {
    func schedule(deadline: Date, action: @escaping @MainActor @Sendable () async -> Void)
        -> any RitualExpiryCancellation
}

private final class RitualExpiryTask: RitualExpiryCancellation, @unchecked Sendable {
    let task: Task<Void, Never>
    init(task: Task<Void, Never>) { self.task = task }
    func cancel() { task.cancel() }
}

@MainActor
private struct SystemRitualExpiryScheduler: RitualExpiryScheduling {
    func schedule(deadline: Date, action: @escaping @MainActor @Sendable () async -> Void)
        -> any RitualExpiryCancellation {
        let task = Task { @MainActor in
            let delay = max(0, deadline.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            await action()
        }
        return RitualExpiryTask(task: task)
    }
}

@MainActor
final class ActivityKitRitualClient: RitualActivityClient, @unchecked Sendable {
    private var activity: Activity<RitualActivityAttributes>?
    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(_ snapshot: RitualActivitySnapshot) throws {
        let attributes = RitualActivityAttributes(ritualName: snapshot.title,
                                                  ritualKind: snapshot.kind.rawValue,
                                                  startDate: snapshot.startDate)
        activity = try Activity.request(attributes: attributes, content: content(snapshot), pushType: nil)
    }
    func update(_ snapshot: RitualActivitySnapshot) async { await activity?.update(content(snapshot)) }
    func endCurrent(_ snapshot: RitualActivitySnapshot, completed: Bool) async {
        guard let activity else { return }
        self.activity = nil
        let policy: ActivityUIDismissalPolicy = completed
            ? .after(Date().addingTimeInterval(3)) : .immediate
        await activity.end(content(snapshot), dismissalPolicy: policy)
    }
    func endAll() async {
        activity = nil
        for orphan in Activity<RitualActivityAttributes>.activities {
            await orphan.end(nil, dismissalPolicy: .immediate)
        }
    }
    private func content(_ snapshot: RitualActivitySnapshot) -> ActivityContent<RitualActivityAttributes.ContentState> {
        let state = RitualActivityAttributes.ContentState(stepName: snapshot.stepName, stepIndex: 1,
                                                          totalSteps: 1, progress: snapshot.progress,
                                                          endDate: snapshot.endDate)
        return ActivityContent(state: state, staleDate: snapshot.staleDate)
    }
}

enum RitualActivityPolicy {
    /// Interactive rituals have no estimated end. Ten minutes is deliberately longer than a
    /// normal ritual but short enough that a force-quit cannot leave an all-day system surface.
    static let maximumLifetime: TimeInterval = 10 * 60

    static func staleDate(startDate: Date, estimatedEndDate: Date?) -> Date {
        let hardLimit = startDate.addingTimeInterval(maximumLifetime)
        guard let estimatedEndDate else { return hardLimit }
        return min(hardLimit, estimatedEndDate.addingTimeInterval(60))
    }

    static func shouldEnd(isRitualPresented: Bool, sceneIsActive: Bool) -> Bool {
        !isRitualPresented || !sceneIsActive
    }
}

/// Best-effort local lifecycle coordinator. ActivityKit remains at the small client boundary;
/// expiry and foreground/orphan decisions are pure and unit-testable.
@MainActor
final class RitualActivityService {
    static let shared = RitualActivityService()
    private let client: any RitualActivityClient
    private let expiryScheduler: any RitualExpiryScheduling
    private var snapshot: RitualActivitySnapshot?
    private var expiryCancellation: (any RitualExpiryCancellation)?
    private var expiryID: UUID?
    private var lastUpdateAt: Date?
    private let minUpdateInterval: TimeInterval = 0.25

    init(client: (any RitualActivityClient)? = nil,
         expiryScheduler: (any RitualExpiryScheduling)? = nil) {
        self.client = client ?? ActivityKitRitualClient()
        self.expiryScheduler = expiryScheduler ?? SystemRitualExpiryScheduler()
    }

    func reconcileOrphans() async {
        // An activation task can race a newly presented RitualView. Once this process owns a
        // current snapshot it is not an orphan and must not be swept away.
        guard snapshot == nil else { return }
        cancelExpiry()
        await client.endAll()
    }

    func start(kind: RitualKind, title: String, startDate: Date) {
        cancelExpiry()
        guard client.activitiesEnabled else { return }
        let value = RitualActivitySnapshot(kind: kind, title: title, startDate: startDate,
            stepName: title, progress: 0, endDate: nil,
            staleDate: RitualActivityPolicy.staleDate(startDate: startDate, estimatedEndDate: nil))
        do {
            try client.start(value)
            snapshot = value; lastUpdateAt = nil
            scheduleExpiry(at: startDate.addingTimeInterval(RitualActivityPolicy.maximumLifetime))
        } catch { snapshot = nil }
    }

    func update(stepName: String, progress: Double, endDate: Date?) {
        guard var value = snapshot else { return }
        let clamped = min(1, max(0, progress)); let now = Date()
        if let lastUpdateAt, now.timeIntervalSince(lastUpdateAt) < minUpdateInterval, clamped < 1 { return }
        self.lastUpdateAt = now
        value.stepName = stepName; value.progress = clamped; value.endDate = endDate
        value.staleDate = RitualActivityPolicy.staleDate(startDate: value.startDate, estimatedEndDate: endDate)
        snapshot = value
        Task { await client.update(value) }
    }

    func end(stepName: String, progress: Double, completed: Bool) {
        cancelExpiry()
        guard var value = snapshot else { return }
        snapshot = nil
        value.stepName = completed ? "Complete" : stepName
        value.progress = completed ? 1 : min(1, max(0, progress)); value.endDate = nil
        value.staleDate = Date()
        Task { await client.endCurrent(value, completed: completed) }
    }

    func ritualStoppedBeingForeground() {
        guard snapshot != nil else { return }
        end(stepName: snapshot?.stepName ?? "Ritual", progress: snapshot?.progress ?? 0, completed: false)
    }


    private func scheduleExpiry(at deadline: Date) {
        let id = UUID()
        expiryID = id
        expiryCancellation = expiryScheduler.schedule(deadline: deadline) { [weak self] in
            self?.expire(id: id)
        }
    }

    private func cancelExpiry() {
        expiryCancellation?.cancel()
        expiryCancellation = nil
        expiryID = nil
    }

    private func expire(id: UUID) {
        guard expiryID == id, let value = snapshot else { return }
        expiryCancellation = nil
        expiryID = nil
        snapshot = nil
        var expired = value
        expired.endDate = nil
        expired.staleDate = Date()
        Task { await client.endCurrent(expired, completed: false) }
    }
}
