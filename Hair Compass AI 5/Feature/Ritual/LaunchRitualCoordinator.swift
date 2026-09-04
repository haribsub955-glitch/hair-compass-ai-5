import Combine
import Foundation
import os

/// Normal launches go directly to the record. Unrelated every-fifth-open games no longer
/// interrupt check-ins. Artwork remains previewable through explicit DEBUG arguments only.
@MainActor final class LaunchRitualCoordinator: ObservableObject {

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "hair-compass", category: "ritual")

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let lastKind = "lastRitualKind"
        static let backgroundedAt = "ritualBackgroundedAt"
    }

    // MARK: Rolls

    /// Old cadence preferences are deliberately ignored, including on existing installs.
    func rollOnLaunch(hasOnboarded: Bool) -> RitualKind? {
        #if DEBUG
        if let forced = debugForcedKind() { return forced }
        if debugAlwaysShow() { return pick() }
        #endif

        return nil
    }

    /// Returning to the app never inserts an unrelated task ahead of the intended destination.
    func rollOnForeground(hasOnboarded: Bool) -> RitualKind? {
        #if DEBUG
        if let forced = debugForcedKind() { return forced }
        #endif
        return nil
    }

    /// Pick a random implemented kind that isn't the last one shown; persist and log it.
    private func pick() -> RitualKind {
        let last = defaults.string(forKey: Key.lastKind)
        let choices = RitualKind.implemented.filter { $0.rawValue != last }
        let pool = choices.isEmpty ? RitualKind.implemented : choices
        let kind = pool.randomElement() ?? .comb
        defaults.set(kind.rawValue, forKey: Key.lastKind)
        logShown(kind)
        return kind
    }

    // MARK: Scene-phase bookkeeping (>4h background re-roll)

    func markBackgrounded(_ date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.backgroundedAt)
    }

    /// True if the app has been backgrounded longer than `threshold` (default 4h).
    func wasBackgroundedLongEnough(now: Date = Date(), threshold: TimeInterval = 4 * 60 * 60) -> Bool {
        let ts = defaults.double(forKey: Key.backgroundedAt)
        guard ts > 0 else { return false }
        return now.timeIntervalSince1970 - ts > threshold
    }

    func clearBackgrounded() {
        defaults.removeObject(forKey: Key.backgroundedAt)
    }

    // MARK: Analytics stub (os.Logger — no analytics SDK in this app)

    func logShown(_ kind: RitualKind) {
        logger.debug("ritual_shown kind=\(kind.rawValue, privacy: .public)")
    }
    func logCompleted(_ kind: RitualKind, duration: TimeInterval) {
        logger.debug("ritual_completed kind=\(kind.rawValue, privacy: .public) duration=\(duration, privacy: .public)")
    }
    func logSkipped(_ kind: RitualKind, at: TimeInterval) {
        logger.debug("ritual_skipped kind=\(kind.rawValue, privacy: .public) at=\(at, privacy: .public)")
    }

    // MARK: DEBUG overrides

    #if DEBUG
    /// `HC_RITUAL_KIND <comb|knot|massage|serum>` forces that kind, bypassing every gate.
    func debugForcedKind() -> RitualKind? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "HC_RITUAL_KIND"), i + 1 < args.count,
              let kind = RitualKind(rawValue: args[i + 1]) else { return nil }
        defaults.set(kind.rawValue, forKey: Key.lastKind)
        logShown(kind)
        return kind
    }

    /// `HC_RITUAL` forces a ritual to always show (still respecting no-repeat).
    func debugAlwaysShow() -> Bool {
        ProcessInfo.processInfo.arguments.contains("HC_RITUAL")
    }
    #endif
}
