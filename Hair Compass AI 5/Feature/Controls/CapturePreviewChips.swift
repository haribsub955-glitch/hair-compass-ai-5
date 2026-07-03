import SwiftUI

/// Inline chip selector for the guided-capture condition fields. Each chip carries a small
/// bespoke glyph that previews the *physical meaning* of its option — a color-temperature
/// swatch for lighting, a head-in-frame size for distance, a parting-line position for
/// parting — so the right choice reads at a glance instead of hiding behind a menu.
struct CapturePreviewChips: View {
    enum Kind { case lighting, distance, parting }

    let title: String
    let options: [String]
    @Binding var selection: String
    let kind: Kind

    /// Color temperature implied by the current lighting selection, for callers that may want
    /// to tint a live preview. Nil for non-lighting kinds.
    var tintPreview: Color? {
        guard kind == .lighting else { return nil }
        return Self.lightingStyle(for: selection).tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    chip(for: option)
                }
            }
        }
    }

    // MARK: Chip

    private func chip(for option: String) -> some View {
        let isOn = option == selection
        return Button {
            guard selection != option else { return }
            selection = option
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 7) {
                glyph(for: option)
                    .frame(width: 30, height: 26)
                    .accessibilityHidden(true)
                Text(option)
                    .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Clinical.accent : Clinical.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(isOn ? Clinical.accentSoft : Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? Clinical.accent : Clinical.hairline, lineWidth: isOn ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(option)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func glyph(for option: String) -> some View {
        switch kind {
        case .lighting: lightingGlyph(option)
        case .distance: distanceGlyph(option)
        case .parting: partingGlyph(option)
        }
    }

    // MARK: Lighting — a light source tinted by color temperature, on a soft matching glow.

    private static func lightingStyle(for option: String) -> (symbol: String, tint: Color, glow: Color) {
        let lowered = option.lowercased()
        if lowered.contains("warm") {
            return ("lightbulb.fill", Clinical.gold, Clinical.warning)
        }
        if lowered.contains("cool") {
            return ("lamp.desk", Clinical.tertiary, Clinical.tertiary)
        }
        return ("sun.max", Clinical.secondary, Clinical.secondary)
    }

    private func lightingGlyph(_ option: String) -> some View {
        let style = Self.lightingStyle(for: option)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [style.glow.opacity(0.4), style.glow.opacity(0)],
                        center: .center, startRadius: 1, endRadius: 14
                    )
                )
                .frame(width: 28, height: 28)
            Image(systemName: style.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(style.tint)
        }
    }

    // MARK: Distance — a camera frame with the head sized by how close you're standing.

    private static func headScale(for option: String) -> CGFloat {
        let lowered = option.lowercased()
        if lowered.contains("close") { return 1.0 }
        if lowered.contains("far") { return 0.34 }
        return 0.62 // arm's length
    }

    private func distanceGlyph(_ option: String) -> some View {
        let scale = Self.headScale(for: option)
        let frameSize = CGSize(width: 21, height: 26)
        let headHeight: CGFloat = (frameSize.height - 5) * scale
        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Clinical.tertiary, lineWidth: 1.2)
                .frame(width: frameSize.width, height: frameSize.height)
            Ellipse()
                .fill(Clinical.secondary.opacity(0.85))
                .frame(width: headHeight * 0.78, height: headHeight)
        }
    }

    // MARK: Parting — a top-of-head ellipse with the parting line where you'd draw it.

    /// Horizontal position of the parting line as a fraction of glyph width; nil = no parting.
    private static func partingFraction(for option: String) -> CGFloat? {
        let lowered = option.lowercased()
        if lowered.contains("none") { return nil }
        if lowered.contains("left") { return 0.32 }
        if lowered.contains("right") { return 0.68 }
        return 0.5 // center
    }

    private func partingGlyph(_ option: String) -> some View {
        let fraction = Self.partingFraction(for: option)
        return ZStack {
            Ellipse().fill(Clinical.secondary.opacity(0.2))
            Ellipse().strokeBorder(Clinical.secondary, lineWidth: 1.2)
            if let fraction {
                PartingLineShape(fraction: fraction)
                    .stroke(Clinical.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        .frame(width: 21, height: 26)
    }
}

/// A vertical parting line clipped to the head ellipse: at horizontal `fraction` of the rect,
/// spanning (most of) the ellipse's chord at that x so it never pokes past the head outline.
private struct PartingLineShape: Shape {
    let fraction: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let semiWidth = rect.width / 2
        let semiHeight = rect.height / 2
        let x = rect.minX + rect.width * fraction
        let ratio = min(max((x - rect.midX) / semiWidth, -1), 1)
        let halfChord = semiHeight * sqrt(max(0, 1 - ratio * ratio)) * 0.86
        path.move(to: CGPoint(x: x, y: rect.midY - halfChord))
        path.addLine(to: CGPoint(x: x, y: rect.midY + halfChord))
        return path
    }
}
