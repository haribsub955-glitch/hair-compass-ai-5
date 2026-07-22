import SwiftUI

/// Compact, physics-driven shedding control for the daily log. The drag input *is* the
/// simulation: sliding across the four bands drives `FallingHairView` live, and the stored
/// `ShedLevel` is derived from where the thumb lands — same philosophy as the onboarding
/// `SheddingDial`, whose band/caption mapping is reused so the two stay in lockstep.
struct ShedDialField: View {
    @Binding var shed: ShedLevel

    @State private var intensity: CGFloat = 1.0 / 3.0
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let bands = ["Minimal", "Normal", "Elevated", "Heavy"]
    private var band: Int { SheddingDial.band(intensity) }

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

    private var previewPanel: some View {
        ZStack(alignment: .bottomLeading) {
            SheddingStatusScene(intensity: intensity)
            Label("Live portrait", systemImage: "waveform.path")
                .font(Clinical.eyebrow(9))
                .tracking(0.7)
                .foregroundStyle(Clinical.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Clinical.surface.opacity(0.82), in: Capsule())
                .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            caption.padding(10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 164)
        .background(Clinical.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.22), value: band)
    }

    private var caption: some View {
        let (title, subtitle) = SheddingDial.bandCaption(intensity)
        let reflection = SheddingReflection.make(band: band)
        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Clinical.headline(16))
                    .foregroundStyle(Clinical.ink)
                    .contentTransition(.opacity)
                Text("\(reflection.title) · \(subtitle)")
                    .font(Clinical.caption(11))
                    .foregroundStyle(Clinical.secondary)
                    .contentTransition(.opacity)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            SheddingBandMeter(band: band)
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
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
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
                        if !dragging {
                            dragging = true
                            Haptics.shared.startTexture()
                        }
                        let previousBand = SheddingDial.band(intensity)
                        let ni = min(1, max(0, (v.location.x - inset - thumb / 2) / usable))
                        intensity = ni
                        Haptics.shared.updateTexture(intensity: Double(ni))
                        let newBand = SheddingDial.band(ni)
                        if newBand != previousBand {
                            Haptics.shared.bandTick(fraction: Double(newBand) / 3.0)
                        }
                        let level = SheddingDial.shedLevel(ni)
                        if level != shed { shed = level }
                    }
                    .onEnded { v in
                        Haptics.shared.stopTexture()
                        dragging = false
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
            Haptics.shared.bandTick(fraction: Double(clamped) / 3.0)
        }
    }
}

/// A compact magnitude cue that animates with the categorical selection. It reinforces the scene
/// without implying an exact strand count.
private struct SheddingBandMeter: View {
    let band: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index <= band ? Clinical.accent : Clinical.hairline)
                    .frame(width: 4, height: 7 + CGFloat(index) * 4)
            }
        }
        .frame(height: 20, alignment: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: band)
        .accessibilityHidden(true)
    }
}
