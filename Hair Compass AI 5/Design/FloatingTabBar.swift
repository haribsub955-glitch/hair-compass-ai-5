import SwiftUI
import UIKit

/// The app's floating tab bar: an ivory capsule sitting inside the bottom safe-area inset on
/// layered warm shadows (tight contact + soft ambient — warm espresso, never grey). The
/// selected item speaks in ink, not chrome — its icon and label simply tint copper — and is
/// marked by a small copper underline that slides beneath the active label with a snappy spring
/// (`matchedGeometryEffect`); the tapped symbol gives a light haptic and a small bounce. Under
/// Reduce Motion the underline glides with an ease curve (no overshoot) and the bounce is
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
        // Scoped to the bar: the underline slide + tint changes animate, the screen swap stays instant.
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
                    .font(.system(size: 18, weight: on ? .semibold : .regular))
                    .symbolEffect(.bounce, value: bounceCounts[tab, default: 0])
                Text(tab.title)
                    .font(.system(size: 11, weight: on ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                // Selection is marked here — a small copper underline sliding between items —
                // rather than by a filled pill behind the whole item, so the bar's loudest mark
                // is a hairline-scale annotation matching the underline grammar the pages
                // already use (Trends' range picker, Photos' region tabs), not a saturated block.
                // The clear placeholder always reserves the same 16×2pt slot so the label never
                // shifts; only the active item's capsule carries the matched-geometry id.
                ZStack {
                    Capsule().fill(.clear).frame(width: 16, height: 2)
                    if on {
                        Capsule()
                            .fill(Clinical.accent)
                            .frame(width: 16, height: 2)
                            .matchedGeometryEffect(id: "selection-pill", in: pill)
                    }
                }
            }
            .foregroundStyle(on ? Clinical.accent : Clinical.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(on ? "Selected" : "")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
