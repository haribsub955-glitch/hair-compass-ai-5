import SwiftUI

/// Scalp massage (`massage`) — auto "settle pulse" (design doc 2026-07-11 §1). Three concentric
/// copper rings pulse outward from center on their own, ~0.33s apart, each fading as it expands;
/// a faint radial glow sits behind them and a soft field of scalp dots nudges outward as each
/// pulse passes. Complete on its own in ~1.05s. A touch spawns a bonus ripple at the touch point.
struct MassageRitual: Ritual {
    let kind: RitualKind = .massage
    let title = "Breathe"
    let hint = "A moment, then we begin."

    // MARK: Tuning
    private static let cadence: CGFloat = 0.33        // spawn gap between the 3 center pulses
    private static let pulseDuration: CGFloat = 0.6    // time for a pulse to expand from 0 → maxR
    private static let totalDuration: CGFloat = 1.05   // isComplete gate
    private static let dotCount = 64
    private static let dotMaxRadiusFrac: CGFloat = 0.42  // matches the pulses' own max-radius fraction
    private static let dotFalloff: CGFloat = 26          // how close a pulse ring must be to nudge a dot
    private static let dotNudge: CGFloat = 5             // max outward displacement at the ring itself
    private static let rippleMaxR: CGFloat = 46
    private static let ripplePulseDuration: CGFloat = 0.4
    private static let rippleThrottle: CGFloat = 0.09    // min gap between touch-spawned ripples
    private static let seedRingFloor: CGFloat = 8         // keeps the t==0 ring visible before it grows
    private static let goldenAngle: CGFloat = 2.399963229728653   // phyllotaxis spread for the dot field

    private struct Pulse { var start: CGFloat; var r: CGFloat }
    private struct Ripple { var pos: CGPoint; var start: CGFloat; var r: CGFloat }
    private struct Dot { var angle: CGFloat; var radiusFrac: CGFloat }

    // The first pulse exists from construction (not spawned lazily in `step`), so `draw` has
    // something to render for the Reduce Motion static frame at time == 0 — `draw` is non-mutating
    // and that path never calls `step`. `step`'s first tick still reports its "beat".
    private var pulses: [Pulse] = [Pulse(start: 0, r: 0)]
    private var spawnedCount = 0
    private var time: CGFloat = 0
    private var ripples: [Ripple] = []
    private var lastRippleSpawn: CGFloat = -1
    private let dots: [Dot] = MassageRitual.makeDots()

    // MARK: Ritual

    var isComplete: Bool { time >= Self.totalDuration }

    mutating func handle(_ touch: RitualTouch) {
        switch touch.phase {
        case .began, .moved:
            guard time - lastRippleSpawn > Self.rippleThrottle else { return }
            lastRippleSpawn = time
            ripples.append(Ripple(pos: touch.location, start: time, r: 0))
        case .ended:
            break
        }
    }

    @discardableResult
    mutating func step(dt: CGFloat, size: CGSize) -> Int {
        guard size != .zero else { return 0 }
        time += dt
        var beats = 0

        // Spawn the 3 center pulses at time ≈ 0, 0.33, 0.66 — one beat each.
        if spawnedCount == 0 {
            spawnedCount = 1
            beats += 1
        }
        if spawnedCount == 1 && time >= Self.cadence {
            pulses.append(Pulse(start: Self.cadence, r: 0))
            spawnedCount = 2
            beats += 1
        }
        if spawnedCount == 2 && time >= Self.cadence * 2 {
            pulses.append(Pulse(start: Self.cadence * 2, r: 0))
            spawnedCount = 3
            beats += 1
        }

        let maxR = min(size.width, size.height) * Self.dotMaxRadiusFrac
        for i in pulses.indices {
            let t = min(1, max(0, (time - pulses[i].start) / Self.pulseDuration))
            pulses[i].r = maxR * Self.easeOut(t)
        }
        pulses.removeAll { time - $0.start > Self.pulseDuration }

        for i in ripples.indices {
            let t = min(1, max(0, (time - ripples[i].start) / Self.ripplePulseDuration))
            ripples[i].r = Self.rippleMaxR * Self.easeOut(t)
        }
        ripples.removeAll { time - $0.start > Self.ripplePulseDuration }

        return beats
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = min(size.width, size.height) * Self.dotMaxRadiusFrac

        // Faint radial glow behind everything.
        let glowR = maxR * 1.15
        let glow = Path(ellipseIn: CGRect(x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2))
        ctx.fill(glow, with: .radialGradient(
            Gradient(colors: [Clinical.accent.opacity(0.16), Clinical.accent.opacity(0)]),
            center: center, startRadius: 0, endRadius: glowR))

        // Scalp dot field — each dot nudges outward when a pulse ring is near its resting radius.
        for dot in dots {
            let baseR = dot.radiusFrac * maxR
            var nudge: CGFloat = 0
            for p in pulses {
                let ringR = max(p.r, Self.seedRingFloor)
                let d = abs(baseR - ringR)
                if d < Self.dotFalloff {
                    nudge = max(nudge, (1 - d / Self.dotFalloff) * Self.dotNudge)
                }
            }
            let r = baseR + nudge
            let pos = CGPoint(x: center.x + cos(dot.angle) * r, y: center.y + sin(dot.angle) * r)
            let dotR: CGFloat = 1.4
            let alpha = 0.24 + 0.34 * Double(min(1, nudge / Self.dotNudge))
            ctx.fill(Path(ellipseIn: CGRect(x: pos.x - dotR, y: pos.y - dotR, width: dotR * 2, height: dotR * 2)),
                     with: .color(Clinical.tertiary.opacity(alpha)))
        }

        // Concentric copper→gold pulses, fading as they expand.
        for p in pulses {
            let r = max(p.r, Self.seedRingFloor)
            let t = min(1, r / maxR)
            let alpha = Double(1 - t) * 0.75
            guard alpha > 0.01 else { continue }
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let color = Clinical.accent.mix(with: Clinical.gold, by: Double(t) * 0.5)
            ctx.stroke(Path(ellipseIn: rect), with: .color(color.opacity(alpha)),
                       style: StrokeStyle(lineWidth: 2.5 - t * 1.2, lineCap: .round))
        }

        // Bonus touch ripples.
        for ripple in ripples {
            let t = min(1, ripple.r / Self.rippleMaxR)
            let alpha = Double(1 - t) * 0.6
            guard alpha > 0.01 else { continue }
            let rect = CGRect(x: ripple.pos.x - ripple.r, y: ripple.pos.y - ripple.r, width: ripple.r * 2, height: ripple.r * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)), style: StrokeStyle(lineWidth: 1.4))
        }
    }

    // MARK: Helpers

    private static func easeOut(_ t: CGFloat) -> CGFloat { 1 - (1 - t) * (1 - t) }

    /// A phyllotaxis (golden-angle) spread — an even, non-clumpy scattering of dots without
    /// needing randomness, so the field is identical across ritual instances.
    private static func makeDots() -> [Dot] {
        var out: [Dot] = []
        out.reserveCapacity(dotCount)
        for i in 0..<dotCount {
            let angle = CGFloat(i) * goldenAngle
            let radiusFrac = (CGFloat(i) / CGFloat(dotCount)).squareRoot() * dotMaxRadiusFrac
            out.append(Dot(angle: angle, radiusFrac: radiusFrac))
        }
        return out
    }
}
