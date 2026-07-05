import SwiftUI
import UIKit

/// The app's floating tab bar: an ivory capsule hovering ~10pt above the home indicator on
/// layered warm shadows (tight contact + soft ambient — warm espresso, never grey). The
/// selected item sits on a copper pill that slides between items with a snappy spring
/// (`matchedGeometryEffect`); the tapped symbol gives a light haptic and a small bounce.
/// Under Reduce Motion the pill glides with an ease curve (no overshoot) and the bounce is
/// dropped. Each item is a real button: label = tab title, `.isSelected` when active.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill
    /// Per-tab bounce triggers so only the tapped symbol bounces — a shared trigger would
    /// bounce the outgoing icon too.
    @State private var bounceCounts: [AppTab: Int] = [:]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(6)
        .background(Clinical.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
        .shadow(color: Clinical.shadowWarm.opacity(0.12), radius: 2, y: 1)   // contact
        .shadow(color: Clinical.shadowWarm.opacity(0.10), radius: 18, y: 9)  // ambient
        // Scoped to the bar: the pill slide + tint changes animate, the screen swap stays instant.
        .animation(
            reduceMotion ? .easeInOut(duration: 0.22) : .spring(response: 0.32, dampingFraction: 0.72),
            value: selection
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func item(_ tab: AppTab) -> some View {
        let on = tab == selection
        return Button {
            guard selection != tab else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if !reduceMotion { bounceCounts[tab, default: 0] += 1 }
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .symbolVariant(on ? .fill : .none)
                    .font(.system(size: 17, weight: on ? .semibold : .regular))
                    .symbolEffect(.bounce, value: bounceCounts[tab, default: 0])
                Text(tab.title)
                    .font(.system(size: 10, weight: on ? .semibold : .medium))
            }
            .foregroundStyle(on ? Clinical.surface : Clinical.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if on {
                    Capsule()
                        .fill(Clinical.accent)
                        .matchedGeometryEffect(id: "selection-pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
