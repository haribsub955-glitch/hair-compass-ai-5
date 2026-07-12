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
    // Low/mid intensity raised (UX audit #7 — onboarding step 5 opens at the default
    // intensity 0.34 and previously read as empty/broken). Blending a sqrt term into the
    // original quadratic curve keeps both endpoints exactly pinned — i=0 stays ~1.1
    // strands/sec (still sparse for "Minimal"), i=1 stays exactly 23.1 (top end unchanged,
    // per spec) — while lifting the low/mid range substantially: i=0.34 goes from ~3.6 to
    // ~11.8 strands/sec. Verified with a python3 replay of the spawn/fall/removal loop across
    // small-to-large device heights (500–850pt): concurrent strands alive at i=0.34 land
    // between ~15.7 and ~21.2 (was ~4.9–6.6), comfortably past the "~15+" target, and
    // concurrent count at i=1 is numerically identical to the original curve.
    static func spawnRate(_ i: CGFloat) -> CGFloat { 1.1 + (0.6 * i.squareRoot() + 0.4 * i) * 22 }   // strands/sec
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
    var staticBand = -1
    var staticSize: CGSize = .zero
}

struct FallingHairView: View {
    var intensity: CGFloat
    @State private var box = HairSimBox()

    private static let palette: [Color] = [Clinical.accent, Clinical.ink, Clinical.secondary, Clinical.sage, Clinical.gold]

    var body: some View {
        MotionTimeline(cadence: .interactive) { timeline, reduceMotion in
            Canvas { ctx, size in
                box.sim.size = size
                if reduceMotion {
                    drawStatic(ctx, size: size)
                } else {
                    let now = timeline.date
                    let dt = box.last.map { min(CGFloat(now.timeIntervalSince($0)), 0.05) } ?? 0
                    box.last = now
                    // Keep the trigonometry input small during long sessions; visually identical,
                    // but avoids doing sine reduction on an ever-growing reference-date value.
                    let time = CGFloat(
                        now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                    )
                    box.sim.step(dt: dt, time: time, intensity: intensity)
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
        let band = min(3, max(0, Int((intensity * 3).rounded())))
        if box.staticStrands.isEmpty || box.staticBand != band || box.staticSize != size {
            box.staticStrands.removeAll(keepingCapacity: true)
            box.staticBand = band
            box.staticSize = size
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

// MARK: - Semantic shedding scene

/// A small, testable description of how the categorical shedding answer becomes a visual scene.
/// The log never pretends to count individual hairs: the stored value remains the four-band
/// self-report, while density, speed and the resting collection make the *difference between
/// bands* immediately legible.
struct SheddingSceneProfile: Equatable {
    let band: Int
    let displayIntensity: CGFloat
    let restingStrandCount: Int
    let clusterCount: Int
    let washOpacity: Double

    static func make(intensity: CGFloat) -> SheddingSceneProfile {
        let clamped = min(1, max(0, intensity))
        let band = min(3, max(0, Int((clamped * 3).rounded())))
        return SheddingSceneProfile(
            band: band,
            // Keep a single occasional strand alive at minimal without flattening the strong
            // density difference between minimal and heavy.
            displayIntensity: 0.08 + clamped * 0.92,
            restingStrandCount: [1, 4, 9, 16][band],
            // Elevated and heavy self-reports often feel clustered rather than merely faster.
            // These are illustrative events, never a claimed measurement.
            clusterCount: [0, 0, 1, 2][band],
            washOpacity: [0.025, 0.04, 0.065, 0.095][band]
        )
    }
}

struct SheddingReflection: Equatable {
    let title: String
    let detail: String

    static func make(band: Int) -> SheddingReflection {
        let clamped = min(3, max(0, band))
        return [
            SheddingReflection(
                title: "Quiet today",
                detail: "Occasional strands; a light moment in the pattern."
            ),
            SheddingReflection(
                title: "Steady turnover",
                detail: "A familiar daily rhythm."
            ),
            SheddingReflection(
                title: "More active",
                detail: "Above your usual pattern—worth tracking over time."
            ),
            SheddingReflection(
                title: "A heavier day",
                detail: "Frequent strands or clusters. One day is context, not a conclusion."
            ),
        ][clamped]
    }
}

/// The shared emotional portrait used while logging and after a log is saved on Today. Falling
/// strands communicate frequency; the quiet collection at the lower edge communicates what that
/// frequency can feel like over a day. Higher levels become denser and warmer, never faster by
/// arbitrary decorative motion alone. Reduce Motion keeps the same information in a static frame.
struct SheddingStatusScene: View {
    var intensity: CGFloat
    var showsCollection = true
    /// When true and nothing has been logged (`showsCollection == false`), seeds a faint, fixed
    /// resting arrangement so the scene reads as an intentional canvas rather than empty space
    /// while a new user decides what to log — never a real reading (it ignores `intensity`
    /// entirely and stays well below Minimal's own opacity), just enough density that the void
    /// between the greeting and the headline doesn't read as a rendering artifact. Ignored once
    /// `showsCollection` is true.
    var ambientWhenEmpty = false

    private var profile: SheddingSceneProfile { .make(intensity: intensity) }
    private static let ambientProfile = SheddingSceneProfile(
        band: 0, displayIntensity: 0.08, restingStrandCount: 3, clusterCount: 0, washOpacity: 0.018
    )

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Clinical.sage.opacity(profile.band == 0 ? 0.045 : 0.015),
                    Clinical.accent.opacity(profile.washOpacity),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Suppressed only in the true "nothing logged, no finger down" rest state (round-3
            // fix): at rest the low-intensity live sim still spawned and fell continuously,
            // producing stray strand fragments that could cross the eyebrow/headline text or
            // read as disconnected squiggles behind the drag ladder — with nothing logged there
            // is no reading for them to represent. The moment a real value exists — logged
            // (`showsCollection`) or a live drag — the simulation resumes exactly as before, and
            // `ambientWhenEmpty == false` call sites (e.g. `ShedDialField`) are unaffected.
            if showsCollection || !ambientWhenEmpty {
                FallingHairView(intensity: profile.displayIntensity)
            }

            // A quiet resting anchor for the scene's lower edge, present at every band —
            // including "not logged" and Minimal, where the falling simulation and resting
            // collection are both nearly invisible. Keeps the hero reading as a composed scene
            // rather than empty canvas when there is little else to draw.
            SceneGroundline()

            if profile.clusterCount > 0 {
                SheddingClusterLayer(profile: profile)
                    .transition(.opacity)
            }

            if showsCollection {
                RestingHairCollection(profile: profile)
                    .transition(.opacity)
            } else if ambientWhenEmpty {
                RestingHairCollection(profile: Self.ambientProfile)
                    .opacity(0.34)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: profile.band)
        .accessibilityHidden(true)
    }
}

/// A faint warm gradient hugging the scene's lower edge — a floor for the falling/resting
/// strands to land on. Always present, independent of band or `showsCollection`, so the hero
/// never reads as unfinished empty space even when there is almost nothing else to draw.
private struct SceneGroundline: View {
    var body: some View {
        LinearGradient(
            colors: [Clinical.ink.opacity(0.05), Clinical.ink.opacity(0)],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

/// Elevated bands gain occasional grouped strands. This gives "more than usual" a distinct
/// rhythm instead of communicating it only by increasing particle count.
private struct SheddingClusterLayer: View {
    let profile: SheddingSceneProfile

    var body: some View {
        MotionTimeline(cadence: .ambient) { timeline, reduceMotion in
            Canvas { ctx, size in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 60)
                let duration = 3.7 - Double(profile.band) * 0.42

                for cluster in 0..<profile.clusterCount {
                    let phase: CGFloat
                    if reduceMotion {
                        phase = 0.40 + CGFloat(cluster) * 0.24
                    } else {
                        let raw = (seconds / duration) + Double(cluster) * 0.53
                        phase = CGFloat(raw - raw.rounded(.down))
                    }

                    let baseX = size.width * (0.22 + sheddingHashUnit(cluster, salt: 41) * 0.56)
                    let sway = sin(phase * .pi * 2 + CGFloat(cluster)) * (8 + CGFloat(profile.band) * 4)
                    let y = -34 + phase * (size.height + 64)
                    let edgeFade = min(1, phase * 9) * min(1, (1 - phase) * 6)
                    let strandCount = profile.band == 2 ? 3 : 5

                    for strand in 0..<strandCount {
                        let offset = (CGFloat(strand) - CGFloat(strandCount - 1) / 2) * 3.8
                        let curl = sheddingHashUnit(strand + cluster * 7, salt: 53) * 9
                        var path = Path()
                        path.move(to: CGPoint(x: baseX + sway + offset, y: y))
                        path.addCurve(
                            to: CGPoint(x: baseX + sway - offset * 0.45, y: y + 30 + curl),
                            control1: CGPoint(x: baseX + sway + 11 + curl, y: y + 8),
                            control2: CGPoint(x: baseX + sway - 12 - curl, y: y + 20)
                        )
                        ctx.stroke(
                            path,
                            with: .color(
                                (strand.isMultiple(of: 2) ? Clinical.accent : Clinical.ink)
                                    .opacity(Double(edgeFade) * (profile.band == 3 ? 0.72 : 0.58))
                            ),
                            style: StrokeStyle(lineWidth: 1.45, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A restrained tangle rather than a literal numeric hair count. The number of paths is fixed per
/// band, so the visual reads consistently whenever the user returns to the same answer.
private struct RestingHairCollection: View {
    let profile: SheddingSceneProfile

    var body: some View {
        Canvas { ctx, size in
            let count = profile.restingStrandCount
            let spread = min(size.width * 0.56, 86 + CGFloat(profile.band) * 20)
            let centerX = size.width * 0.70
            let baseline = size.height - 13

            // A soft grounded shadow makes the resting strands feel collected, not suspended.
            let shadowRect = CGRect(
                x: centerX - spread * 0.56,
                y: baseline - 3,
                width: spread * 1.12,
                height: 10
            )
            ctx.fill(
                Path(ellipseIn: shadowRect),
                with: .color(Clinical.ink.opacity(0.025 + Double(profile.band) * 0.012))
            )

            for index in 0..<count {
                let a = sheddingHashUnit(index, salt: 3)
                let b = sheddingHashUnit(index, salt: 7)
                let c = sheddingHashUnit(index, salt: 11)
                let startX = centerX - spread * 0.48 + a * spread * 0.76
                let endX = centerX - spread * 0.34 + b * spread * 0.76
                let y = baseline - c * (4 + CGFloat(profile.band) * 2.2)
                let lift = 4 + b * (8 + CGFloat(profile.band) * 3)

                var path = Path()
                path.move(to: CGPoint(x: startX, y: y))
                path.addCurve(
                    to: CGPoint(x: endX, y: y + (a - 0.5) * 4),
                    control1: CGPoint(x: startX + spread * (0.18 + c * 0.14), y: y - lift),
                    control2: CGPoint(x: endX - spread * (0.16 + a * 0.13), y: y + lift * 0.72)
                )
                let palette: [Color] = [Clinical.ink, Clinical.accent, Clinical.secondary, Clinical.gold]
                ctx.stroke(
                    path,
                    with: .color(palette[index % palette.count].opacity(0.42 + Double(profile.band) * 0.08)),
                    style: StrokeStyle(
                        lineWidth: 1.1 + c * 0.9,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

}

private func sheddingHashUnit(_ index: Int, salt: Int) -> CGFloat {
    let value = sin(CGFloat((index + 1) * 127 + salt * 313)) * 43_758.5453
    return value - value.rounded(.down)
}
