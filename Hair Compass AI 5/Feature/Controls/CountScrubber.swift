import SwiftUI

/// A tactile drag-to-set counter for the daily log (cigarettes, drinks). Dragging across the
/// track sets the count; a restrained physical motif — smoke wisps or condensation beads —
/// scales with the magnitude so the number carries a quiet bodily weight without turning the
/// sheet into a form or a toy. Same interaction grammar as `ShedDialField`: zero-distance drag
/// (so taps jump), selection haptic only when the integer changes, VoiceOver adjustable.
struct CountScrubber: View {
    enum Motif { case smoke, drops }

    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var tint: Color = Clinical.accent
    var motif: Motif
    var onInteraction: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false

    private let trackHeight: CGFloat = 40
    private let thumbSize: CGFloat = 26
    private let inset: CGFloat = 5
    private let cornerRadius: CGFloat = 13

    private var span: CGFloat { CGFloat(range.upperBound - range.lowerBound) }
    private var fraction: CGFloat {
        guard span > 0 else { return 0 }
        return CGFloat(value - range.lowerBound) / span
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
                Spacer()
                Text("\(value)")
                    .font(Clinical.number(17))
                    .foregroundStyle(value > range.lowerBound ? tint : Clinical.tertiary)
                    .contentTransition(.numericText())
            }
            track
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(value + 1)
            case .decrement: setValue(value - 1)
            @unknown default: break
            }
        }
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let usable = max(1, w - 2 * inset - thumbSize)
            let thumbX = inset + fraction * usable
            let fillWidth = min(w, thumbX + thumbSize)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Clinical.canvas)

                // Filled progress up to the thumb — quiet tint wash, magnitude made spatial.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.10), tint.opacity(0.22)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillWidth)

                motifLayer(fillWidth: fillWidth)

                Circle()
                    .fill(Clinical.surface)
                    .overlay(
                        Circle().strokeBorder(value > range.lowerBound ? tint : Clinical.hairline,
                                              lineWidth: 2)
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Clinical.cardShadow, radius: 5, y: 2)
                    .scaleEffect(isDragging ? 1.08 : 1)
                    .offset(x: thumbX)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        onInteraction?()
                        if !isDragging {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                                isDragging = true
                            }
                        }
                        let f = min(1, max(0, (g.location.x - inset - thumbSize / 2) / usable))
                        setValue(range.lowerBound + Int((f * span).rounded()))
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

    /// Clamp, haptic only when the integer actually changes, animate the readout + fill together.
    /// Shared by the drag gesture and the VoiceOver adjustable action.
    private func setValue(_ newValue: Int) {
        onInteraction?()
        let clamped = min(range.upperBound, max(range.lowerBound, newValue))
        guard clamped != value else { return }
        Haptics.shared.detentTick()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { value = clamped }
    }

    // MARK: Physical motif (quiet accent, never the focus)

    private func motifLayer(fillWidth: CGFloat) -> some View {
        MotionTimeline(cadence: .ambient, paused: value == range.lowerBound) { timeline, reduceMotion in
            Canvas { ctx, size in
                guard value > range.lowerBound else { return }
                // Modulo keeps Double precision over long sessions; Reduce Motion gets one
                // static representative frame (t = 0, particles spread by their hash offsets).
                let t: CGFloat = reduceMotion
                    ? 0
                    : CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
                switch motif {
                case .smoke: drawSmoke(ctx, size: size, time: t, fillWidth: fillWidth)
                case .drops: drawDrops(ctx, size: size, time: t, fillWidth: fillWidth)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Faint wisps rising out of the filled region and dissipating. Count 2…6 and alpha
    /// 0.10…0.26 scale with the value — smoking is the strong risk factor, so this motif is
    /// allowed slightly more presence than the drops.
    private func drawSmoke(_ ctx: GraphicsContext, size: CGSize, time t: CGFloat, fillWidth: CGFloat) {
        let count = min(2 + value / 10, 6)
        let alpha = 0.10 + fraction * 0.16
        let region = max(fillWidth, 44)
        var layer = ctx
        layer.addFilter(.blur(radius: 0.8))
        for i in 0..<count {
            let h1 = hash(i, 1), h2 = hash(i, 2), h3 = hash(i, 3)
            let duration = 3.4 + h1 * 2.2
            let progress = fract(t / duration + h2)
            let envelope = sin(progress * .pi)
            let x = 8 + h3 * (region - 16) + sin(t * 0.9 + h1 * 6.28) * 3
            let y = size.height - 4 - progress * (size.height - 2)
            let sway = 2.5 + progress * 3.5
            var p = Path()
            p.move(to: CGPoint(x: x, y: y + 7))
            p.addQuadCurve(to: CGPoint(x: x + sway, y: y - 7),
                           control: CGPoint(x: x - sway, y: y))
            let color = (i % 2 == 0 ? Clinical.warning : Clinical.tertiary)
                .opacity(alpha * envelope)
            layer.stroke(p, with: .color(color),
                         style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

    /// A few small beads drifting slowly down the filled region, condensation-quiet. Alcohol is
    /// a weak signal, so this stays fainter and sparser than the smoke: count 1…4, alpha ≤ 0.22.
    private func drawDrops(_ ctx: GraphicsContext, size: CGSize, time t: CGFloat, fillWidth: CGFloat) {
        let count = min(1 + value / 8, 4)
        let alpha = 0.12 + fraction * 0.10
        let region = max(fillWidth, 44)
        for i in 0..<count {
            let h1 = hash(i, 4), h2 = hash(i, 5), h3 = hash(i, 6)
            let duration = 6.0 + h1 * 3.0
            let progress = fract(t / duration + h2)
            let envelope = sin(progress * .pi)
            let r = 1.8 + h1 * 1.3
            let x = 10 + h3 * (region - 20)
            let y = 5 + progress * (size.height - 10)
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2.3)
            let color = (i % 2 == 0 ? Clinical.sage : Clinical.tertiary)
                .opacity(alpha * envelope)
            ctx.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    // MARK: Deterministic per-particle randomness

    private func fract(_ x: CGFloat) -> CGFloat { x - x.rounded(.down) }

    private func hash(_ i: Int, _ salt: CGFloat) -> CGFloat {
        fract(sin(CGFloat(i + 1) * 127.1 + salt * 311.7) * 43758.5453)
    }
}
