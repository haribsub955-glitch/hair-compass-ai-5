import Foundation
import LocalAuthentication
import Observation

/// Optional Face ID / Touch ID / passcode lock for the whole app — table stakes for a health app
/// holding scalp photos. The preference persists in UserDefaults; the lock itself is runtime state:
/// it engages on launch (when enabled) and re-engages whenever the app is backgrounded.
///
/// Biometric plumbing is injected as closures so tests never need a real `LAContext`.
@MainActor
@Observable
final class AppLockService {
    static let enabledKey = "appLockEnabled"

    private let defaults: UserDefaults
    /// Can this device authenticate at all (Face ID / Touch ID / passcode)?
    private let canEvaluate: @MainActor () -> Bool
    /// Run the actual authentication with a localized reason; true on success.
    private let authenticate: @MainActor (String) async -> Bool
    @ObservationIgnored private var isAuthenticating = false

    /// The user's preference, persisted. Turning it off also unlocks immediately.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { isLocked = false }
        }
    }

    /// Runtime lock state — starts locked when the lock is enabled.
    private(set) var isLocked: Bool

    /// False when the device has no Face ID / Touch ID / passcode — the settings toggle disables
    /// and `unlock()` never traps the user out of their own records.
    var canUseLock: Bool { canEvaluate() }

    init(defaults: UserDefaults = .standard,
         canEvaluate: (@MainActor () -> Bool)? = nil,
         authenticate: (@MainActor (String) async -> Bool)? = nil) {
        var canCheck = canEvaluate ?? Self.deviceCanAuthenticate
        var auth = authenticate ?? Self.deviceAuthenticate
        var enabled = defaults.bool(forKey: Self.enabledKey)
        var locked = enabled
        #if DEBUG
        // HC_LOCKED forces the lock overlay on (for screenshots): enabled + locked, with an
        // authenticator that always fails so the overlay stays up even on an unenrolled simulator.
        // Assigned in init, so nothing is persisted to UserDefaults.
        if ProcessInfo.processInfo.arguments.contains("HC_LOCKED") {
            enabled = true
            locked = true
            canCheck = { true }
            auth = { _ in false }
        }
        // HC_NOLOCK is the opposite escape hatch: never let the lock block a debug run (simulators
        // without enrolled Face ID can otherwise strand you). Also persists the preference off so
        // subsequent launches stay unlocked.
        if ProcessInfo.processInfo.arguments.contains("HC_NOLOCK") {
            enabled = false
            locked = false
            defaults.set(false, forKey: Self.enabledKey)
        }
        #endif
        self.defaults = defaults
        self.canEvaluate = canCheck
        self.authenticate = auth
        self.isEnabled = enabled
        self.isLocked = locked
    }

    /// Engage the lock — a no-op unless the user has enabled App Lock.
    func lockIfEnabled() {
        guard isEnabled else { return }
        isLocked = true
    }

    /// Relock policy: relock whenever the app is backgrounded (simple, safest). Called from the
    /// scenePhase handler alongside the ritual coordinator's own bookkeeping.
    func markBackgrounded() {
        lockIfEnabled()
    }

    #if DEBUG
    /// Debug builds only: an explicit bypass for the lock screen's "Skip" button, so an unenrolled
    /// simulator can never strand a test run. Compiled out of release entirely.
    func debugBypass() {
        isLocked = false
    }
    #endif

    /// Try to unlock with Face ID / Touch ID / passcode. If the device can't authenticate at all,
    /// auto-unlock rather than locking the user out of their own data.
    func unlock() async {
        guard isLocked else { return }
        guard canUseLock else {
            isLocked = false
            return
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await authenticate("Unlock your hair records.") {
            isLocked = false
        }
    }

    // MARK: - Real device plumbing (LocalAuthentication)

    /// `.deviceOwnerAuthentication` (not `...WithBiometrics`) so the device passcode works as a
    /// fallback when Face ID fails or isn't enrolled.
    private static func deviceCanAuthenticate() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    private static func deviceAuthenticate(reason: String) async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
