import SwiftUI
import UIKit

/// The app's floating tab bar: items sitting directly on the canvas, inside the bottom safe-area
/// inset, on nothing but a bottom-anchored scrim that fades scrolling content into
/// `Clinical.canvas` before it reaches the labels. Round-13 retired the ivory capsule (fill +
/// hairline strokeBorder + two warm shadows) — every page had already shed its card chrome, and
/// the bright white pill was the loudest piece of chrome left, with Plan's product cards visibly
/// ghosting behind it. The frame now speaks the same ink grammar as the pages it holds: no
/// surface, no border, no shadow, just labels on a fade to canvas. The selected item still speaks
/// in ink, not chrome — its icon and label simply tint copper — and is still marked by a small
/// copper underline that slides beneath the active label with a snappy spring
/// (`matchedGeometryEffect`); the tapped symbol still gives a light haptic and a small bounce.
/// Under Reduce Motion the underline glides with an ease curve (no overshoot) and the bounce is
/// dropped. Each item is a real button: label = tab title, `.isSelected` when active.
/// The fade that dissolves scrolling content into `Clinical.canvas` before it reaches the bottom
/// chrome. It used to be `FloatingTabBar`'s own background, and that geometry was the bug twice
/// over: the gradient's stops were spread across the bar's full height, so content still ghosted
/// through the icons at half strength — and the Wren button rides *above* the bar in the same
/// safe-area inset, entirely outside the bar's background, so content behind her showed at full
/// opacity. The scrim is now its own view so the host can put it behind the complete chrome block
/// (Wren + bar + home-indicator area): a fixed 28pt clear→canvas strip, then solid canvas all the
/// way down. Host it with `.padding(.top, -28)` so the fade strip rises above the chrome instead
/// of eating into it.
struct TabBarScrim: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Clinical.canvas.opacity(0), Clinical.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            Clinical.canvas
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

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
        .padding(.horizontal, 6)
        // Scoped to the bar: the underline slide + tint changes animate, the screen swap stays instant.
        .animation(
            reduceMotion ? .easeInOut(duration: 0.22) : .spring(response: 0.32, dampingFraction: 0.72),
            value: selection
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
                    .font(Clinical.body(18, weight: on ? .semibold : .regular))
                    .symbolEffect(.bounce, value: bounceCounts[tab, default: 0])
                Text(tab.title)
                    .font(Clinical.body(11, weight: on ? .semibold : .medium))
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
