import SwiftUI

/// Combing (`comb`) — auto "smoothing pass" (design doc 2026-07-11 §1). Five wavy vertical locks
/// straighten on their own as a soft copper→gold light bar sweeps top→bottom **once** over ~0.9s,
/// with a cream sparkle trail following the bar. A touch anywhere nudges the sweep forward a
/// little faster, but the pass always finishes on its own in ~1s — no combing required.
struct CombRitual: Ritual {
    let kind: RitualKind = .comb
    let title = "Smooth"
    let hint = "One clean pass — you're set."

    // MARK: Tuning
    private static let lockCount = 5
    private static let pointCount = 26
    private static let yTop: CGFloat = 0.30, yBottom: CGFloat = 0.85
    private static let xLeft: CGFloat = 0.22, xRight: CGFloat = 0.78
    private static let sweepDuration: CGFloat = 0.9    // sweep fraction `sy` reaches 1 at this elapsed time
    private static let totalDuration: CGFloat = 1.0    // isComplete gate
    private static let smoothGain: CGFloat = 0.25      // per-frame smoothness gain behind the bar
    private static let beatThreshold: CGFloat = 0.9    // lock-average crossing that fires a beat
    private static let touchBoost: CGFloat = 0.06      // elapsed added per began/moved touch sample

    private struct StrandPoint { var a: CGFloat; var s: CGFloat }
    private struct Lock {
        var xFrac: CGFloat
        var freq: CGFloat
        var phase: CGFloat
        var points: [StrandPoint]
        var rewarded: Bool
    }
    private struct Sparkle { var pos: CGPoint; var vel: CGPoint; var life: CGFloat; var maxLife: CGFloat }

    // Locks are built eagerly (a static factory feeding the property default) rather than lazily
    // on first `step()`, because `draw` is non-mutating and Reduce Motion calls `draw` without
    // ever calling `step` — the locks must already exist for that first static frame.
    private var locks: [Lock] = CombRitual.build()
    private var time: CGFloat = 0
    private var sparkles: [Sparkle] = []
    private var sparkleAcc: CGFloat = 0

    // MARK: Ritual

    var isComplete: Bool { time >= Self.totalDuration }

    mutating func handle(_ touch: RitualTouch) {
        switch touch.phase {
        case .began, .moved:
            time += Self.touchBoost
        case .ended:
            break
        }
    }

    @discardableResult
    mutating func step(dt: CGFloat, size: CGSize) -> Int {
        guard size != .zero else { return 0 }
        time += dt
        var beats = 0

        let sy = min(1, time / Self.sweepDuration)
        let denom = CGFloat(Self.pointCount - 1)

        // Straighten every point the bar has already swept past this frame.
        for li in locks.indices {
            for j in locks[li].points.indices {
                let pointFrac = CGFloat(j) / denom
                if pointFrac <= sy {
                    locks[li].points[j].s = min(1, locks[li].points[j].s + Self.smoothGain)
                }
            }
        }

        // One beat per lock the moment its average first crosses the reward threshold.
        for li in locks.indices {
            if !locks[li].rewarded && lockAvg(locks[li]) > Self.beatThreshold {
                locks[li].rewarded = true
                beats += 1
            }
        }

        // Sparkle trail riding the sweep bar while it's still moving.
        if sy < 1 { spawnSparkles(size: size, sy: sy, dt: dt) }
        for si in sparkles.indices {
            sparkles[si].pos.x += sparkles[si].vel.x * dt
            sparkles[si].pos.y += sparkles[si].vel.y * dt
            sparkles[si].life -= dt
        }
        sparkles.removeAll { $0.life <= 0 }

        return beats
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let sy = min(1, time / Self.sweepDuration)

        // 3-stroke lock render (shadow / main / highlight), unchanged from the original.
        for lock in locks {
            let path = lockPath(lock, size: size)
            let avg = lockAvg(lock)

            let shadow = path.applying(CGAffineTransform(translationX: 1.6, y: 0))
            ctx.stroke(shadow, with: .color(Clinical.ink.opacity(0.25)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

            let main = Clinical.accent.mix(with: Clinical.gold, by: Double(min(1, avg * 0.75)))
            ctx.stroke(path, with: .color(main),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

            let highlight = path.applying(CGAffineTransform(translationX: -1.1, y: 0))
            ctx.stroke(highlight, with: .color(Color.white.opacity(Double(0.12 + 0.55 * avg))),
                       style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }

        // The sweep bar: a soft copper→gold blurred blob riding the sweep y across the strand band.
        if sy < 1 {
            let y = size.height * (Self.yTop + (Self.yBottom - Self.yTop) * sy)
            let xL = size.width * Self.xLeft - 20, xR = size.width * Self.xRight + 20
            let bar = Path(CGRect(x: xL, y: y - 5, width: xR - xL, height: 10))
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 8))
                layer.fill(bar, with: .linearGradient(
                    Gradient(colors: [Clinical.accent.opacity(0.85), Clinical.gold.opacity(0.85)]),
                    startPoint: CGPoint(x: xL, y: y), endPoint: CGPoint(x: xR, y: y)))
            }
        }

        // Cream sparkle trail.
        for sp in sparkles {
            let a = Double(max(0, sp.life / sp.maxLife)) * 0.85
            let r: CGFloat = 1.6
            let dot = Path(ellipseIn: CGRect(x: sp.pos.x - r, y: sp.pos.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(Color.white.opacity(a)))
        }
    }

    // MARK: Helpers

    private static func build() -> [Lock] {
        var result: [Lock] = []
        for i in 0..<lockCount {
            let xFrac = xLeft + (xRight - xLeft) * CGFloat(i) / CGFloat(lockCount - 1)
            let freq = 0.45 + CGFloat.random(in: 0...1) * 0.25
            let phase = CGFloat.random(in: 0...(2 * .pi))
            var pts: [StrandPoint] = []
            for _ in 0..<pointCount {
                pts.append(StrandPoint(a: 10 + CGFloat.random(in: 0...1) * 16, s: 0))
            }
            result.append(Lock(xFrac: xFrac, freq: freq, phase: phase, points: pts, rewarded: false))
        }
        return result
    }

    private func pointPosition(lock: Lock, j: Int, size: CGSize) -> CGPoint {
        let p = lock.points[j]
        let yFrac = Self.yTop + (Self.yBottom - Self.yTop) * CGFloat(j) / CGFloat(Self.pointCount - 1)
        let xOff = sin(CGFloat(j) * lock.freq + lock.phase + time / 1.6) * p.a * (1 - p.s)
                 + sin(time / 2.4 + lock.phase) * 2.5
        return CGPoint(x: size.width * lock.xFrac + xOff, y: size.height * yFrac)
    }

    private func lockPath(_ lock: Lock, size: CGSize) -> Path {
        var path = Path()
        let pts = (0..<lock.points.count).map { pointPosition(lock: lock, j: $0, size: size) }
        guard let first = pts.first else { return path }
        path.move(to: first)
        for k in 1..<pts.count {
            let mid = CGPoint(x: (pts[k - 1].x + pts[k].x) / 2, y: (pts[k - 1].y + pts[k].y) / 2)
            path.addQuadCurve(to: mid, control: pts[k - 1])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    private func lockAvg(_ lock: Lock) -> CGFloat {
        guard !lock.points.isEmpty else { return 0 }
        var total: CGFloat = 0
        for p in lock.points { total += p.s }
        return total / CGFloat(lock.points.count)
    }

    private mutating func spawnSparkles(size: CGSize, sy: CGFloat, dt: CGFloat) {
        sparkleAcc += dt * 45   // ~45 sparkles/sec while the bar is moving
        let y = size.height * (Self.yTop + (Self.yBottom - Self.yTop) * sy)
        let xL = size.width * Self.xLeft, xR = size.width * Self.xRight
        while sparkleAcc >= 1 {
            sparkleAcc -= 1
            let life = CGFloat.random(in: 0.3...0.6)
            sparkles.append(Sparkle(
                pos: CGPoint(x: CGFloat.random(in: xL...xR), y: y + CGFloat.random(in: -4...4)),
                vel: CGPoint(x: CGFloat.random(in: -10...10), y: -CGFloat.random(in: 20...40)),
                life: life, maxLife: life))
        }
        if sparkleAcc > 4 { sparkleAcc = 4 }
    }
}
