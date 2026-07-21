import SwiftUI

/// Loosen the knot (`knot`) — spec §3.4. A tangled closed loop of 90 points that relaxes into a
/// glossy coil as you trace circles over it; it slowly idle-rotates and wobbles until relaxed, shifts
/// copper→gold with progress, and gets a light blob that laps the coil once. Complete at avg s > 0.94.
struct KnotRitual: Ritual {
    let kind: RitualKind = .knot
    let title = "Loosen the knot"
    let hint = "Trace circles over it until it relaxes."

    // MARK: Tuning (spec §3.4)
    private static let pointCount = 90
    private static let center = CGPoint(x: 0.5, y: 0.58)   // fractional
    private static let baseRadius: CGFloat = 92
    private static let reach: CGFloat = 62
    private static let completeThreshold: CGFloat = 0.94
    private static let rewardThreshold: CGFloat = 0.985
    private static let rewardDuration: CGFloat = 0.8
    private static let turnSeconds: CGFloat = 75          // full idle rotation

    private struct KnotPoint { var n: CGFloat; var jitter: CGFloat; var s: CGFloat }

    private var points: [KnotPoint] = []
    private var built = false
    private var time: CGFloat = 0
    private var rotation: CGFloat = 0
    private var finger: CGPoint?
    private var dragging = false
    private var rewardStart: CGFloat?
    private var rewarded = false

    // MARK: Ritual

    var isComplete: Bool { !points.isEmpty && avgS > Self.completeThreshold }
    var progress: CGFloat { min(1, avgS / Self.completeThreshold) }
    var estimatedDuration: TimeInterval? { nil }   // interaction-paced — no fixed end time

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
        rotation += (2 * CGFloat.pi / Self.turnSeconds) * dt
        var beats = 0
        let before = avgS

        // Tracing: any point within reach of the finger relaxes this frame.
        if dragging, let f = finger {
            for i in points.indices {
                let pos = pointPosition(i, size: size)
                let dx = pos.x - f.x, dy = pos.y - f.y
                let d = (dx * dx + dy * dy).squareRoot()
                if d < Self.reach {
                    let gain = 0.09 * (1 - d / Self.reach) + 0.015
                    points[i].s = min(1, points[i].s + gain)
                }
            }
        }

        let prog = avgS
        // Light haptic each time we cross a coarse relaxation milestone.
        if Int(prog * 10) > Int(before * 10) { beats += 1 }
        // Reward blob once the coil is essentially fully relaxed.
        if prog > Self.rewardThreshold && !rewarded {
            rewarded = true
            rewardStart = time
            beats += 1
        }
        return beats
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        guard built else { return }
        let path = loopPath(size: size)
        let prog = Double(min(1, avgS))

        // Same 3-stroke render as combing (widths 6/4/1.4), colour shifting to gold with progress.
        let shadow = path.applying(CGAffineTransform(translationX: 1.6, y: 0))
        ctx.stroke(shadow, with: .color(Clinical.ink.opacity(0.25)),
                   style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

        let main = Clinical.accent.mix(with: Clinical.gold, by: prog)
        ctx.stroke(path, with: .color(main),
                   style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        let highlight = path.applying(CGAffineTransform(translationX: -1.1, y: 0))
        ctx.stroke(highlight, with: .color(Color.white.opacity(0.12 + 0.55 * prog)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

        // Reward light blob laps the coil once.
        if let start = rewardStart {
            let e = time - start
            if e >= 0 && e <= Self.rewardDuration {
                let frac = e / Self.rewardDuration
                let idx = min(points.count - 1, Int(frac * CGFloat(points.count)))
                let pos = pointPosition(idx, size: size)
                let blob = Path(ellipseIn: CGRect(x: pos.x - 16, y: pos.y - 16, width: 32, height: 32))
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 7))
                    layer.fill(blob, with: .color(Color.white.opacity(0.7)))
                }
            }
        }
    }

    // MARK: Helpers

    private mutating func build() {
        for _ in 0..<Self.pointCount {
            let sign: CGFloat = Bool.random() ? 1 : -1
            let n = sign * (26 + CGFloat.random(in: 0...1) * 26)
            let jitter = CGFloat.random(in: -0.35...0.35)
            points.append(KnotPoint(n: n, jitter: jitter, s: 0))
        }
        built = true
    }

    private func pointPosition(_ i: Int, size: CGSize) -> CGPoint {
        let p = points[i]
        let center = CGPoint(x: size.width * Self.center.x, y: size.height * Self.center.y)
        let baseAngle = 2 * CGFloat.pi * CGFloat(i) / CGFloat(points.count) + rotation
        let angle = baseAngle + p.jitter * (1 - p.s)
        // Wobble that dies as the point relaxes.
        let wobble = sin(time * 1.7 + CGFloat(i) * 0.4) * 4 * (1 - p.s)
        let radius = Self.baseRadius + p.n * (1 - p.s) + wobble
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func loopPath(size: CGSize) -> Path {
        var path = Path()
        let pts = (0..<points.count).map { pointPosition($0, size: size) }
        guard let first = pts.first else { return path }
        path.move(to: first)
        for k in 0..<pts.count {
            let cur = pts[k]
            let next = pts[(k + 1) % pts.count]
            let mid = CGPoint(x: (cur.x + next.x) / 2, y: (cur.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: cur)
        }
        path.closeSubpath()
        return path
    }

    private var avgS: CGFloat {
        guard !points.isEmpty else { return 0 }
        var total: CGFloat = 0
        for p in points { total += p.s }
        return total / CGFloat(points.count)
    }
}
