import SwiftUI

/// Combing (`comb`) — spec §3.1. Five vertical locks of wavy strand that straighten and shift
/// copper→gold as you run a finger down them; a comb asset tracks the finger, cream sparkles drift
/// up, and each fully-smoothed lock gets a sweeping light blob. Complete at overall average s > 0.94.
struct CombRitual: Ritual {
    let kind: RitualKind = .comb
    let title = "Comb it smooth"
    let hint = "Run your finger down each strand."

    // MARK: Tuning (spec §3.1)
    private static let lockCount = 5
    private static let pointCount = 26
    private static let yTop: CGFloat = 0.30, yBottom: CGFloat = 0.85
    private static let xLeft: CGFloat = 0.22, xRight: CGFloat = 0.78
    private static let reach: CGFloat = 58            // combing radius
    private static let completeThreshold: CGFloat = 0.94
    private static let rewardThreshold: CGFloat = 0.985
    private static let rewardDuration: CGFloat = 0.7

    private struct StrandPoint { var a: CGFloat; var s: CGFloat }
    private struct Lock {
        var xFrac: CGFloat
        var freq: CGFloat
        var phase: CGFloat
        var points: [StrandPoint]
        var rewardStart: CGFloat?
        var rewarded: Bool
    }
    private struct Sparkle { var pos: CGPoint; var vel: CGPoint; var life: CGFloat; var maxLife: CGFloat }

    private var locks: [Lock] = []
    private var built = false
    private var time: CGFloat = 0
    private var finger: CGPoint?
    private var dragging = false
    private var sparkles: [Sparkle] = []
    private var sparkleAcc: CGFloat = 0

    // MARK: Ritual

    var isComplete: Bool {
        guard !locks.isEmpty else { return false }
        var total: CGFloat = 0, count = 0
        for lock in locks { for p in lock.points { total += p.s; count += 1 } }
        return count > 0 && total / CGFloat(count) > Self.completeThreshold
    }

    mutating func handle(_ touch: RitualTouch) {
        switch touch.phase {
        case .began, .moved:
            dragging = true
            finger = touch.location
        case .ended:
            dragging = false
        }
    }

    @discardableResult
    mutating func step(dt: CGFloat, size: CGSize) -> Int {
        guard size != .zero else { return 0 }
        if !built { build() }
        time += dt
        var beats = 0

        // Combing: any point within reach of the finger gains smoothness this frame.
        if dragging, let f = finger {
            for li in locks.indices {
                for j in locks[li].points.indices {
                    let pos = pointPosition(lock: locks[li], j: j, size: size)
                    let dx = pos.x - f.x, dy = pos.y - f.y
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d < Self.reach {
                        let gain = 0.13 * (1 - d / Self.reach) + 0.02
                        locks[li].points[j].s = min(1, locks[li].points[j].s + gain)
                    }
                }
            }
            spawnSparkles(at: f, dt: dt)
        }

        // Reward: when a lock crosses the smoothing threshold, kick off its sweeping light blob.
        for li in locks.indices {
            if lockAvg(locks[li]) > Self.rewardThreshold && !locks[li].rewarded {
                locks[li].rewarded = true
                locks[li].rewardStart = time
                beats += 1
            }
        }

        // Advance sparkles.
        for si in sparkles.indices {
            sparkles[si].pos.x += sparkles[si].vel.x * dt
            sparkles[si].pos.y += sparkles[si].vel.y * dt
            sparkles[si].life -= dt
        }
        sparkles.removeAll { $0.life <= 0 }

        return beats
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        guard built else { return }

        for lock in locks {
            let path = lockPath(lock, size: size)
            let avg = lockAvg(lock)

            // 3-stroke render over the same path.
            let shadow = path.applying(CGAffineTransform(translationX: 1.6, y: 0))
            ctx.stroke(shadow, with: .color(Clinical.ink.opacity(0.25)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

            let main = Clinical.accent.mix(with: Clinical.gold, by: Double(min(1, avg * 0.75)))
            ctx.stroke(path, with: .color(main),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

            let highlight = path.applying(CGAffineTransform(translationX: -1.1, y: 0))
            ctx.stroke(highlight, with: .color(Color.white.opacity(Double(0.12 + 0.55 * avg))),
                       style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))

            // Reward light blob sweeping down the lock.
            if let start = lock.rewardStart {
                let e = time - start
                if e >= 0 && e <= Self.rewardDuration {
                    let top = size.height * Self.yTop, bottom = size.height * Self.yBottom
                    let y = top + (bottom - top) * (e / Self.rewardDuration)
                    let x = size.width * lock.xFrac
                    let alpha = Double(1 - e / Self.rewardDuration) * 0.7
                    let blob = Path(ellipseIn: CGRect(x: x - 16, y: y - 16, width: 32, height: 32))
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 7))
                        layer.fill(blob, with: .color(Color.white.opacity(alpha)))
                    }
                }
            }
        }

        // Cream sparkles.
        for sp in sparkles {
            let a = Double(max(0, sp.life / sp.maxLife)) * 0.85
            let r: CGFloat = 1.6
            let dot = Path(ellipseIn: CGRect(x: sp.pos.x - r, y: sp.pos.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(Color.white.opacity(a)))
        }

        // Comb tool following the finger (teeth at the fingertip, rotated ≈ −14°).
        if dragging, let f = finger {
            let resolved = ctx.resolve(Image(BrandArt.combTool))
            let natural = resolved.size
            let w: CGFloat = 130
            let h = natural.width > 0 ? w * natural.height / natural.width : 90
            var tool = ctx
            tool.translateBy(x: f.x, y: f.y)
            tool.rotate(by: .degrees(-14))
            tool.draw(resolved, in: CGRect(x: -w / 2, y: -h + 6, width: w, height: h))
        }
    }

    // MARK: Helpers

    private mutating func build() {
        for i in 0..<Self.lockCount {
            let xFrac = Self.xLeft + (Self.xRight - Self.xLeft) * CGFloat(i) / CGFloat(Self.lockCount - 1)
            let freq = 0.45 + CGFloat.random(in: 0...1) * 0.25
            let phase = CGFloat.random(in: 0...(2 * .pi))
            var pts: [StrandPoint] = []
            for _ in 0..<Self.pointCount {
                pts.append(StrandPoint(a: 10 + CGFloat.random(in: 0...1) * 16, s: 0))
            }
            locks.append(Lock(xFrac: xFrac, freq: freq, phase: phase, points: pts,
                              rewardStart: nil, rewarded: false))
        }
        built = true
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

    private mutating func spawnSparkles(at f: CGPoint, dt: CGFloat) {
        sparkleAcc += dt * 30   // ~30 sparkles/sec while combing
        while sparkleAcc >= 1 {
            sparkleAcc -= 1
            let life = CGFloat.random(in: 0.5...1.1)
            sparkles.append(Sparkle(
                pos: CGPoint(x: f.x + CGFloat.random(in: -10...10), y: f.y + CGFloat.random(in: -6...6)),
                vel: CGPoint(x: CGFloat.random(in: -12...12), y: -CGFloat.random(in: 20...50)),
                life: life, maxLife: life))
        }
        if sparkleAcc > 4 { sparkleAcc = 4 }
    }
}
