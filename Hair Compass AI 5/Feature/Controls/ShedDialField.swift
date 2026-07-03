import SwiftUI

/// Compact, physics-driven shedding control for the daily log. The drag input *is* the
/// simulation: sliding across the four bands drives `FallingHairView` live, and the stored
/// `ShedLevel` is derived from where the thumb lands — same philosophy as the onboarding
/// `SheddingDial`, whose band/caption mapping is reused so the two stay in lockstep.
struct ShedDialField: View {
    @Binding var shed: ShedLevel

    @State private var intensity: CGFloat = 1.0 / 3.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let bands = ["Minimal", "Normal", "Elevated", "Heavy"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            previewPanel
            dragTrack
        }
        .onAppear { intensity = CGFloat(shed.rawValue) / 3 }
        .onChange(of: shed) { _, newValue in
            // Keep the binding authoritative: reflect external changes without
            // fighting our own updates (which already agree on the band).
            if SheddingDial.band(intensity) != newValue.rawValue {
                intensity = CGFloat(newValue.rawValue) / 3
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily shedding")
        .accessibilityValue(shed.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setBand(shed.rawValue + 1)
            case .decrement: setBand(shed.rawValue - 1)
            @unknown default: break
            }
        }
    }

    // MARK: Live preview

    /// A 140pt panel can't carry a 0-intensity sim the way the full-screen onboarding can, so the
    /// PREVIEW gets a visual floor: even "minimal" shows a gentle, slow drizzle. The stored `shed`
    /// stays honest — it's derived from the true raw drag intensity; only this display value is
    /// floored, and the strand count still visibly rises across the whole drag.
    private var previewIntensity: CGFloat { 0.22 + intensity * 0.78 }

    private var previewPanel: some View {
        ZStack(alignment: .bottomLeading) {
            FallingHairView(intensity: previewIntensity)
            caption.padding(10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(Clinical.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
    }

    private var caption: some View {
        let (title, subtitle) = SheddingDial.bandCaption(intensity)
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Clinical.headline(15))
                .foregroundStyle(Clinical.ink)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Clinical.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Clinical.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
    }

    // MARK: Drag track

    private var dragTrack: some View {
        VStack(spacing: 7) {
            trackBar
            // Zone labels live in their own row so the thumb never occludes them. Each is
            // centered in its quarter and is a large direct tap target (setBand).
            HStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { index, name in
                    Button { setBand(index) } label: {
                        Text(name.uppercased())
                            .font(Clinical.eyebrow(9))
                            .tracking(0.6)
                            .foregroundStyle(index == shed.rawValue ? Clinical.accent : Clinical.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var trackBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let inset: CGFloat = 5
            let thumb: CGFloat = 26
            let usable = max(1, w - 2 * inset - thumb)
            let thumbX = inset + intensity * usable

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Clinical.canvas)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Clinical.hairline, lineWidth: 1)
                    )

                // Filled progress up to the thumb.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Clinical.accent.opacity(0.14), Clinical.accent.opacity(0.30)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: min(w, thumbX + thumb))

                // Copper thumb.
                Circle()
                    .fill(Clinical.accent)
                    .frame(width: thumb, height: thumb)
                    .overlay(Circle().strokeBorder(Clinical.surface, lineWidth: 2))
                    .shadow(color: Clinical.accent.opacity(0.35), radius: 6, y: 2)
                    .offset(x: thumbX)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let previousBand = SheddingDial.band(intensity)
                        let ni = min(1, max(0, (v.location.x - inset - thumb / 2) / usable))
                        intensity = ni
                        if SheddingDial.band(ni) != previousBand {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        let level = SheddingDial.shedLevel(ni)
                        if level != shed { shed = level }
                    }
                    .onEnded { v in
                        // A near-zero drag is a tap: snap straight to the tapped zone.
                        if abs(v.translation.width) < 4, abs(v.translation.height) < 4 {
                            setBand(min(3, max(0, Int(v.location.x / w * 4))))
                        }
                    }
            )
        }
        .frame(height: 32)
    }

    // MARK: Band mutation (zone taps + VoiceOver adjustable)

    private func setBand(_ band: Int) {
        let clamped = min(3, max(0, band))
        let target = CGFloat(clamped) / 3
        if reduceMotion {
            intensity = target
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { intensity = target }
        }
        if shed.rawValue != clamped {
            shed = ShedLevel(rawValue: clamped) ?? .normal
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
