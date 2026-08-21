import SwiftUI

private struct EntitlementsKey: EnvironmentKey {
    /// The least-privileged default. A surface that somehow renders outside the injection
    /// should lock, never open.
    static let defaultValue = Entitlements(tier: .free)
}

extension EnvironmentValues {
    var entitlements: Entitlements {
        get { self[EntitlementsKey.self] }
        set { self[EntitlementsKey.self] = newValue }
    }
}
