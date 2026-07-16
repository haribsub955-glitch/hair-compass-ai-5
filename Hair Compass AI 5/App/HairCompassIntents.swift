import AppIntents
import Foundation

/// Siri / Shortcuts / Action-button entry point: "Log my hair check-in" opens the app straight to
/// today's check-in. `openAppWhenRun` foregrounds the app; the handoff flag (below) is consumed by
/// `RootView` on activation, reusing the same in-app route the widget's `haircompass://log` uses.
struct LogTodayCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Hair Check-in"
    static var description = IntentDescription("Open Hair Compass to today's hair check-in.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        IntentHandoff.requestLog()
        return .result()
    }
}

/// One-shot handoff between the App Intent (which may run out-of-process) and the app: a flag in
/// the shared App Group defaults that `RootView` reads and clears when it becomes active.
enum IntentHandoff {
    nonisolated static let suiteName = "group.harib.Hair-Compass-AI-5"
    nonisolated static let pendingLogKey = "intent.pendingLog"

    nonisolated static func requestLog() {
        UserDefaults(suiteName: suiteName)?.set(true, forKey: pendingLogKey)
    }

    /// Reads and clears the pending-log flag; returns whether one was set.
    @discardableResult
    nonisolated static func consumePendingLog() -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.bool(forKey: pendingLogKey) else { return false }
        defaults.removeObject(forKey: pendingLogKey)
        return true
    }
}

/// Registers the app's voice/Shortcuts phrases — auto-discovered by the system, no app-side setup.
struct HairCompassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTodayCheckInIntent(),
            phrases: [
                "Log my hair check-in in \(.applicationName)",
                "Open \(.applicationName) check-in",
                "Log today in \(.applicationName)"
            ],
            shortTitle: "Log Check-in",
            systemImageName: "checkmark.circle"
        )
    }
}
