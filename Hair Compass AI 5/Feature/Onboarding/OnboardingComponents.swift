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

// MARK: - Family-history risk arc

/// An arc gauge that fills to an evidence-grounded level (family history OR ~2.72) — context, never
/// a prediction.
struct RiskArc: View {
    var value: Double   // 0…1
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.5).rotation(.degrees(180))
                .stroke(Clinical.hairline, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            Circle().trim(from: 0, to: 0.5 * value).rotation(.degrees(180))
                .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
            VStack(spacing: 2) {
                Text(label).font(Clinical.headline(18)).foregroundStyle(Clinical.ink)
                Text("relative risk").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            }.offset(y: 10)
        }
        .frame(width: 150, height: 90, alignment: .top)
        .clipped()
    }
    private var label: String {
        switch value { case ..<0.15: return "Low"; case ..<0.5: return "Raised"; case ..<0.8: return "High"; default: return "Highest" }
    }
}

// MARK: - Per-condition demos

/// The "what are you noticing?" preview. Diffuse shedding gets the full falling-hair physics; pattern
/// loss gets a density fade; the rest get a calm animated motif.
struct ConditionDemo: View {
    let condition: HairCondition
    var body: some View {
        switch condition {
        case .telogenEffluvium: FallingHairView(intensity: 0.5)
        case .androgenetic: DensityFadeView()
        default: MotifView(symbol: symbol, tint: tint)
        }
    }
    private var symbol: String {
        switch condition {
        case .alopeciaAreata: return "circle.dashed"
        case .traction: return "arrow.up.and.down.and.arrow.left.and.right"
        case .seborrheicDermatitis: return "snowflake"
        default: return "sparkles"
        }
    }
    private var tint: Color { condition == .seborrheicDermatitis ? Clinical.sage : Clinical.accent }
}

/// A soft grid of rooted strands whose centre thins over time — reads as gradual pattern loss.
struct DensityFadeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 1.0 : (sin(tl.date.timeIntervalSinceReferenceDate * 0.7) * 0.5 + 0.5)
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

/// A calm breathing motif for the remaining options.
struct MotifView: View {
    let symbol: String
    var tint: Color = Clinical.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 64, weight: .light))
            .foregroundStyle(tint)
            .scaleEffect(on ? 1.06 : 0.94)
            .opacity(on ? 1 : 0.75)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Hair-care stressor demo

/// A single hero strand reacting to the three habit toggles: tension pulls it taut and frays the
/// tip, heat makes it wave + warm, chemical thins it.
struct StressStrandView: View {
    var tight: Bool
    var heat: Bool
    var chemical: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
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
