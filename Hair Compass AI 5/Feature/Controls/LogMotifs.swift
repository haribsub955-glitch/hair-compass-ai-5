import SwiftUI

/// The six Canvas motif renderers behind the daily-log `LivingGauge`s. Each is a
/// `MotionTimeline { Canvas }` exactly like `FallingHairView` / `CountScrubber`'s motif layer;
/// `intensity` (0…1) drives everything, and Reduce Motion draws one static representative frame.
/// Ambient motifs are capped at 30 fps and pause when off-screen or inactive. Constants are
/// ported 1:1 from the design prototype's `draw*` functions (Daily Log — Living Inputs); colours
/// map onto `Clinical` tokens.

// MARK: - Shared deterministic randomness (same hash as CountScrubber & the prototype)

private func fract(_ x: CGFloat) -> CGFloat { x - x.rounded(.down) }

private func hash(_ i: Int, _ salt: CGFloat) -> CGFloat {
    fract(sin(CGFloat(i + 1) * 127.1 + salt * 311.7) * 43758.5453)
}

private func circlePath(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

/// Modulo keeps Double precision over long sessions (same trick as CountScrubber).
private func timelineSeconds(_ date: Date) -> CGFloat {
    CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
}

// MARK: - Flaking: fine flecks drifting down, bigger clumps as intensity rises

private struct Fleck {
    var x: CGFloat
    var y: CGFloat
    let vy: CGFloat
    let drift: CGFloat
    let phase: CGFloat
    let r: CGFloat
    let rot: CGFloat
    let light: Bool
}

/// Reference box so the per-frame step mutates in place without thrashing SwiftUI state —
/// same pattern as `HairSimBox` in HairPhysics.swift.
@MainActor private final class FleckSimBox {
    var flecks: [Fleck] = []
    var acc: CGFloat = 0
    var last: Date?
}

/// Prototype `drawFlake`: spawn `0.5 + i²·11` flecks/s (max 55), fall 7–16 pt/s scaled by
/// `(0.5 + i·0.9)`, sinusoidal drift, radius `1…1+i·2.4` (bigger = clumps), α `0.55·fade`.
struct FlakeMotif: View {
    var intensity: CGFloat
    @State private var box = FleckSimBox()

    var body: some View {
        MotionTimeline(cadence: .ambient) { timeline, reduceMotion in
            Canvas { ctx, size in
                if reduceMotion {
                    drawStatic(ctx, size: size)
                    return
                }
                let now = timeline.date
                let dt = box.last.map { min(CGFloat(now.timeIntervalSince($0)), 0.05) } ?? 0
                box.last = now
                let t = timelineSeconds(now)
                step(dt: dt, time: t, size: size)
                for fleck in box.flecks { draw(fleck, in: ctx, size: size, time: t) }
            }
        }
        .accessibilityHidden(true)
    }

    private func step(dt: CGFloat, time t: CGFloat, size: CGSize) {
        box.acc += dt * (0.5 + intensity * intensity * 11)
        while box.acc >= 1 {
            if box.flecks.count < 55 {
                box.flecks.append(Fleck(
                    x: CGFloat.random(in: 0...1) * size.width,
                    y: -6,
                    vy: 7 + CGFloat.random(in: 0...1) * 9,
                    drift: (CGFloat.random(in: 0...1) - 0.5) * 12,
                    phase: CGFloat.random(in: 0...1) * 6.28,
                    r: 1 + CGFloat.random(in: 0...1) * (1 + intensity * 2.4),
                    rot: CGFloat.random(in: 0...1) * 6.28,
                    light: CGFloat.random(in: 0...1) < 0.6))
            }
            box.acc -= 1
        }
        if box.acc > 4 { box.acc = 4 }
        for i in box.flecks.indices {
            box.flecks[i].y += box.flecks[i].vy * dt * (0.5 + intensity * 0.9)
            box.flecks[i].x += sin(t * 1.5 + box.flecks[i].phase) * box.flecks[i].drift * dt
        }
        box.flecks.removeAll { $0.y - $0.r > size.height + 8 }
    }

    private func draw(_ f: Fleck, in ctx: GraphicsContext, size: CGSize, time t: CGFloat) {
        let fade = f.y > size.height - 36 ? max(0, (size.height - f.y) / 36) : 1
        // Prototype palette #EFE6D6 / #A69687 → nearest tokens hairline / tertiary.
        let color = (f.light ? Clinical.hairline : Clinical.tertiary).opacity(0.55 * fade)
        var c = ctx
        c.translateBy(x: f.x, y: f.y)
        c.rotate(by: .radians(Double(f.rot + t * 0.5)))
        c.fill(Path(ellipseIn: CGRect(x: -f.r, y: -f.r * 0.7, width: f.r * 2, height: f.r * 1.4)),
               with: .color(color))
    }

    /// Reduce Motion: a settled scatter of flecks at hash-fixed positions.
    private func drawStatic(_ ctx: GraphicsContext, size: CGSize) {
        let n = Int(3 + intensity * 30)
        for k in 0..<n {
            let fleck = Fleck(
                x: hash(k, 11) * size.width,
                y: hash(k, 12) * size.height,
                vy: 0, drift: 0, phase: 0,
                r: 1 + hash(k, 13) * (1 + intensity * 2.4),
                rot: hash(k, 15) * 6.28,
                light: hash(k, 14) < 0.6)
            draw(fleck, in: ctx, size: size, time: 0)
        }
    }
}

// MARK: - Redness: a field wash — the whole panel flushes, two breathing blooms

/// Prototype `drawRed`: base wash `critical` at α `i·pulse·0.22` where
/// `pulse = 0.92 + 0.08·sin(t·1.8)`, plus two radial blooms (0.34w/0.56h ×0.55 and
/// 0.72w/0.40h ×0.42) breathing by `0.9 + 0.1·sin(t·1.4 + phase)` at α `i·pulse·0.85 → 0`.
/// Bloom hex #B44A34 has no token → `Clinical.critical`. Zero intensity draws nothing: calm.
struct RednessMotif: View {
    var intensity: CGFloat

    var body: some View {
        MotionTimeline(cadence: .ambient, paused: intensity <= 0.001) { timeline, reduceMotion in
            Canvas { ctx, size in
                guard intensity > 0.001 else { return }
                let t: CGFloat = reduceMotion ? 0 : timelineSeconds(timeline.date)
                let pulse = 0.92 + 0.08 * sin(t * 1.8)
                let a = intensity * pulse
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Clinical.critical.opacity(a * 0.22)))
                let blooms: [(CGFloat, CGFloat, CGFloat, CGFloat)] =
                    [(0.34, 0.56, 0.55, 0), (0.72, 0.40, 0.42, 2.1)]
                for (fx, fy, rf, ph) in blooms {
                    let cx = size.width * fx
                    let cy = size.height * fy
                    let rad = max(size.width, size.height) * rf * (0.9 + 0.1 * sin(t * 1.4 + ph))
                    ctx.fill(circlePath(cx, cy, rad),
                             with: .radialGradient(
                                Gradient(colors: [Clinical.critical.opacity(a * 0.85),
                                                  Clinical.critical.opacity(0)]),
                                center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: rad))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Itch: prickle ripples — expanding rings at random points, more frequent with i

private struct ItchRipple {
    let x: CGFloat
    let y: CGFloat
    var age: CGFloat
}

@MainActor private final class ItchSimBox {
    var ripples: [ItchRipple] = []
    var acc: CGFloat = 0
    var last: Date?
}

/// Prototype `drawItch`: spawn rate `0.25 + i²·6` rings/s (max 34 live); each ring grows
/// r 3→20 and fades over 0.72 s at α `(1-p)·(0.12 + i·0.4)`, stroke `Clinical.warning` 1.4pt,
/// with a small centre prick at α ×1.3.
struct ItchMotif: View {
    var intensity: CGFloat
    @State private var box = ItchSimBox()

    var body: some View {
        MotionTimeline(cadence: .ambient) { timeline, reduceMotion in
            Canvas { ctx, size in
                if reduceMotion {
                    drawStatic(ctx, size: size)
                    return
                }
                let now = timeline.date
                let dt = box.last.map { min(CGFloat(now.timeIntervalSince($0)), 0.05) } ?? 0
                box.last = now
                step(dt: dt, size: size)
                for ripple in box.ripples {
                    drawRipple(ctx, x: ripple.x, y: ripple.y, progress: ripple.age / 0.72)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func step(dt: CGFloat, size: CGSize) {
        box.acc += dt * (0.25 + intensity * intensity * 6)
        while box.acc >= 1 {
            box.ripples.append(ItchRipple(
                x: 18 + CGFloat.random(in: 0...1) * max(1, size.width - 36),
                y: 18 + CGFloat.random(in: 0...1) * max(1, size.height - 36),
                age: 0))
            box.acc -= 1
            if box.ripples.count > 34 { box.ripples.removeFirst() }
        }
        if box.acc > 3 { box.acc = 3 }
        for i in box.ripples.indices { box.ripples[i].age += dt }
        box.ripples.removeAll { $0.age >= 0.72 }
    }

    private func drawRipple(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, progress p: CGFloat) {
        let rad = 3 + p * 17
        let al = (1 - p) * (0.12 + intensity * 0.4)
        ctx.stroke(circlePath(x, y, rad), with: .color(Clinical.warning.opacity(al)),
                   style: StrokeStyle(lineWidth: 1.4))
        ctx.fill(circlePath(x, y, 1.3), with: .color(Clinical.warning.opacity(min(1, al * 1.3))))
    }

    /// Reduce Motion: a few frozen ripples at hash-fixed positions and progress.
    private func drawStatic(_ ctx: GraphicsContext, size: CGSize) {
        let n = 1 + Int(intensity * 4)
        for k in 0..<n {
            drawRipple(ctx,
                       x: 18 + hash(k, 21) * max(1, size.width - 36),
                       y: 18 + hash(k, 22) * max(1, size.height - 36),
                       progress: 0.15 + hash(k, 23) * 0.6)
        }
    }
}

// MARK: - Oiliness: gloss sheen — gold wash, sweeping specular band, soft gloss blobs

/// Prototype `drawOil`: base gold wash α `i·0.16`; a specular band centred at
/// `w·(0.5 + 0.42·sin(t·0.55))`, half-width `0.4w`, peak α `0.1 + i·0.5`; two gloss blobs
/// (0.3w/0.6h and 0.72w/0.34h) of radius `10 + i·26` swaying by `sin(t·0.7 + phase)·6` at
/// α `0.14 + i·0.4`. Highlight hexes #FCF3DF/#FFFDF6 → nearest token `Clinical.surface`.
struct OilMotif: View {
    var intensity: CGFloat

    var body: some View {
        MotionTimeline(cadence: .ambient, paused: intensity <= 0.001) { timeline, reduceMotion in
            Canvas { ctx, size in
                guard intensity > 0.001 else { return }
                let t: CGFloat = reduceMotion ? 0 : timelineSeconds(timeline.date)
                let full = Path(CGRect(origin: .zero, size: size))
                ctx.fill(full, with: .color(Clinical.gold.opacity(intensity * 0.16)))

                let cx = size.width * (0.5 + 0.42 * sin(t * 0.55))
                let bw = size.width * 0.4
                let stops = [
                    Gradient.Stop(color: Clinical.surface.opacity(0), location: 0),
                    Gradient.Stop(color: Clinical.surface.opacity(0.1 + intensity * 0.5), location: 0.5),
                    Gradient.Stop(color: Clinical.surface.opacity(0), location: 1),
                ]
                ctx.fill(full, with: .linearGradient(
                    Gradient(stops: stops),
                    startPoint: CGPoint(x: cx - bw, y: 0),
                    endPoint: CGPoint(x: cx + bw, y: size.height)))

                let blobs: [(CGFloat, CGFloat, CGFloat)] = [(0.3, 0.6, 0), (0.72, 0.34, 3)]
                for (fx, fy, ph) in blobs {
                    let rr = 10 + intensity * 26
                    let gx = size.width * fx + sin(t * 0.7 + ph) * 6
                    let gy = size.height * fy
                    ctx.fill(circlePath(gx, gy, rr),
                             with: .radialGradient(
                                Gradient(colors: [Clinical.surface.opacity(0.14 + intensity * 0.4),
                                                  Clinical.surface.opacity(0)]),
                                center: CGPoint(x: gx, y: gy), startRadius: 0, endRadius: rr))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sleep quality: night calm — a wave that settles, gold stars, a growing moon

/// Prototype `drawSleep`: breathing sine wave that gets *calmer* as quality rises
/// (`freq = 0.03 + (1-q)·0.10`, `speed = 0.6 + (1-q)·1.9`, `amp = 5 + (1-q)·11`, envelope
/// `0.65 + 0.35·sin(t·0.5)`), `floor(q·7)` twinkling stars, and a crescent moon of radius
/// `8 + q·9`. Wave `Clinical.ink` @ 0.5; stars `Clinical.gold`; moon `Clinical.sage` @ 0.42
/// cut out with the panel colour (`Clinical.surface`).
struct SleepMotif: View {
    var intensity: CGFloat

    var body: some View {
        MotionTimeline(cadence: .ambient) { timeline, reduceMotion in
            Canvas { ctx, size in
                let t: CGFloat = reduceMotion ? 0 : timelineSeconds(timeline.date)
                let q = intensity
                let mid = size.height * 0.62

                // Crescent moon — grows with quality.
                let mr = 8 + q * 9
                let mx = size.width - 26
                let my: CGFloat = 22
                ctx.fill(circlePath(mx, my, mr), with: .color(Clinical.sage.opacity(0.42)))
                ctx.fill(circlePath(mx + mr * 0.5, my - mr * 0.3, mr), with: .color(Clinical.surface))

                // Twinkling stars.
                let n = Int(q * 7)
                for k in 0..<n {
                    let sx = 10 + hash(k, 1) * (size.width - 40)
                    let sy = 8 + hash(k, 2) * (size.height * 0.42)
                    let tw = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 1.4 + hash(k, 3) * 6.28))
                    ctx.fill(circlePath(sx, sy, 1.1), with: .color(Clinical.gold.opacity(0.55 * tw)))
                }

                // Breathing wave — calmer as quality rises.
                let freq = 0.03 + (1 - q) * 0.10
                let speed = 0.6 + (1 - q) * 1.9
                let amp = 5 + (1 - q) * 11
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    let y = mid + sin(x * freq + t * speed) * amp * (0.65 + 0.35 * sin(t * 0.5))
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    x += 3
                }
                ctx.stroke(path, with: .color(Clinical.ink.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Stress: seismograph — flat and calm at low, jagged and hot at high

/// Prototype `drawStress`: scrolling readout line with `amp = 3 + s²·30`,
/// `freq = 0.05 + s·0.14`, scroll speed `t·(2 + s·6)`, hash-noise jitter `s²` re-seeded at
/// `floor(t·(2 + s·12))`; colour lerps `Clinical.ink → Clinical.critical` with `s`; a scan
/// dot sits at the right edge.
struct StressMotif: View {
    var intensity: CGFloat

    var body: some View {
        MotionTimeline(cadence: .ambient) { timeline, reduceMotion in
            Canvas { ctx, size in
                let t: CGFloat = reduceMotion ? 0 : timelineSeconds(timeline.date)
                let s = intensity
                let mid = size.height * 0.5
                let col = Clinical.ink.mix(with: Clinical.critical, by: Double(s))
                let amp = 3 + s * s * 30
                let freq = 0.05 + s * 0.14
                let jit = s * s

                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    let base = sin(x * freq + t * (2 + s * 6))
                    let noise = (hash(Int(x / 3), (t * (2 + s * 12)).rounded(.down)) - 0.5) * 2 * jit
                    let y = mid + base * amp * 0.5 + noise * amp
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    x += 3
                }
                ctx.stroke(path, with: .color(col),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ctx.fill(circlePath(size.width - 4, mid, 2.6), with: .color(col))
            }
        }
        .accessibilityHidden(true)
    }
}
