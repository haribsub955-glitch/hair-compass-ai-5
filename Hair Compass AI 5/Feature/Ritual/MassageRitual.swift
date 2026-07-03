import SwiftUI

/// Scalp massage (`massage`) — spec §3.2. Rubbing below the top 30% of the screen builds foam
/// bubbles at the finger; each bubble grows, drifts up, and pops (end of life, or when the finger
/// brushes an older one) into an expanding white ring — the satisfying beat. A thin copper progress
/// ring at bottom center fills with drag distance; full ring completes. Uses the plain fade finish.
struct MassageRitual: Ritual {
    let kind: RitualKind = .massage
    let title = "Massage in circles"
    let hint = "Rub gently — the lather builds as you go."

    // MARK: Tuning (spec §3.2)
    private static let speedGate: CGFloat = 1.5      // pt/frame to count as rubbing
    private static let topExclusion: CGFloat = 0.30  // no bubbles in the top 30%
    private static let reach: CGFloat = 58           // (unused for combing; kept for touch pops)
    private static let progressRate: CGFloat = 0.00028
    private static let popRingDuration: CGFloat = 0.38
    private static let touchPopAge: CGFloat = 0.35

    private struct Bubble {
        var pos: CGPoint
        var r: CGFloat
        var maxR: CGFloat
        var vel: CGPoint
        var age: CGFloat
        var life: CGFloat
        var maxLife: CGFloat
    }
    private struct PopRing { var pos: CGPoint; var r0: CGFloat; var elapsed: CGFloat }

    private var bubbles: [Bubble] = []
    private var rings: [PopRing] = []
    private var progress: CGFloat = 0
    private var finger: CGPoint?
    private var active = false
    private var prevStepFinger: CGPoint?
    private var time: CGFloat = 0

    // MARK: Ritual

    var isComplete: Bool { progress >= 1 }

    mutating func handle(_ touch: RitualTouch) {
        switch touch.phase {
        case .began, .moved:
            active = true
            finger = touch.location
        case .ended:
            active = false
        }
    }

    @discardableResult
    mutating func step(dt: CGFloat, size: CGSize) -> Int {
        guard size != .zero else { return 0 }
        time += dt
        var beats = 0

        // Rubbing: per-frame drag speed (pt/frame), gated below the top 30%.
        if active, let f = finger {
            let dragSpeed: CGFloat
            if let prev = prevStepFinger {
                let dx = f.x - prev.x, dy = f.y - prev.y
                dragSpeed = (dx * dx + dy * dy).squareRoot()
            } else {
                dragSpeed = 0
            }
            prevStepFinger = f

            if dragSpeed > Self.speedGate && f.y > size.height * Self.topExclusion {
                progress = min(1, progress + dragSpeed * Self.progressRate)
                // Spawn chance ∝ speed, capped 0.8/frame.
                let chance = min(0.8, dragSpeed * 0.06)
                if CGFloat.random(in: 0...1) < chance {
                    let life = CGFloat.random(in: 1.8...3.4)
                    bubbles.append(Bubble(
                        pos: CGPoint(x: f.x + CGFloat.random(in: -6...6), y: f.y + CGFloat.random(in: -6...6)),
                        r: CGFloat.random(in: 2...5),
                        maxR: CGFloat.random(in: 7...22),
                        vel: CGPoint(x: CGFloat.random(in: -5...5), y: -CGFloat.random(in: 12...28)),
                        age: 0, life: life, maxLife: life))
                }
            }
        } else {
            prevStepFinger = nil
        }

        // Grow + drift bubbles.
        for i in bubbles.indices {
            bubbles[i].r += (bubbles[i].maxR - bubbles[i].r) * 0.04   // per-frame growth
            bubbles[i].pos.x += bubbles[i].vel.x * dt                 // slow upward drift
            bubbles[i].pos.y += bubbles[i].vel.y * dt
            bubbles[i].age += dt
            bubbles[i].life -= dt
        }

        // Pops: end of life, or finger touches a bubble older than 0.35s.
        var survivors: [Bubble] = []
        for b in bubbles {
            var popped = b.life <= 0
            if !popped, active, let f = finger, b.age > Self.touchPopAge {
                let dx = b.pos.x - f.x, dy = b.pos.y - f.y
                if (dx * dx + dy * dy).squareRoot() < b.r + 8 { popped = true }
            }
            if popped {
                rings.append(PopRing(pos: b.pos, r0: b.r, elapsed: 0))
                beats += 1
            } else {
                survivors.append(b)
            }
        }
        bubbles = survivors

        // Advance pop rings.
        for i in rings.indices { rings[i].elapsed += dt }
        rings.removeAll { $0.elapsed > Self.popRingDuration }

        return beats
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        // Foam bubbles: cream fill, white rim, small white highlight dot.
        for b in bubbles {
            let fade = Double(min(1, b.life / 0.4))
            let circle = Path(ellipseIn: CGRect(x: b.pos.x - b.r, y: b.pos.y - b.r, width: b.r * 2, height: b.r * 2))
            ctx.fill(circle, with: .color(Clinical.canvas.opacity(0.35 * fade)))          // cream fill 35%
            ctx.stroke(circle, with: .color(Color.white.opacity(0.85 * fade)),            // white rim 1.6@85%
                       style: StrokeStyle(lineWidth: 1.6))
            let hr = max(1, b.r * 0.22)
            let hx = b.pos.x - b.r * 0.35, hy = b.pos.y - b.r * 0.35
            let dot = Path(ellipseIn: CGRect(x: hx - hr, y: hy - hr, width: hr * 2, height: hr * 2))
            ctx.fill(dot, with: .color(Color.white.opacity(0.8 * fade)))                  // highlight dot
        }

        // Pop rings: expand r → r+14 over 0.38s, fading.
        for ring in rings {
            let t = ring.elapsed / Self.popRingDuration
            let radius = ring.r0 + 14 * t
            let alpha = Double(1 - t) * 0.9
            let rect = CGRect(x: ring.pos.x - radius, y: ring.pos.y - radius, width: radius * 2, height: radius * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)),
                       style: StrokeStyle(lineWidth: 1.6))
        }

        // Progress: thin copper ring (r 24) at bottom center that fills with progress.
        let center = CGPoint(x: size.width / 2, y: size.height - 70)
        let ringR: CGFloat = 24
        let track = Path(ellipseIn: CGRect(x: center.x - ringR, y: center.y - ringR, width: ringR * 2, height: ringR * 2))
        ctx.stroke(track, with: .color(Clinical.accent.opacity(0.18)), style: StrokeStyle(lineWidth: 3))
        if progress > 0 {
            var arc = Path()
            arc.addArc(center: center, radius: ringR,
                       startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(min(1, progress))),
                       clockwise: false)
            ctx.stroke(arc, with: .color(Clinical.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
