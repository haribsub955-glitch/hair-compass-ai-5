import SwiftUI

/// The shared falling-hair engine (SwiftUI Canvas + TimelineView). Each strand is a 3-point Verlet
/// chain that bends as it falls; `intensity` (0…1) drives spawn rate, gravity, and sway so the
/// answer literally *is* the simulation. Canvas is the backbone; SpriteKit stays an upgrade path if
/// we ever want thousands of particles (see the onboarding spec).

// MARK: - Pure, testable simulation

struct HairStrand {
    var p: [CGPoint]      // 3 chain points (root → tip)
    var old: [CGPoint]
    let seg: CGFloat
    let phase: CGFloat
    let width: CGFloat
    let drag: CGFloat
    let colorIndex: Int
}

struct HairSim {
    var strands: [HairStrand] = []
    var size: CGSize = .zero
    private var spawnAcc: CGFloat = 0

    static let maxStrands = 220
    static func spawnRate(_ i: CGFloat) -> CGFloat { 1.1 + i * i * 22 }   // strands/sec
    static func gravity(_ i: CGFloat) -> CGFloat { 620 + i * 640 }        // pt/s²
    static func sway(_ i: CGFloat) -> CGFloat { 46 + i * 95 }             // lateral amplitude

    /// One physics step. `rand` is injected so tests are deterministic.
    mutating func step(dt: CGFloat, time: CGFloat, intensity: CGFloat, rand: () -> CGFloat = { CGFloat.random(in: 0...1) }) {
        guard size != .zero, dt > 0 else { return }
        spawnAcc += dt * Self.spawnRate(intensity)
        while spawnAcc >= 1, strands.count < Self.maxStrands {
            strands.append(Self.makeStrand(size: size, rand: rand))
            spawnAcc -= 1
        }
        if spawnAcc > 4 { spawnAcc = 4 }

        let g = Self.gravity(intensity), swayA = Self.sway(intensity)
        for i in strands.indices { Self.integrate(&strands[i], dt: dt, time: time, g: g, swayA: swayA) }
        strands.removeAll { min($0.p[0].y, $0.p[2].y) > size.height + 30 }
    }

    static func makeStrand(size: CGSize, rand: () -> CGFloat) -> HairStrand {
        let x = rand() * size.width
        let y = -10 - rand() * 40
        let seg = 9 + rand() * 8
        let ang = (rand() - 0.5) * 0.8
        var p: [CGPoint] = [], old: [CGPoint] = []
        for k in 0..<3 {
            let px = x + sin(ang) * seg * CGFloat(k)
            let py = y + cos(ang) * seg * CGFloat(k)
            p.append(CGPoint(x: px, y: py))
            old.append(CGPoint(x: px - (rand() - 0.5) * 2, y: py))
        }
        return HairStrand(p: p, old: old, seg: seg, phase: rand() * 6.28,
                          width: 1.7 + rand() * 1.7, drag: 0.008 + rand() * 0.01, colorIndex: Int(rand() * 5) % 5)
    }

    static func integrate(_ s: inout HairStrand, dt: CGFloat, time: CGFloat, g: CGFloat, swayA: CGFloat) {
        for k in 0..<3 {
            let pt = s.p[k], o = s.old[k]
            let vx = (pt.x - o.x) * (1 - s.drag)
            let vy = (pt.y - o.y) * (1 - s.drag)
            s.old[k] = pt
            let ax = sin(time * 2.1 + s.phase + CGFloat(k) * 0.5) * swayA * (0.4 + CGFloat(k) * 0.4)
            s.p[k] = CGPoint(x: pt.x + vx + ax * dt * dt, y: pt.y + vy + g * dt * dt)
        }
        // distance constraints keep it a coherent strand
        for _ in 0..<2 {
            for k in 0..<2 {
                let a = s.p[k], b = s.p[k + 1]
                var dx = b.x - a.x, dy = b.y - a.y
                let d = max(0.001, (dx * dx + dy * dy).squareRoot())
                let diff = (d - s.seg) / d * 0.5
                dx *= diff; dy *= diff
                s.p[k] = CGPoint(x: a.x + dx, y: a.y + dy)
                s.p[k + 1] = CGPoint(x: b.x - dx, y: b.y - dy)
            }
        }
    }
}

// MARK: - SwiftUI view

/// Reference box so the per-frame step mutates in place without thrashing SwiftUI state — the
/// TimelineView already drives one redraw per frame.
@MainActor private final class HairSimBox {
    var sim = HairSim()
    var last: Date?
    var staticStrands: [HairStrand] = []
}

struct FallingHairView: View {
    var intensity: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var box = HairSimBox()

    private static let palette: [Color] = [Clinical.accent, Clinical.ink, Clinical.secondary, Clinical.sage, Clinical.gold]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                box.sim.size = size
                if reduceMotion {
                    drawStatic(ctx, size: size)
                } else {
                    let now = timeline.date
                    let dt = box.last.map { min(CGFloat(now.timeIntervalSince($0)), 0.05) } ?? 0
                    box.last = now
                    box.sim.step(dt: dt, time: CGFloat(now.timeIntervalSinceReferenceDate), intensity: intensity)
                    for s in box.sim.strands { drawStrand(ctx, s, height: size.height) }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func drawStrand(_ ctx: GraphicsContext, _ s: HairStrand, height: CGFloat) {
        let bottom = max(s.p[0].y, s.p[2].y)
        let fade = bottom > height - 60 ? max(0, (height - bottom) / 60) : 1
        var path = Path()
        path.move(to: s.p[0])
        path.addQuadCurve(to: s.p[2], control: s.p[1])
        ctx.stroke(path, with: .color(Self.palette[s.colorIndex].opacity(0.85 * fade)),
                   style: StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round))
    }

    private func drawStatic(_ ctx: GraphicsContext, size: CGSize) {
        if box.staticStrands.isEmpty {
            var seed: UInt64 = 42
            func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max) }
            let n = Int(8 + intensity * 60)
            box.sim.size = size
            for _ in 0..<n {
                var s = HairSim.makeStrand(size: size, rand: rnd)
                let dy = rnd() * size.height
                s.p = s.p.map { CGPoint(x: $0.x, y: $0.y + dy) }
                box.staticStrands.append(s)
            }
        }
        for s in box.staticStrands { drawStrand(ctx, s, height: size.height + 100) }
    }
}
