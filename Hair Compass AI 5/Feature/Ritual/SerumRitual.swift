import SwiftUI

/// Serum drops (`serum`) — spec §3.3. Hold anywhere to swell a drop at the dropper's tip; release
/// and it falls under gravity into a 1-D wave pool at the bottom. Each impact ripples the surface,
/// throws splash droplets, and raises the level (~10 drops). When the still surface reaches the
/// dashed copper target line at 72% height it completes — RitualView plays the copper-burst finish.
struct SerumRitual: Ritual {
    let kind: RitualKind = .serum
    let title = "One drop at a time"
    let hint = "Hold to fill the drop, release to let it fall."

    // MARK: Tuning (spec §3.3)
    private static let columns = 120
    private static let tipFrac: CGFloat = 0.37
    private static let targetFrac: CGFloat = 0.72
    private static let fillScale: CGFloat = 0.38          // maps `level` → pool height (≈10 drops to target)
    private static let chargeRate: CGFloat = 0.02         // per frame while holding
    private static let dropGravity: CGFloat = 0.55        // per frame²
    /// `level` needed for the still surface to reach the target line (size-independent).
    private static var completeLevel: CGFloat { (1 - targetFrac) / fillScale }

    private struct Drop { var x: CGFloat; var y: CGFloat; var r: CGFloat; var vy: CGFloat }
    private struct Splash { var pos: CGPoint; var vel: CGPoint; var r: CGFloat; var life: CGFloat; var maxLife: CGFloat }

    private var h = [CGFloat](repeating: 0, count: 120)   // surface height offset per column
    private var v = [CGFloat](repeating: 0, count: 120)   // surface velocity per column
    private var level: CGFloat = 0
    private var charge: CGFloat = 0
    private var holding = false
    private var releaseRequested = false
    private var drops: [Drop] = []
    private var splashes: [Splash] = []
    private var time: CGFloat = 0

    // MARK: Ritual

    var isComplete: Bool { level >= Self.completeLevel }
    var progress: CGFloat { min(1, level / Self.completeLevel) }
    var estimatedDuration: TimeInterval? { nil }   // interaction-paced — no fixed end time

    mutating func handle(_ touch: RitualTouch) {
        switch touch.phase {
        case .began, .moved:
            holding = true
        case .ended:
            holding = false
            releaseRequested = true
        }
    }

    @discardableResult
    mutating func step(dt: CGFloat, size: CGSize) -> Int {
        guard size != .zero else { return 0 }
        time += dt
        var beats = 0

        let tip = CGPoint(x: size.width / 2, y: size.height * Self.tipFrac)
        let baseY = size.height * (1 - level * Self.fillScale)
        let colW = size.width / CGFloat(Self.columns)

        // Charge the pending drop while holding.
        if holding { charge = min(2.5, charge + Self.chargeRate) }

        // Release → detach a falling drop from the tip.
        if releaseRequested {
            releaseRequested = false
            if charge > 0 {
                let r = 3 + charge * 12
                drops.append(Drop(x: tip.x, y: tip.y + r, r: r, vy: 0))
                charge = 0
            }
        }

        // Falling drops (per-frame gravity).
        var i = 0
        while i < drops.count {
            drops[i].vy += Self.dropGravity
            drops[i].y += drops[i].vy
            if drops[i].y >= baseY {
                let d = drops[i]
                let col = min(Self.columns - 1, max(0, Int(d.x / colW)))
                // Impulse ∝ drop radius, spread lightly to neighbours.
                v[col] -= d.r * 0.9
                if col > 0 { v[col - 1] -= d.r * 0.4 }
                if col < Self.columns - 1 { v[col + 1] -= d.r * 0.4 }
                // 5 splash droplets.
                for _ in 0..<5 {
                    let life = CGFloat.random(in: 0.4...0.8)
                    splashes.append(Splash(
                        pos: CGPoint(x: d.x, y: baseY),
                        vel: CGPoint(x: CGFloat.random(in: -70...70), y: -CGFloat.random(in: 50...130)),
                        r: CGFloat.random(in: 1.5...3), life: life, maxLife: life))
                }
                level = min(1, level + 0.055 + d.r * 0.003)
                beats += 1
                drops.remove(at: i)
            } else {
                i += 1
            }
        }

        // Wave surface: two sub-steps per frame.
        for _ in 0..<2 {
            var nv = v
            for c in 0..<Self.columns {
                let left = h[max(0, c - 1)]
                let right = h[min(Self.columns - 1, c + 1)]
                nv[c] += 0.12 * (left + right - 2 * h[c]) - 0.004 * h[c]
            }
            for c in 0..<Self.columns {
                v[c] = nv[c] * 0.993          // damping
                h[c] += v[c]
            }
        }

        // Splash droplets (cosmetic, dt-based).
        for s in splashes.indices {
            splashes[s].vel.y += 220 * dt
            splashes[s].pos.x += splashes[s].vel.x * dt
            splashes[s].pos.y += splashes[s].vel.y * dt
            splashes[s].life -= dt
        }
        splashes.removeAll { $0.life <= 0 }

        return beats
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let tip = CGPoint(x: size.width / 2, y: size.height * Self.tipFrac)
        let baseY = size.height * (1 - level * Self.fillScale)
        let colW = size.width / CGFloat(Self.columns)
        let targetY = size.height * Self.targetFrac

        // Pool body (translucent copper) with wavy top edge.
        var pool = Path()
        pool.move(to: CGPoint(x: 0, y: size.height))
        pool.addLine(to: CGPoint(x: 0, y: baseY - h[0]))
        for c in 0..<Self.columns {
            pool.addLine(to: CGPoint(x: CGFloat(c) * colW, y: baseY - h[c]))
        }
        pool.addLine(to: CGPoint(x: size.width, y: baseY - h[Self.columns - 1]))
        pool.addLine(to: CGPoint(x: size.width, y: size.height))
        pool.closeSubpath()
        ctx.fill(pool, with: .color(Clinical.accent.opacity(0.35)))

        // Surface line.
        var surface = Path()
        surface.move(to: CGPoint(x: 0, y: baseY - h[0]))
        for c in 0..<Self.columns { surface.addLine(to: CGPoint(x: CGFloat(c) * colW, y: baseY - h[c])) }
        ctx.stroke(surface, with: .color(Clinical.accent.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        // Dashed copper target line at 72% height.
        var target = Path()
        target.move(to: CGPoint(x: 22, y: targetY))
        target.addLine(to: CGPoint(x: size.width - 22, y: targetY))
        ctx.stroke(target, with: .color(Clinical.accent.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))

        // Splash droplets.
        for s in splashes {
            let rect = CGRect(x: s.pos.x - s.r, y: s.pos.y - s.r, width: s.r * 2, height: s.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(Clinical.accent.opacity(Double(min(1, s.life / s.maxLife)) * 0.9)))
        }

        // Falling drops.
        for d in drops {
            let rect = CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2, height: d.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(Clinical.accent.opacity(0.85)))
        }

        // The glass dropper.
        drawDropper(in: &ctx, tip: tip)

        // Pending charging drop at the tip (slight wobble).
        if holding && charge > 0 {
            let r = 3 + charge * 12
            let wob = sin(time * 8) * 1.5
            let rect = CGRect(x: tip.x - r + wob, y: tip.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(Clinical.accent.opacity(0.85)))
        }
    }

    // MARK: Dropper

    private func drawDropper(in ctx: inout GraphicsContext, tip: CGPoint) {
        let bulbR: CGFloat = 17
        let bulbCenter = CGPoint(x: tip.x, y: tip.y - 80)
        let topY = bulbCenter.y + bulbR - 2

        // Tapering glass body from below the bulb down to the tip.
        var body = Path()
        body.move(to: CGPoint(x: tip.x - 9, y: topY))
        body.addLine(to: CGPoint(x: tip.x - 2.5, y: tip.y))
        body.addQuadCurve(to: CGPoint(x: tip.x + 2.5, y: tip.y), control: CGPoint(x: tip.x, y: tip.y + 3))
        body.addLine(to: CGPoint(x: tip.x + 9, y: topY))
        body.closeSubpath()
        ctx.fill(body, with: .color(Color.white.opacity(0.18)))   // translucent glass

        // Inner serum fill (lower ~80% of the body).
        var serum = Path()
        let serumTop = topY + (tip.y - topY) * 0.2
        serum.move(to: CGPoint(x: tip.x - 6.5, y: serumTop))
        serum.addLine(to: CGPoint(x: tip.x - 2.5, y: tip.y))
        serum.addQuadCurve(to: CGPoint(x: tip.x + 2.5, y: tip.y), control: CGPoint(x: tip.x, y: tip.y + 3))
        serum.addLine(to: CGPoint(x: tip.x + 6.5, y: serumTop))
        serum.closeSubpath()
        ctx.fill(serum, with: .color(Clinical.accent.opacity(0.8)))

        ctx.stroke(body, with: .color(Clinical.accent.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        // Rubber bulb.
        let bulb = Path(ellipseIn: CGRect(x: bulbCenter.x - bulbR, y: bulbCenter.y - bulbR, width: bulbR * 2, height: bulbR * 2))
        ctx.fill(bulb, with: .color(Color.white.opacity(0.18)))
        ctx.fill(Path(ellipseIn: CGRect(x: bulbCenter.x - bulbR + 3, y: bulbCenter.y - bulbR + 4, width: bulbR * 2 - 6, height: bulbR)), with: .color(Clinical.accent.opacity(0.5)))
        ctx.stroke(bulb, with: .color(Clinical.accent.opacity(0.55)), style: StrokeStyle(lineWidth: 2))
    }
}
