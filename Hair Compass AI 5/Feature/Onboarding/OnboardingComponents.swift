import SwiftUI

// MARK: - Shedding dial (the flagship interaction)

/// Vertical Minimal→Heavy dial. Dragging binds `intensity` (0…1) live, which drives the
/// FallingHairView behind it — the input literally is the simulation.
struct SheddingDial: View {
    @Binding var intensity: CGFloat
    private let bands = ["Minimal", "Normal", "Elevated", "Heavy"]

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height, pad: CGFloat = 14, thumb: CGFloat = 56
            let usable = max(1, h - 2 * pad - thumb)
            ZStack(alignment: .top) {
                Capsule().fill(Clinical.surface)
                    .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
                    .shadow(color: Clinical.cardShadow, radius: 10, y: 4)
                VStack { Spacer(); Capsule()
                    .fill(LinearGradient(colors: [Clinical.accent.opacity(0.16), Clinical.accent.opacity(0.32)], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(0, intensity * h)) }
                VStack(spacing: 0) {
                    ForEach(bands.reversed(), id: \.self) { b in
                        Text(b.uppercased()).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                            .frame(maxHeight: .infinity)
                    }
                }.padding(.vertical, 18)
                Circle().fill(Clinical.accent)
                    .frame(width: thumb, height: thumb)
                    .overlay(Text("SET").font(Clinical.eyebrow(10)).foregroundStyle(.white))
                    .shadow(color: Clinical.accent.opacity(0.4), radius: 8, y: 4)
                    .offset(y: pad + (1 - intensity) * usable)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let ni = 1 - (v.location.y - pad - thumb / 2) / usable
                intensity = min(1, max(0, ni))
                UISelectionFeedbackGenerator().selectionChanged()
            })
        }
    }

    static func band(_ i: CGFloat) -> Int { min(3, max(0, Int((i * 3).rounded()))) }
    static func shedLevel(_ i: CGFloat) -> ShedLevel { ShedLevel(rawValue: band(i)) ?? .normal }
    static func bandCaption(_ i: CGFloat) -> (String, String) {
        [("Minimal shed", "a few strands"), ("Typical shed", "a normal daily amount"),
         ("Elevated shed", "more than usual"), ("Heavy shed", "clumps / handfuls")][band(i)]
    }
}

// MARK: - Family-history risk gauge

/// A wide half-arc gauge that fills to an evidence-grounded level (family history OR ~2.72) with a
/// sweeping needle and banded labels — context, never a prediction. Replaces the earlier small
/// `RiskArc`; same call shape (`RiskGauge(value:)`), only caller is `OnboardingFlow.familyStep`.
struct RiskGauge: View {
    var value: Double   // 0…1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let width: CGFloat = 230
    private let height: CGFloat = 130
    private let radius: CGFloat = 80
    private let lineWidth: CGFloat = 14
    private let bandLabels = ["LOW", "RAISED", "HIGH", "HIGHEST"]
    private let bandWords = ["Low", "Raised", "High", "Highest"]

    private var clamped: Double { min(1, max(0, value)) }
    private var center: CGPoint { CGPoint(x: width / 2, y: height - 18) }

    /// Same bands as the earlier RiskArc label.
    private var activeIndex: Int {
        switch clamped {
        case ..<0.15: return 0
        case ..<0.5: return 1
        case ..<0.8: return 2
        default: return 3
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.5)
                .rotation(.degrees(180))
                .stroke(Clinical.hairline, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
                .position(center)

            Circle()
                .trim(from: 0, to: 0.5 * clamped)
                .rotation(.degrees(180))
                .stroke(
                    AngularGradient(colors: [Clinical.accentSoft, Clinical.accent], center: .center, startAngle: .degrees(180), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: clamped)

            // Needle: a thin round-capped line from the pivot (arc center) toward the value's point
            // on the arc — built as a custom Shape (not a rotated capsule) so `animatableData`
            // gives a genuinely smooth sweep rather than an offset/anchor guess.
            NeedleShape(value: clamped, center: center, length: radius - lineWidth / 2 - 6)
                .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: clamped)

            ForEach(Array(bandLabels.enumerated()), id: \.offset) { i, name in
                let on = i == activeIndex
                Text(name)
                    .font(Clinical.eyebrow(9))
                    .fontWeight(on ? .semibold : .regular)
                    .foregroundStyle(on ? Clinical.accent : Clinical.tertiary)
                    .position(point(atValue: Double(i) / 3, radius: radius + 14))
            }

            VStack(spacing: 2) {
                Text(bandWords[activeIndex]).font(Clinical.headline(22)).foregroundStyle(Clinical.ink)
                Text("relative odds").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            }
            .position(x: center.x, y: center.y - radius * 0.5)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)   // the option buttons below carry the semantics
    }

    /// A point on a circle of the given radius, at the same 180°(west)…360°(east) sweep — through
    /// the top — used by both the arc trim and the needle above.
    private func point(atValue v: Double, radius r: CGFloat) -> CGPoint {
        let theta = Angle.degrees(180 + 180 * v).radians
        return CGPoint(x: center.x + r * CGFloat(cos(theta)), y: center.y + r * CGFloat(sin(theta)))
    }
}

/// The risk gauge's needle, expressed as a genuine `Shape` (rather than a rotated view) so its
/// `animatableData` drives a continuous trig-computed sweep under the same spring as the arc fill.
private struct NeedleShape: Shape {
    var value: Double   // 0…1
    let center: CGPoint
    let length: CGFloat

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let theta = Angle.degrees(180 + 180 * value).radians
        let tip = CGPoint(x: center.x + length * CGFloat(cos(theta)), y: center.y + length * CGFloat(sin(theta)))
        var p = Path()
        p.move(to: center)
        p.addLine(to: tip)
        return p
    }
}

// MARK: - Per-condition demos

/// The "what are you noticing?" preview. Each condition gets a dedicated, honest demo of what its
/// pattern actually looks like — no generic pulsing icon.
struct ConditionDemo: View {
    let condition: HairCondition
    var body: some View {
        switch condition {
        case .telogenEffluvium: FallingHairView(intensity: 0.5)
        case .androgenetic: DensityFadeView()
        case .alopeciaAreata: PatchDemoView()
        case .traction: TractionDemoView()
        case .seborrheicDermatitis: FlakeDemoView()
        case .unsure: CompassDemoView()
        }
    }
}

/// A soft grid of rooted strands whose centre thins over time — reads as gradual pattern loss.
struct DensityFadeView: View {
    var body: some View {
        MotionTimeline(cadence: .ambient) { tl, reduceMotion in
            Canvas { ctx, size in
                let seconds = tl.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3600)
                let t = reduceMotion ? 1.0 : (sin(seconds * 0.7) * 0.5 + 0.5)
                let cols = 16, rows = 10
                let cx = size.width / 2, cy = size.height * 0.45
                let maxR = min(size.width, size.height) * 0.42
                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = size.width * (CGFloat(c) + 0.5) / CGFloat(cols)
                        let y = size.height * (CGFloat(r) + 0.5) / CGFloat(rows)
                        let d = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
                        // strands near the centre fade as `t` rises (crown thinning)
                        let central = max(0, 1 - d / maxR)
                        let alpha = max(0.05, 1 - central * (0.35 + 0.55 * t))
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y))
                        p.addQuadCurve(to: CGPoint(x: x + 2, y: y + 12), control: CGPoint(x: x - 2, y: y + 6))
                        ctx.stroke(p, with: .color(Clinical.ink.opacity(0.7 * alpha)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A field of short rooted strands (mirrors `DensityFadeView`'s grid) with an off-centre circular
/// patch that fades **fully out** — a sharp-edged bald patch, not a broad dimming — and regrows on
/// a slow ~6s cycle (fade ~2.2s, hold ~1s bald, regrow the remainder). Reads as smooth
/// alopecia-areata patches without claiming a diagnosis.
struct PatchDemoView: View {
    var body: some View {
        MotionTimeline(cadence: .ambient) { tl, reduceMotion in
            Canvas { ctx, size in
                let cols = 16, rows = 10
                let patchCenter = CGPoint(x: size.width * 0.62, y: size.height * 0.42)
                let patchR = min(size.width, size.height) * 0.24

                // 0 = full patch (all strands present), 1 = clean bald patch.
                let loss: Double
                if reduceMotion {
                    loss = 0.5   // static half-faded steady state
                } else {
                    let cycle = 6.0, fadeOut = 2.2, hold = 1.0
                    let regrow = cycle - fadeOut - hold
                    let seconds = tl.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 3600)
                    let phase = seconds.truncatingRemainder(dividingBy: cycle)
                    if phase < fadeOut {
                        loss = onboardEase(phase / fadeOut)
                    } else if phase < fadeOut + hold {
                        loss = 1
                    } else {
                        loss = max(0, 1 - onboardEase((phase - fadeOut - hold) / regrow))
                    }
                }

                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = size.width * (CGFloat(c) + 0.5) / CGFloat(cols)
                        let y = size.height * (CGFloat(r) + 0.5) / CGFloat(rows)
                        let d = ((x - patchCenter.x) * (x - patchCenter.x) + (y - patchCenter.y) * (y - patchCenter.y)).squareRoot()
                        // A narrow 10pt feather at the circle's edge keeps the boundary from
                        // aliasing on the grid while everywhere else stays either fully present
                        // (outside) or fully governed by `loss` (inside) — no broad halo of
                        // "just dimmer" strands.
                        let edge: CGFloat = 5
                        let inside = min(1, max(0, (patchR + edge - d) / (edge * 2)))
                        let alpha = max(0, 1 - inside * CGFloat(loss))
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y))
                        p.addQuadCurve(to: CGPoint(x: x + 2, y: y + 12), control: CGPoint(x: x - 2, y: y + 6))
                        ctx.stroke(p, with: .color(Clinical.ink.opacity(0.7 * alpha)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    }
                }
                if loss > 0.15 {
                    let ring = Path(ellipseIn: CGRect(x: patchCenter.x - patchR, y: patchCenter.y - patchR, width: patchR * 2, height: patchR * 2))
                    ctx.stroke(ring, with: .color(Clinical.accent.opacity(0.25 * loss)), style: StrokeStyle(lineWidth: 1))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Smoothstep ease (`3t²-2t³`), clamped — used for the patch demo's fade/regrow so the loop reads
/// as a soft, organic transition rather than a linear wipe.
private func onboardEase(_ x: Double) -> Double {
    let t = min(1, max(0, x))
    return t * t * (3 - 2 * t)
}

/// 5–6 strands anchored along a hairline arc; the outermost strands angle and straighten toward a
/// pull direction on a ~3s cycle, with tiny stress ticks at the anchor of the most-strained strand
/// while taut — the traction-alopecia mechanism made visible.
struct TractionDemoView: View {
    var body: some View {
        MotionTimeline(cadence: .interactive) { tl, reduceMotion in
            Canvas { ctx, size in
                let seconds = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3600)
                // 0 = relaxed, 1 = fully taut.
                let phase = reduceMotion ? 1.0 : (sin(seconds / 3.0 * 2 * .pi) * 0.5 + 0.5)

                let n = 6
                let arcY = size.height * 0.86
                let arcWidth = size.width * 0.7
                let startX = size.width * 0.15
                let strandLen = size.height * 0.62
                let pullX = size.width * 0.5

                for i in 0..<n {
                    let f = CGFloat(i) / CGFloat(n - 1)
                    let anchor = CGPoint(x: startX + arcWidth * f, y: arcY)
                    // Outermost strands (near the temples) feel the most pull.
                    let strain = phase * (0.35 + 0.65 * Double(abs(f - 0.5) * 2))
                    let restTipX = anchor.x + (f - 0.5) * 26
                    let tautTipX = pullX + (f - 0.5) * 6
                    let tipX = restTipX + (tautTipX - restTipX) * CGFloat(strain)
                    let tip = CGPoint(x: tipX, y: anchor.y - strandLen)

                    var strand = Path()
                    strand.move(to: anchor)
                    strand.addQuadCurve(to: tip, control: CGPoint(x: (anchor.x + tipX) / 2, y: anchor.y - strandLen * 0.55))
                    ctx.stroke(strand, with: .color(Clinical.ink.opacity(0.75)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

                    if strain > 0.55 {
                        for k in 0..<3 {
                            let a = Double(k) / 3 * .pi - .pi / 2
                            let tickStart = CGPoint(x: anchor.x + CGFloat(cos(a)) * 5, y: anchor.y + CGFloat(sin(a)) * 5)
                            let tickEnd = CGPoint(x: anchor.x + CGFloat(cos(a)) * 11, y: anchor.y + CGFloat(sin(a)) * 11)
                            var tick = Path()
                            tick.move(to: tickStart); tick.addLine(to: tickEnd)
                            ctx.stroke(tick, with: .color(Clinical.accent.opacity((strain - 0.55) * 2)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A clear scalp band across the top third (the part line, filled and legible — not just an
/// off-canvas ellipse), with larger rounded copper/ivory flakes detaching and drifting down with a
/// slight sway, and a slightly stronger warm blush pulsing under the band for the itch/redness.
struct FlakeDemoView: View {
    var body: some View {
        MotionTimeline(cadence: .ambient) { tl, reduceMotion in
            Canvas { ctx, size in
                let seconds = tl.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3600)

                // The scalp band: a filled shape across the top third, its lower edge dipping
                // gently like a visible part line.
                let bandBottom = size.height * 0.30
                let bandDip = size.height * 0.10
                var band = Path()
                band.move(to: CGPoint(x: 0, y: 0))
                band.addLine(to: CGPoint(x: 0, y: bandBottom))
                band.addQuadCurve(to: CGPoint(x: size.width, y: bandBottom), control: CGPoint(x: size.width / 2, y: bandDip))
                band.addLine(to: CGPoint(x: size.width, y: 0))
                band.closeSubpath()
                ctx.fill(band, with: .color(Clinical.secondary.opacity(0.15)))

                var bandEdge = Path()
                bandEdge.move(to: CGPoint(x: 0, y: bandBottom))
                bandEdge.addQuadCurve(to: CGPoint(x: size.width, y: bandBottom), control: CGPoint(x: size.width / 2, y: bandDip))
                ctx.stroke(bandEdge, with: .color(Clinical.ink.opacity(0.3)), style: StrokeStyle(lineWidth: 1.2))

                // Warm blush pulsing under the band — the itch/redness cue, a touch stronger than
                // the earlier pass.
                let pulse = reduceMotion ? 0.6 : (sin(seconds * 1.4) * 0.5 + 0.5)
                let blushRect = CGRect(x: size.width * 0.08, y: bandDip - 6, width: size.width * 0.84, height: bandBottom - bandDip + 30)
                ctx.fill(Path(ellipseIn: blushRect), with: .color(Clinical.warning.opacity(0.16 * pulse)))

                let count = 14
                for i in 0..<count {
                    let speedFactor = 0.55 + onboardHashUnit(i, salt: 5) * 0.5
                    let cycle = 2.6 / speedFactor
                    let t: CGFloat
                    if reduceMotion {
                        // Static mid-frame: hold flakes mid-fall (near the fade-envelope's peak)
                        // rather than freezing at a random moment that could read as empty.
                        t = 0.45 + onboardHashUnit(i, salt: 9) * 0.3
                    } else {
                        let raw = seconds / Double(cycle) + Double(onboardHashUnit(i, salt: 3))
                        t = CGFloat(raw - raw.rounded(.down))
                    }
                    let sway = sin(Double(t) * .pi * 2 + Double(i)) * 6
                    let x = size.width * (0.15 + onboardHashUnit(i, salt: 7) * 0.7) + CGFloat(sway)
                    let y = bandBottom - 6 + t * size.height * 0.68
                    let r: CGFloat = 3 + onboardHashUnit(i, salt: 11) * 2   // larger flakes: 3–5pt
                    let alpha = min(1, t * 4) * min(1, (1 - t) * 4)
                    let flakeRect = CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4)
                    if onboardHashUnit(i, salt: 13) < 0.55 {
                        // Copper flake.
                        ctx.fill(Path(roundedRect: flakeRect, cornerRadius: r * 0.6), with: .color(Clinical.accent.opacity(0.55 * alpha)))
                    } else {
                        // Ivory flake, outlined so it reads against the panel background.
                        ctx.fill(Path(roundedRect: flakeRect, cornerRadius: r * 0.6), with: .color(Clinical.canvas.opacity(alpha)))
                        ctx.stroke(Path(roundedRect: flakeRect, cornerRadius: r * 0.6), with: .color(Clinical.hairline.opacity(alpha)), style: StrokeStyle(lineWidth: 0.8))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A thin circle with a copper needle that gently swings and settles — the brand's compass motif,
/// used for "not sure yet" so the app itself models "we'll find the pattern together."
struct CompassDemoView: View {
    var body: some View {
        MotionTimeline(cadence: .ambient) { tl, reduceMotion in
            Canvas { ctx, size in
                let seconds = tl.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3600)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.32

                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(Clinical.hairline), style: StrokeStyle(lineWidth: 1.5))
                for i in 0..<12 {
                    let a = Double(i) / 12 * 2 * .pi
                    let inner = CGPoint(x: center.x + CGFloat(cos(a)) * radius * 0.88, y: center.y + CGFloat(sin(a)) * radius * 0.88)
                    let outer = CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)
                    var tick = Path()
                    tick.move(to: inner); tick.addLine(to: outer)
                    ctx.stroke(tick, with: .color(Clinical.tertiary.opacity(0.5)), style: StrokeStyle(lineWidth: 1))
                }

                // A gentle decaying swing that settles every ~8s, then swings again.
                let restAngle = -Double.pi / 2
                let swing = reduceMotion ? 0 : sin(seconds * 1.1) * 0.35 * exp(-(seconds.truncatingRemainder(dividingBy: 8)) / 8)
                let angle = restAngle + swing
                let tip = CGPoint(x: center.x + CGFloat(cos(angle)) * radius * 0.82, y: center.y + CGFloat(sin(angle)) * radius * 0.82)
                let tail = CGPoint(x: center.x - CGFloat(cos(angle)) * radius * 0.42, y: center.y - CGFloat(sin(angle)) * radius * 0.42)
                var needle = Path()
                needle.move(to: tail); needle.addLine(to: tip)
                ctx.stroke(needle, with: .color(Clinical.accent), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(Clinical.accent))
            }
        }
        .accessibilityHidden(true)
    }
}

private func onboardHashUnit(_ index: Int, salt: Int) -> CGFloat {
    let value = sin(CGFloat((index + 1) * 127 + salt * 313)) * 43_758.5453
    return value - value.rounded(.down)
}

// MARK: - Hair-care stressor demo

/// A single hero strand reacting to the three habit toggles: tension pulls it taut and frays the
/// tip, heat makes it wave + warm, chemical thins it.
struct StressStrandView: View {
    var tight: Bool
    var heat: Bool
    var chemical: Bool

    var body: some View {
        MotionTimeline(cadence: .interactive) { tl, reduceMotion in
            Canvas { ctx, size in
                let t = reduceMotion
                    ? 0
                    : tl.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 3600)
                let x = size.width / 2
                let top = size.height * 0.12, bottom = size.height * 0.82
                let n = 14
                var path = Path()
                for i in 0...n {
                    let f = CGFloat(i) / CGFloat(n)
                    let y = top + (bottom - top) * f
                    // tension straightens; heat waves; base curl otherwise
                    let curl: CGFloat = tight ? 3 : 16
                    let wave: Double = heat ? sin(t * 3 + Double(f) * 8) * 10 : 0
                    let px = x + sin(f * 3.14 * (tight ? 0.4 : 1.2)) * curl + CGFloat(wave)
                    if i == 0 { path.move(to: CGPoint(x: px, y: y)) } else { path.addLine(to: CGPoint(x: px, y: y)) }
                }
                let color = heat ? Clinical.warning : Clinical.ink
                let width: CGFloat = chemical ? 1.0 : 3.0
                ctx.stroke(path, with: .color(color.opacity(chemical ? 0.5 : 0.9)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                // fray at the follicle when tight
                if tight {
                    for k in 0..<5 {
                        let a = Double(k) / 5 * 6.28 + t
                        var fp = Path()
                        fp.move(to: CGPoint(x: x, y: bottom))
                        fp.addLine(to: CGPoint(x: x + CGFloat(cos(a)) * 10, y: bottom + CGFloat(sin(a)) * 6 + 4))
                        ctx.stroke(fp, with: .color(Clinical.accent.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    }
                }
                // chemical droplet
                if chemical {
                    let dy = (t.truncatingRemainder(dividingBy: 2)) / 2
                    let py = top + (bottom - top) * CGFloat(dy)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: py - 4, width: 8, height: 10)), with: .color(Clinical.sage.opacity(0.6)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
