import Combine
import Foundation
import os

/// Owns the launch-ritual trigger decision: the 1/3 roll, the never-repeat rule, the first-launch
/// guard, and the >4h-background re-roll bookkeeping. There is no analytics service in this app, so
/// the `ritual_shown / _completed / _skipped` events are stubbed as `os.Logger` debug lines.
@MainActor final class LaunchRitualCoordinator: ObservableObject {

    /// Probability a ritual is shown on an eligible launch. `static var` so it stays tweakable
    /// (a remote-config hook could set it). Prototype exposed every-launch / 1-in-2 / 1-in-3.
    static var frequency: Double = 1.0 / 3.0

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "hair-compass", category: "ritual")

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let lastKind = "lastRitualKind"
        static let launchedBefore = "hasLaunchedBefore"
        static let backgroundedAt = "ritualBackgroundedAt"
    }

    // MARK: Rolls

    /// Decide whether to show a ritual on this cold launch. Returns nil on first-ever launch, when
    /// not onboarded, or when the probability roll fails. DEBUG overrides bypass all of that.
    func rollOnLaunch(hasOnboarded: Bool) -> RitualKind? {
        #if DEBUG
        if let forced = debugForcedKind() { return forced }
        if debugAlwaysShow() { return pick() }
        #endif

        // First-ever launch: mark it and never show (onboarding owns the first run).
        if !defaults.bool(forKey: Key.launchedBefore) {
            defaults.set(true, forKey: Key.launchedBefore)
            return nil
        }
        guard hasOnboarded else { return nil }
        guard Double.random(in: 0..<1) < Self.frequency else { return nil }
        return pick()
    }

    /// Re-roll when returning to the foreground after a long background. Same probability rules,
    /// but the first-launch guard is moot (we've obviously launched before).
    func rollOnForeground(hasOnboarded: Bool) -> RitualKind? {
        #if DEBUG
        if let forced = debugForcedKind() { return forced }
        #endif
        guard hasOnboarded else { return nil }
        guard Double.random(in: 0..<1) < Self.frequency else { return nil }
        return pick()
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
