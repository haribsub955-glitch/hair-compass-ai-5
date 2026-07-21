import ActivityKit
import Foundation

/// Starts/updates/ends the Ritual Live Activity (Dynamic Island + Lock Screen) that mirrors a
/// launch ritual (Feature/Ritual/RitualView.swift) while it's on screen. Entirely local — no push
/// updates, `pushType: nil` throughout — and entirely best-effort: every entry point silently
/// no-ops when Live Activities are unavailable/disabled or the OS refuses the request, so a
/// ritual's own animation/haptics/completion flow never stalls or crashes because of ActivityKit.
@MainActor
final class RitualActivityService {
    static let shared = RitualActivityService()
    private init() {}

    private var activity: Activity<RitualActivityAttributes>?

    /// Throttle: `RitualView`'s canvas steps every animation frame (~60/s), but ActivityKit
    /// updates are rate-limited by the system — never push more than a handful of updates a
    /// second. The very first and terminal (progress >= 1) updates always bypass the throttle so
    /// the Dynamic Island never misses a ritual's start or its completed frame.
    private var lastUpdateAt: Date?
    private let minUpdateInterval: TimeInterval = 0.25

    /// Begin tracking a ritual. Fails silently (no permission, Live Activities off in Settings,
    /// simulator without support, over the OS's concurrent-activity limit, ...) — the ritual
    /// itself never depends on this succeeding.
    func start(kind: RitualKind, title: String, startDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Defensive cleanup: a previous run that crashed or was force-quit mid-ritual could have
        // left an orphaned activity behind (its own `end` never ran) — clear those before
        // starting a fresh one so Live Activities never pile up.
        for stale in Activity<RitualActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }

        let attributes = RitualActivityAttributes(ritualName: title, ritualKind: kind.rawValue, startDate: startDate)
        let state = RitualActivityAttributes.ContentState(
            stepName: title, stepIndex: 1, totalSteps: 1, progress: 0, endDate: nil)

        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        lastUpdateAt = nil
    }

    /// Push a new content state. Throttled (see `minUpdateInterval`); a no-op if `start` never
    /// produced an activity (Live Activities unavailable, request refused, ...).
    func update(stepName: String, progress: Double, endDate: Date?) {
        guard let activity else { return }
        let clamped = min(1, max(0, progress))
        let now = Date()
        if let last = lastUpdateAt, now.timeIntervalSince(last) < minUpdateInterval, clamped < 1 { return }
        lastUpdateAt = now

        let state = RitualActivityAttributes.ContentState(
            stepName: stepName, stepIndex: 1, totalSteps: 1, progress: clamped, endDate: endDate)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// End the activity. `completed` finishes at 100% and lingers briefly (`.after`) so a glance
    /// at the Lock Screen/Dynamic Island still catches the "done" frame; a skip/cancel dismisses
    /// immediately since there's nothing left worth showing.
    func end(stepName: String, progress: Double, completed: Bool) {
        guard let activity else { return }
        self.activity = nil

        let state = RitualActivityAttributes.ContentState(
            stepName: completed ? "Complete" : stepName,
            stepIndex: 1, totalSteps: 1,
            progress: completed ? 1 : min(1, max(0, progress)),
            endDate: nil
        )
        let policy: ActivityUIDismissalPolicy = completed ? .after(Date().addingTimeInterval(3)) : .immediate
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy) }
    }
}
