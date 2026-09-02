import Foundation
import Security

/// Where the trial window's first-launch anchor lives. A protocol so tests inject memory;
/// production uses the Keychain, which survives app deletion — reinstalling must not mint a
/// fresh 3 days.
protocol AccessAnchorStoring {
    func loadAnchor() -> Date?
    func saveAnchor(_ date: Date)
}

/// The 3-day full-access window every fresh install starts with. All gated surfaces read
/// `purchases.hasPro || accessWindow.isActive`; when both are false the gate shows the paywall.
///
/// The anchor is written exactly once, on the first launch that finds none, and never moved —
/// including when the device clock is set behind it (the window then simply reads active until
/// the real boundary; a clock trick can stretch one window but never restart it, because
/// restarting would require deleting the Keychain row, which app deletion does not do).
@MainActor
@Observable
final class AccessWindow {
    static let duration: TimeInterval = 72 * 3600

    private let now: () -> Date
    private let anchor: Date

    init(store: AccessAnchorStoring = KeychainAnchorStore(), now: @escaping () -> Date = Date.init) {
        self.now = now
        if let existing = store.loadAnchor() {
            anchor = existing
        } else {
            let fresh = now()
            store.saveAnchor(fresh)
            anchor = fresh
        }
    }

    #if DEBUG
    /// `HC_TRIAL expired` / `HC_TRIAL active` forces the window for QA — the lapsed paywall is
    /// otherwise unreachable for 3 days on a fresh install. Same shape as `HC_PRO`/`HC_AI_STATUS`.
    static var forcedActive: Bool? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "HC_TRIAL"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "active": return true
        case "expired": return false
        default: return nil
        }
    }
    #endif

    var isActive: Bool {
        #if DEBUG
        if let forced = Self.forcedActive { return forced }
        #endif
        return now() < anchor.addingTimeInterval(Self.duration)
    }

    /// Whole days left, rounded up — "N days left" on the paywall must never show a number the
    /// window outlives. 0 once lapsed.
    var remainingDays: Int {
        let remaining = anchor.addingTimeInterval(Self.duration).timeIntervalSince(now())
        guard remaining > 0 else { return 0 }
        return Int((remaining / 86_400).rounded(.up))
    }
}

/// Keychain-backed anchor storage. A generic-password row keyed to the app, deliberately
/// device-only (no iCloud sync — a new phone is a new person's decision surface, and syncing
/// would also let one lapsed device lapse a fresh one).
struct KeychainAnchorStore: AccessAnchorStoring {
    private static let service = "harib.Hair-Compass-AI-5.access"
    private static let account = "firstLaunchAnchor"

    func loadAnchor() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let interval = TimeInterval(String(decoding: data, as: UTF8.self)) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func saveAnchor(_ date: Date) {
        let data = Data(String(date.timeIntervalSince1970).utf8)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Add-or-keep: never overwrite an existing anchor (see the type doc's honesty rule).
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
