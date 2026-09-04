import SwiftUI

/// Presentation-only pieces for the illustrated journal. No health values are inferred here.
struct BotanicalEmblem: View {
    let symbol: String
    var tint: Color = Clinical.sage
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.17).gradient)
            Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1)
            Circle().strokeBorder(Clinical.paperLight.opacity(0.8), lineWidth: 1).padding(3)
            Image(systemName: symbol)
                .font(.system(size: size * 0.40, weight: .light))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .shadow(color: Clinical.cardShadow, radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}

/// The routine's leaf seal sits on the timeline; completion is also stated in text.
struct RitualLeafSeal: View {
    let done: Bool
    let periodic: Bool

    private var tint: Color { done ? Clinical.positive : Clinical.accent }

    var body: some View {
        ZStack {
            LeafSealShape().fill(tint.opacity(done ? 0.85 : 0.17).gradient)
            LeafSealShape().stroke(tint.opacity(0.55), lineWidth: 1)
            LeafSealShape().stroke(Clinical.paperLight.opacity(0.7), lineWidth: 1).padding(4)
            Image(systemName: done ? "checkmark" : periodic ? "calendar" : "clock")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(done ? Clinical.surface : Clinical.accent)
        }
        .frame(width: 38, height: 54)
        .shadow(color: Clinical.cardShadow, radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}

private struct LeafSealShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX * 1.25, y: rect.height * 0.40),
                      control2: CGPoint(x: rect.maxX, y: rect.height * 0.77))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.height * 0.77),
                      control2: CGPoint(x: rect.minX - rect.width * 0.25, y: rect.height * 0.40))
        path.closeSubpath()
        return path
    }
}

/// Quiet edge ornament for a card. White paper in the existing art blends into warm surfaces.
struct BotanicalCardSprig: View {
    var width: CGFloat = 120
    var opacity: Double = 0.25

    var body: some View {
        Image(BrandArt.sprig)
            .resizable().scaledToFit()
            .frame(width: width)
            .blendMode(.multiply)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A real feature action, with a botanical edge rather than a second navigation system.
struct BotanicalActionCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ClinicalCard(padding: 17) {
                HStack(spacing: 13) {
                    BotanicalEmblem(symbol: symbol, tint: Clinical.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(Clinical.headline(20)).foregroundStyle(Clinical.ink)
                        Text(subtitle).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(Clinical.body(13, weight: .medium)).foregroundStyle(Clinical.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .trailing) { BotanicalCardSprig(width: 82, opacity: 0.12) }
            }
        }
        .buttonStyle(.clinicalPressable)
    }
}

struct JournalMetricTile: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    var tint: Color = Clinical.accent

    var body: some View {
        ClinicalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 9) {
                BotanicalEmblem(symbol: symbol, tint: tint, size: 36)
                Text(title).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                Text(value).font(Clinical.headline(23)).foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption).font(Clinical.caption(10)).foregroundStyle(Clinical.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }
}
