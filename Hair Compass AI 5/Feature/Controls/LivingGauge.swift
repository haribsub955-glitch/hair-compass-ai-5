import SwiftUI

/// Band mapping shared by every living gauge: thumb intensity (0…1) → discrete band index.
/// Same formula as `SheddingDial.band(_:)` (`round(i * 3)`), generalized to any band count —
/// 4 for the 0–3 scalp fields, 5 for the 1–5 wellbeing fields (`level = 1 + index`).
enum GaugeBand {
    static func index(_ intensity: CGFloat, count: Int) -> Int {
        min(count - 1, max(0, Int((intensity * CGFloat(count - 1)).rounded())))
    }
}

/// The generalized "input is the preview" control, factored out of `ShedDialField`: a live
/// preview panel whose animated motif *is* the thing being measured, over a tinted drag track.
/// The shell — preview panel + caption chip + track + zone/end labels — is written once here;
/// only the motif view, tint, band count and caption copy vary per field.
///
/// Interaction grammar (lifted verbatim from `ShedDialField`):
/// - zero-distance `DragGesture` so a tap jumps straight to that zone,
/// - `Haptics.shared.bandTick` fires only when the discrete band changes, never per pixel,
/// - `accessibilityElement(children: .ignore)` + adjustable action stepping one band,
/// - Reduce Motion is honored inside each motif (one static representative frame).
struct LivingGauge<Motif: View>: View {
    let title: String
    @Binding var intensity: CGFloat          // 0…1, the source of truth while dragging
    let bandCount: Int                       // 4 (0–3 fields) or 5 (1–5 fields)
    let tint: Color                          // thumb / fill / active-zone colour
    var panelBackground: Color = Clinical.surface
    let zones: [String]?                     // zone labels, or nil → show end labels
    let ends: (String, String)?              // ("POOR","DEEP") etc. for 5-level gauges
    let caption: (CGFloat) -> (String, String)   // live (title, subtitle)
    @ViewBuilder let motif: (CGFloat) -> Motif   // the animated preview, fed intensity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var band: Int { GaugeBand.index(intensity, count: bandCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Clinical.ink)
            previewPanel
            dragTrack
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(caption(intensity).0)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setBand(band + 1)
            case .decrement: setBand(band - 1)
            @unknown default: break
            }
        }
    }

    // MARK: Live preview

    private var previewPanel: some View {
        ZStack(alignment: .bottomLeading) {
            motif(intensity)
            captionChip.padding(10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.22), value: band)
    }

    private var captionChip: some View {
        let (title, subtitle) = caption(intensity)
        return HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Clinical.headline(15))
                    .foregroundStyle(Clinical.ink)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Clinical.secondary)
                    .contentTransition(.opacity)
            }
            GaugeBandMeter(band: band, count: bandCount, tint: tint)
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
            if let zones {
                // Zone labels live in their own row so the thumb never occludes them. Each is
                // centered in its slice and is a large direct tap target (setBand).
                HStack(spacing: 0) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { index, name in
                        Button { setBand(index) } label: {
                            Text(name.uppercased())
                                .font(Clinical.eyebrow(9))
                                .tracking(0.6)
                                .foregroundStyle(index == band ? tint : Clinical.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let ends {
                HStack {
                    Text(ends.0.uppercased())
                    Spacer()
                    Text(ends.1.uppercased())
                }
                .font(Clinical.eyebrow(9))
                .tracking(0.6)
                .foregroundStyle(Clinical.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                    .fill(LinearGradient(colors: [tint.opacity(0.14), tint.opacity(0.30)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: min(w, thumbX + thumb))

                // Tinted thumb.
                Circle()
                    .fill(tint)
                    .frame(width: thumb, height: thumb)
                    .overlay(Circle().strokeBorder(Clinical.surface, lineWidth: 2))
                    .shadow(color: tint.opacity(0.35), radius: 6, y: 2)
                    .offset(x: thumbX)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let previousBand = GaugeBand.index(intensity, count: bandCount)
                        let ni = min(1, max(0, (v.location.x - inset - thumb / 2) / usable))
                        intensity = ni
                        let newBand = GaugeBand.index(ni, count: bandCount)
                        if newBand != previousBand {
                            Haptics.shared.bandTick(fraction: Double(newBand) / Double(max(1, bandCount - 1)))
                        }
                    }
                    .onEnded { v in
                        // A near-zero drag is a tap: snap straight to the tapped zone.
                        if abs(v.translation.width) < 4, abs(v.translation.height) < 4 {
                            setBand(min(bandCount - 1, max(0, Int(v.location.x / w * CGFloat(bandCount)))))
                        }
                    }
            )
        }
        .frame(height: 32)
    }

    // MARK: Band mutation (zone taps + VoiceOver adjustable)

    private func setBand(_ newBand: Int) {
        let clamped = min(bandCount - 1, max(0, newBand))
        let changed = clamped != band
        let target = CGFloat(clamped) / CGFloat(bandCount - 1)
        if reduceMotion {
            intensity = target
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { intensity = target }
        }
        if changed {
            Haptics.shared.bandTick(fraction: Double(clamped) / Double(max(1, bandCount - 1)))
        }
    }
}

/// Animated, non-numeric magnitude cue shared by scalp and wellbeing states. The live Canvas
/// remains the primary explanation; these bars make the selected band readable at a glance.
private struct GaugeBandMeter: View {
    let band: Int
    let count: Int
    let tint: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= band ? tint : Clinical.hairline)
                    .frame(width: 3.5, height: 6 + CGFloat(index) * 2.5)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: band)
        .accessibilityHidden(true)
    }
}
