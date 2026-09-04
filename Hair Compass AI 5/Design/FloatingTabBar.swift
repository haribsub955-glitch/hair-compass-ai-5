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
        // Order matters: `materialBand` is applied first so it paints in front of `scrim` (the
        // fade), directly behind the items — the fade dissolves scrolled content on its way up
        // to the bar, and the material band guarantees the row itself stays legible no matter
        // where the fade's own opacity lands at that height.
        .background(materialBand)
        .background(scrim)
        // Scoped to the bar: the underline slide + tint changes animate, the screen swap stays instant.
        .animation(
            reduceMotion ? .easeInOut(duration: 0.22) : .spring(response: 0.32, dampingFraction: 0.72),
            value: selection
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// Directly behind the labels, clipped to the bar's own height at the top (it takes no top
    /// padding, so its top edge is proposed exactly the item row's own top) but extended past the
    /// home indicator at the bottom — a blurred, canvas-tinted ground the items always read
    /// against, independent of how far the fade above has faded in yet, that reaches all the way
    /// to the physical bottom edge so nothing between the row and the edge reads through either.
    /// `.ignoresSafeArea(edges: .bottom)` alone does not reach: this view sits inside
    /// `RootView`'s `.safeAreaInset(edge: .bottom)` content, which has already claimed the
    /// device's bottom safe area for itself by the time this renders, leaving nothing further
    /// for a nested `ignoresSafeArea` call to ignore (confirmed empirically — a debug fill with
    /// only `.ignoresSafeArea(edges: .bottom)` stopped exactly at the item row's own bottom edge).
    /// `.padding(.bottom, -60)` is what actually does the work, the same negative-padding bleed
    /// `scrim` already uses on its top edge; kept alongside `ignoresSafeArea` for parity with
    /// `scrim`'s own modifier order.
    private var materialBand: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Clinical.canvas.opacity(0.55))
            .padding(.bottom, -60)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }

    /// Clear at the top, full canvas by the labels' own top edge, extended into the bottom safe
    /// area — so content scrolled behind the bar dissolves into the page instead of ghosting
    /// through a transparent white pill. Widened past the item stack (via `.padding(.top, -48)`,
    /// 24 pt more than before) so the fade starts higher and nothing shows a hard-edged rectangle
    /// above the tallest label.
    private var scrim: some View {
        LinearGradient(
            colors: [Clinical.canvas.opacity(0), Clinical.canvas],
            startPoint: .top,
            endPoint: .bottom
        )
        .padding(.top, -48)
        .padding(.horizontal, -20)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
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
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityValue(on ? "Selected" : "")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
