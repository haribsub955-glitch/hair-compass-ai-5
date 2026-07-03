import SwiftUI

/// A tactile metric picker for the Compare builder: drag across the tick strip and the sparkline
/// preview above it re-draws live with the metric under your finger — the input IS the preview,
/// the same philosophy as the onboarding shedding dial. Selection commits continuously while
/// scrubbing (so the big chart behind previews too); a tap is just a zero-distance drag. Same
/// interaction grammar as `CountScrubber`/`ShedDialField`: selection haptic only when the focused
/// option actually changes, VoiceOver adjustable as one element.
struct MetricScrubber: View {
    let title: String
    let options: [ChartMetric]
    @Binding var selectionID: String
    var tint: Color = Clinical.accent
    /// The metric's dated values already min–max normalized to 0…1 (empty ⇒ no data).
    let normalizedSeries: (ChartMetric) -> [Double]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false

    private let previewHeight: CGFloat = 38
    private let trackHeight: CGFloat = 24

    /// Because commit is continuous, the focused option and the selection are one and the same —
    /// deriving focus from the binding also keeps the strip in sync when presets change it.
    private var focusIndex: Int { options.firstIndex { $0.id == selectionID } ?? 0 }
    private var focused: ChartMetric { options[focusIndex] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)
            VStack(spacing: 8) {
                previewLabel
                sparkline.frame(height: previewHeight)
                track
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(focused.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setIndex(focusIndex + 1)
            case .decrement: setIndex(focusIndex - 1)
            @unknown default: break
            }
        }
    }

    // MARK: Preview (title + unit + live sparkline of the focused metric)

    private var previewLabel: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(focused.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Clinical.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(focused.unit)
                .font(Clinical.eyebrow(9)).tracking(0.8)
                .foregroundStyle(Clinical.tertiary)
            Spacer(minLength: 0)
        }
    }

    private var sparkline: some View {
        let values = normalizedSeries(focused)
        return ZStack {
            Canvas { ctx, size in
                if values.count >= 2 {
                    drawSeries(ctx, size: size, values: values)
                } else {
                    drawBaseline(ctx, size: size)
                }
            }
            if values.count < 2 {
                Text("Not enough data yet")
                    .font(Clinical.eyebrow(9)).tracking(0.8)
                    .foregroundStyle(Clinical.tertiary.opacity(0.8))
            }
        }
        .accessibilityHidden(true)
    }

    private func drawSeries(_ ctx: GraphicsContext, size: CGSize, values: [Double]) {
        let insetY: CGFloat = 6
        let insetX: CGFloat = 4
        let h = size.height - insetY * 2
        let w = size.width - insetX * 2
        let stepX = w / CGFloat(values.count - 1)
        let pts: [CGPoint] = values.enumerated().map { i, v in
            CGPoint(x: insetX + CGFloat(i) * stepX, y: insetY + (1 - CGFloat(v)) * h)
        }

        var line = Path()
        line.move(to: pts[0])
        for p in pts.dropFirst() { line.addLine(to: p) }

        // Soft area wash under the line — quiet, gouache-flat.
        var area = line
        area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: size.height))
        area.addLine(to: CGPoint(x: pts[0].x, y: size.height))
        area.closeSubpath()
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [tint.opacity(0.16), tint.opacity(0.02)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))

        ctx.stroke(line, with: .color(tint),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

        // Emphasized end dot with a faint halo — "where the signal is now".
        if let last = pts.last {
            let r: CGFloat = 3
            ctx.stroke(Path(ellipseIn: CGRect(x: last.x - r - 2, y: last.y - r - 2,
                                              width: (r + 2) * 2, height: (r + 2) * 2)),
                       with: .color(tint.opacity(0.35)), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2)),
                     with: .color(tint))
        }
    }

    private func drawBaseline(_ ctx: GraphicsContext, size: CGSize) {
        let y = size.height / 2
        var p = Path()
        p.move(to: CGPoint(x: 4, y: y))
        p.addLine(to: CGPoint(x: size.width - 4, y: y))
        ctx.stroke(p, with: .color(Clinical.hairline),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
    }

    // MARK: Scrub track (one tick per option; drag or tap anywhere on it)

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let segment = w / CGFloat(max(1, options.count))
            ZStack {
                Capsule().fill(Clinical.hairline.opacity(0.7)).frame(height: 2)
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { i, _ in
                        let on = i == focusIndex
                        Capsule()
                            .fill(on ? tint : Clinical.tertiary.opacity(0.35))
                            .frame(width: on ? 5 : 3, height: on ? CGFloat(trackHeight) - 4 : 12)
                            .scaleEffect(on && isDragging ? 1.15 : 1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !isDragging {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                                isDragging = true
                            }
                        }
                        setIndex(Int((g.location.x / segment).rounded(.down)))
                    }
                    .onEnded { _ in
                        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: trackHeight)
    }

    /// Clamp, haptic only when the focused option actually changes, commit the selection so both
    /// the preview and the chart behind update live. Shared by drag, tap and VoiceOver adjust.
    private func setIndex(_ i: Int) {
        guard !options.isEmpty else { return }
        let clamped = min(options.count - 1, max(0, i))
        guard options[clamped].id != selectionID else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            selectionID = options[clamped].id
        }
    }
}
