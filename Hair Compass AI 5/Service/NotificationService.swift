import Foundation
import UserNotifications

/// Local (on-device) reminders that keep a person on their routine: a repeating notification at
/// each active daily treatment's slot time, a refill heads-up, and a monthly photo prompt — all
/// under the Plan tab's "Reminders" toggle (`reschedule()`). The evening check-in nudge
/// (`planEveningCheckIn`) is a separate, opt-in, user-timed reminder — see its doc comment. No
/// server, no data leaves the phone.
@MainActor
@Observable
final class NotificationService {
    static let enabledKey = "remindersEnabled"

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private let center = UNUserNotificationCenter.current()

    private let treatmentPrefix = "treatment."
    private let refillPrefix = "refill."
    private let photoReminderID = "photoReminder"
    private let eveningCheckInPrefix = "eveningCheckIn."

    /// Coalescing guard for `reschedule()` (audit #5): a second call cancels the first's task
    /// before it starts a fresh remove+add sequence, so a stale removeAll from an old call can
    /// never race an add from a newer one — latest call always wins.
    private var rescheduleTask: Task<Void, Never>?

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Requests notification permission if it hasn't been decided yet, otherwise just reports
    /// the current grant state. Shared by any feature that needs permission before scheduling —
    /// independent of which toggle/UserDefaults flag that feature owns.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let granted: Bool
        if authorization == .notDetermined {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        } else {
            granted = authorization == .authorized || authorization == .provisional
        }
        await refreshAuthorization()
        return granted
    }

    /// Turn reminders on: request permission if needed, then schedule. Returns whether it's on.
    @discardableResult
    func enable(
        treatments: [(name: String, slots: [String])],
        refills: [(name: String, refillBy: Date)] = []
    ) async -> Bool {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return false
        }
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        await reschedule(treatments: treatments, refills: refills)
        return true
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        center.removeAllPendingNotificationRequests()
    }

    /// Replace all scheduled reminders with fresh ones for the current active daily treatments.
    /// No-op when reminders are off, so callers can fire it freely whenever treatments change.
    func reschedule(
        treatments: [(name: String, slots: [String])],
        refills: [(name: String, refillBy: Date)] = []
    ) async {
        rescheduleTask?.cancel()
        let task = Task { [weak self] in
            // Explicit guard rather than `self?.…` — optional-chaining a Void-returning async
            // call infers `Void?`, which would mismatch the declared `Task<Void, Never>` below.
            guard let self else { return }
            await self.performReschedule(treatments: treatments, refills: refills)
        }
        rescheduleTask = task
        await task.value
    }

    /// The actual remove+add sequence, isolated so `reschedule()` can coalesce overlapping
    /// calls into a single in-flight `Task` (see `rescheduleTask`).
    private func performReschedule(
        treatments: [(name: String, slots: [String])],
        refills: [(name: String, refillBy: Date)]
    ) async {
        guard isEnabled, authorization == .authorized || authorization == .provisional else { return }
        center.removeAllPendingNotificationRequests()
        guard !Task.isCancelled else { return }

        for (i, t) in treatments.enumerated() {
            for slot in t.slots {
                guard let comps = Self.components(from: slot) else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Hair Compass"
                content.body = "Time for your \(t.name)."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = UNNotificationRequest(identifier: "\(treatmentPrefix)\(i).\(slot)", content: content, trigger: trigger)
                try? await center.add(request)
            }
        }

        // One-off refill heads-up, 7 days before each refill-by date at 10:00. Skipped when
        // that moment is already past — the in-app chip carries urgent/overdue from there.
        for (i, r) in refills.enumerated() {
            guard let fireDate = Self.refillReminderDate(for: r.refillBy), fireDate > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Running low soon"
            content.body = "Your \(r.name) supply runs out around \(r.refillBy.formatted(date: .abbreviated, time: .omitted)). A good week to arrange a refill."
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "\(refillPrefix)\(i)", content: content, trigger: trigger)
            try? await center.add(request)
        }

        // Monthly photo prompt — a comparable set on the 1st of each month.
        var monthly = DateComponents(); monthly.day = 1; monthly.hour = 10
        let photo = UNMutableNotificationContent()
        photo.title = "Monthly photos"
        photo.body = "Capture your five regions for a comparable set — same lighting and angle as last time."
        photo.sound = .default
        let photoRequest = UNNotificationRequest(
            identifier: photoReminderID,
            content: photo,
            trigger: UNCalendarNotificationTrigger(dateMatching: monthly, repeats: true)
        )
        try? await center.add(photoRequest)
    }

    /// Implementation-intention evening reminder (research: a user-chosen time beats generic
    /// smart timing, and caps at ≤1/day keep retention high). Independent of the routine
    /// "Reminders" toggle above — OFF until the Plan tab's evening-check-in toggle turns it on.
    /// Schedules up to 3 non-repeating reminders (today + the next two days) at `time`, skipping
    /// today when `hasLoggedToday` so a logged day is never nagged. Invitation-toned, never
    /// guilt: streak-aware once a streak exists, otherwise a plain, calm invite.
    func planEveningCheckIn(enabled: Bool, time: DateComponents, hasLoggedToday: Bool, streak: Int) async {
        let ids = (0..<3).map { "\(eveningCheckInPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled, authorization == .authorized || authorization == .provisional else { return }

        let calendar = Calendar.current
        let body = streak >= 3
            ? "Day \(streak + 1) is a 20-second check-in away."
            : "Ready for tonight's check-in? 20 seconds keeps your chart honest."

        for offset in 0..<3 {
            if offset == 0 && hasLoggedToday { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: .now) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = time.hour
            comps.minute = time.minute
            guard let fireDate = calendar.date(from: comps), fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Hair Compass"
            content.body = body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: "\(eveningCheckInPrefix)\(offset)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// 10:00 local time, 7 days before the refill-by date. nil if the calendar math fails.
    static func refillReminderDate(for refillBy: Date, calendar: Calendar = .current) -> Date? {
        guard let weekBefore = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: refillBy)) else { return nil }
        return calendar.date(byAdding: .hour, value: 10, to: weekBefore)
    }

    /// "08:00" → hour/minute DateComponents for a repeating daily trigger.
    static func components(from slot: String) -> DateComponents? {
        let parts = slot.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var comps = DateComponents(); comps.hour = h; comps.minute = m
        return comps
    }
}
