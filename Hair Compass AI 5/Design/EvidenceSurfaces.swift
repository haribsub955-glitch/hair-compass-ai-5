import SwiftUI

/// A compact, semantic status mark for measured evidence. Callers supply the already-derived
/// wording and tint; this view never interprets a health value.
struct ClinicalStatusPill: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(Clinical.eyebrow(9.5))
            .tracking(0.25)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.75))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

/// A read-only evidence track shared by the Plan horizon and Trends current-read surface.
/// It is intentionally static: progress should settle the screen, not look draggable.
struct EvidenceProgressTrack: View {
    let value: Double
    var tint: Color = Clinical.accent
    var accessibilityLabel: String

    private var clampedValue: Double { min(1, max(0, value)) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Clinical.hairline.opacity(0.75))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.72), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * clampedValue)
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(clampedValue.formatted(.percent.precision(.fractionLength(0))))
    }
}
