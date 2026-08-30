import SwiftUI

/// Applies the wall at a surface. One line per gated view, so the policy stays in
/// `Entitlements.swift` and call sites carry no decision of their own.
struct ProGatedModifier: ViewModifier {
    let feature: ProFeature

    func body(content: Content) -> some View {
        ProGate(feature: feature) { content }
    }
}

extension View {
    func proGated(_ feature: ProFeature) -> some View {
        modifier(ProGatedModifier(feature: feature))
    }
}
