import Foundation
import UserNotifications

/// Local (on-device) reminders that keep a person on their routine: a repeating notification at each
/// active daily treatment's slot time, plus a gentle evening nudge to log the day. No server, no
/// data leaves the phone. One toggle on the Plan tab drives it.
@MainActor
@Observable
final class NotificationService {
    static let enabledKey = "remindersEnabled"

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private let center = UNUserNotificationCenter.current()

    private let treatmentPrefix = "treatment."
    private let logNudgeID = "logNudge"
    private let photoReminderID = "photoReminder"

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Turn reminders on: request permission if needed, then schedule. Returns whether it's on.
    @discardableResult
    func enable(treatments: [(name: String, slots: [String])]) async -> Bool {
        let granted: Bool
        if authorization == .notDetermined {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        } else {
            granted = authorization == .authorized || authorization == .provisional
        }
        await refreshAuthorization()
        guard granted else {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return false
        }
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        await reschedule(treatments: treatments)
        return true
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        center.removeAllPendingNotificationRequests()
    }

    /// Replace all scheduled reminders with fresh ones for the current active daily treatments.
    /// No-op when reminders are off, so callers can fire it freely whenever treatments change.
    func reschedule(treatments: [(name: String, slots: [String])]) async {
        guard isEnabled, authorization == .authorized || authorization == .provisional else { return }
        center.removeAllPendingNotificationRequests()

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

        // Evening nudge to log the day and protect the streak.
        var evening = DateComponents(); evening.hour = 20; evening.minute = 30
        let nudge = UNMutableNotificationContent()
        nudge.title = "How was today?"
        nudge.body = "Log your check-in to keep your streak going."
        nudge.sound = .default
        let nudgeRequest = UNNotificationRequest(
            identifier: logNudgeID,
            content: nudge,
            trigger: UNCalendarNotificationTrigger(dateMatching: evening, repeats: true)
        )
        try? await center.add(nudgeRequest)

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

    /// "08:00" → hour/minute DateComponents for a repeating daily trigger.
    static func components(from slot: String) -> DateComponents? {
        let parts = slot.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var comps = DateComponents(); comps.hour = h; comps.minute = m
        return comps
    }
}
