import os
import SwiftUI
import UIKit

/// Full-screen host for one launch ritual: botanical backdrop + copy block + a `Canvas` driven by
/// `TimelineView(.animation)` that steps and draws the ritual, plus an always-available skip (✕ or
/// swipe-down). Completion runs a gentle fade, then reveals the app underneath via `onFinish()`.
struct RitualView: View {
    let kind: RitualKind
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var box = RitualBox()
    @State private var finishing = false
    @State private var contentOpacity: Double = 1
    @State private var startedAt = Date()
    @State private var serumBurst = false

    private let logger = Logger(subsystem: "hair-compass", category: "ritual")

    // Copy is read from a throwaway instance so it's available before the Canvas builds the live one.
    private var meta: (title: String, hint: String) {
        let r = RitualKind.make(kind)
        return (r.title, r.hint)
    }

    var body: some View {
        ZStack {
            // 1) Base canvas colour + botanical backdrop (center kept clear per the asset note).
            Group {
                Clinical.canvas.ignoresSafeArea()
                Image(BrandArt.ritualBackdrop)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.9)
                    .ignoresSafeArea()

                // 2) The interaction canvas.
                ritualCanvas
                    .gesture(interactionGesture)

                // 3) Copy block — non-interactive so drags anywhere reach the canvas.
                VStack(spacing: 8) {
                    Text("HAIR COMPASS")
                        .font(Clinical.eyebrow(10.5)).tracking(2)
                        .foregroundStyle(Clinical.tertiary)
                    Text(meta.title)
                        .font(Clinical.headline(34))
                        .foregroundStyle(Clinical.ink)
                        .multilineTextAlignment(.center)
                    Text(meta.hint)
                        .font(Clinical.caption(13.5))
                        .foregroundStyle(Clinical.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 66)
                .allowsHitTesting(false)
            }
            .opacity(contentOpacity)

            // 4) Skip affordance: a top strip that hosts the ✕ button and recognises swipe-down.
            VStack {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .frame(height: 96)
                        .contentShape(Rectangle())
                        .gesture(swipeDownGesture)
                    Button(action: skip) {
                        Image(systemName: "xmark")
                            .font(Clinical.body(15, weight: .semibold))
                            .foregroundStyle(Clinical.secondary)
                            .frame(width: 34, height: 34)
                            .background(Clinical.surface.opacity(0.85), in: Circle())
                            .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .padding(.trailing, 16)
                    .accessibilityLabel("Skip")
                    .accessibilityIdentifier("ritualSkip")
                }
                Spacer()

                // Under Reduce Motion the frame is static, so offer explicit completion.
                if reduceMotion {
                    Button(action: complete) {
                        Text("Done")
                            .font(Clinical.body(16, weight: .semibold))
                            .foregroundStyle(Clinical.surface)
                            .padding(.horizontal, 40).padding(.vertical, 14)
                            .background(Clinical.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 44)
                }
            }
            .opacity(finishing ? 0 : 1)   // clear the skip/done chrome once we start finishing

            // 5) Serum copper-burst finish (spec §2) — overlays everything, then reveals via onFinish.
            if serumBurst {
                SerumBurst(onDone: onFinish)
                    .ignoresSafeArea()
                    .transition(.identity)
            }
        }
        .onAppear {
            startedAt = Date()
            RitualActivityService.shared.start(kind: kind, title: meta.title, startDate: startedAt)
        }
        .onDisappear {
            // Safety net: RootView can force-dismiss the ritual out from under us (app lock wins
            // over an in-flight ritual — see RootView's `ritualKind = nil` on that path), which
            // tears this view down without `skip()`/`complete()` ever running. `end` is a no-op
            // once either of those has already cleared the activity.
            RitualActivityService.shared.end(stepName: meta.title, progress: 0, completed: false)
        }
    }

    // MARK: Canvas

    private var ritualCanvas: some View {
        MotionTimeline(cadence: .interactive) { timeline, reduceMotion in
            Canvas { ctx, size in
                if box.ritual == nil { box.ritual = RitualKind.make(kind) }
                var context = ctx

                if reduceMotion {
                    // Static representative frame — no stepping, so push the Live Activity's
                    // starting state once here (it otherwise only updates from the step loop
                    // below) and leave it at 0% until the explicit "Done" button calls complete().
                    box.ritual?.draw(in: &context, size: size)
                    if let ritual = box.ritual {
                        RitualActivityService.shared.update(stepName: ritual.title, progress: 0, endDate: nil)
                    }
                    return
                }

                let now = timeline.date
                let dt = box.last.map { min(CGFloat(now.timeIntervalSince($0)), 0.05) } ?? 0
                box.last = now
                let beats = box.ritual?.step(dt: dt, size: size) ?? 0
                box.ritual?.draw(in: &context, size: size)

                if let ritual = box.ritual {
                    let endDate = ritual.estimatedDuration.map { startedAt.addingTimeInterval($0) }
                    RitualActivityService.shared.update(
                        stepName: ritual.title, progress: Double(ritual.progress), endDate: endDate)
                }

                if beats > 0 { box.impact.impactOccurred() }

                if box.ritual?.isComplete == true, !box.finished {
                    box.finished = true
                    DispatchQueue.main.async { complete() }
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Gestures

    private var interactionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let prev = box.lastTouch ?? value.startLocation
                let phase: RitualTouch.Phase = box.dragging ? .moved : .began
                box.dragging = true
                box.ritual?.handle(RitualTouch(location: value.location, previous: prev, phase: phase))
                box.lastTouch = value.location
            }
            .onEnded { value in
                let prev = box.lastTouch ?? value.startLocation
                box.ritual?.handle(RitualTouch(location: value.location, previous: prev, phase: .ended))
                box.dragging = false
                box.lastTouch = nil
            }
    }

    private var swipeDownGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if value.translation.height > 60 { skip() }
            }
    }

    // MARK: Skip / complete

    private func skip() {
        logger.debug("ritual_skipped kind=\(kind.rawValue, privacy: .public) at=\(Date().timeIntervalSince(startedAt), privacy: .public)")
        RitualActivityService.shared.end(stepName: meta.title, progress: Double(box.ritual?.progress ?? 0), completed: false)
        onFinish()
    }

    /// Success beat + finish sequence. Comb / knot / massage use the plain fade; serum plays the
    /// copper-burst overlay (which drives its own timing, then calls `onFinish`).
    private func complete() {
        guard !finishing else { return }
        finishing = true
        logger.debug("ritual_completed kind=\(kind.rawValue, privacy: .public) duration=\(Date().timeIntervalSince(startedAt), privacy: .public)")
        box.success.notificationOccurred(.success)   // haptics kept even under Reduce Motion
        RitualActivityService.shared.end(stepName: meta.title, progress: 1, completed: true)

        if reduceMotion {
            onFinish()
            return
        }

        switch kind {
        case .serum:
            // Copper-burst finish: fade the ritual under the burst, which expands to cover, throws
            // 28 droplets, fades, and reveals the destination via `onFinish`.
            withAnimation(.easeInOut(duration: 0.5)) { contentOpacity = 0 }
            serumBurst = true
        default:
            // Interaction + backdrop fade out over 0.9s; reveal the destination ≈0.65s after finish.
            withAnimation(.easeInOut(duration: 0.9)) { contentOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { onFinish() }
        }
    }
}

/// The serum copper-burst finish (spec §2): a flat copper circle expands from the pool to cover the
/// screen, then fades while 28 droplet particles fly outward under gravity. Drives its own frame
/// clock and calls `onDone` (≈0.9s) to reveal the destination.
private struct SerumBurst: View {
    var onDone: () -> Void
    @State private var box = BurstBox()

    var body: some View {
        MotionTimeline(cadence: .interactive) { timeline, _ in
            Canvas { ctx, size in
                if !box.started { box.start(size: size); box.started = true }
                let now = timeline.date
                let dt = box.last.map { min(CGFloat(now.timeIntervalSince($0)), 0.05) } ?? 0
                box.last = now
                box.advance(dt: dt)
                var context = ctx
                box.draw(in: &context)
                if box.done, !box.calledDone {
                    box.calledDone = true
                    DispatchQueue.main.async { onDone() }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Reference box for the burst so the per-frame particle sim doesn't thrash SwiftUI state.
@MainActor private final class BurstBox {
    private struct Particle { var pos: CGPoint; var vel: CGPoint; var r: CGFloat }

    var started = false
    var done = false
    var calledDone = false
    var last: Date?

    private var elapsed: CGFloat = 0
    private var circleR: CGFloat = 0
    private var maxR: CGFloat = 1
    private var origin: CGPoint = .zero
    private var particles: [Particle] = []

    func start(size: CGSize) {
        origin = CGPoint(x: size.width / 2, y: size.height * 0.78)   // burst from the pool
        maxR = (size.width * size.width + size.height * size.height).squareRoot()
        for _ in 0..<28 {
            let ang = CGFloat.random(in: 0...(2 * CGFloat.pi))
            let spd = CGFloat.random(in: 4...12)
            particles.append(Particle(
                pos: origin,
                vel: CGPoint(x: cos(ang) * spd, y: sin(ang) * spd - 6),   // slight upward bias
                r: CGFloat.random(in: 3...7)))
        }
    }

    func advance(dt: CGFloat) {
        elapsed += dt
        circleR = min(maxR, circleR + maxR * 0.10)   // per-frame expansion
        for i in particles.indices {
            particles[i].vel.y += 0.3                 // gravity 0.3/frame
            particles[i].pos.x += particles[i].vel.x
            particles[i].pos.y += particles[i].vel.y
            particles[i].r *= 0.99                     // shrink 0.99/frame
        }
        particles.removeAll { $0.r < 0.5 }
        if elapsed > 0.9 { done = true }
    }

    func draw(in ctx: inout GraphicsContext) {
        // Solid while covering, then fades from ~0.45s so the destination reads through.
        let fade: Double = elapsed > 0.45 ? max(0, Double(1 - (elapsed - 0.45) / 0.45)) : 1
        let circle = Path(ellipseIn: CGRect(x: origin.x - circleR, y: origin.y - circleR, width: circleR * 2, height: circleR * 2))
        ctx.fill(circle, with: .color(Clinical.accent.opacity(fade)))
        for p in particles {
            let rect = CGRect(x: p.pos.x - p.r, y: p.pos.y - p.r, width: p.r * 2, height: p.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(Clinical.accent.opacity(fade)))
        }
    }
}

/// Reference box holding the mutable ritual so per-frame `step`/`draw` don't thrash SwiftUI state
/// (mirrors `HairSimBox` in HairPhysics.swift). Also caches the frame clock, drag state, and the
/// (prepared) haptic generators.
@MainActor private final class RitualBox {
    var ritual: (any Ritual)?
    var last: Date?
    var lastTouch: CGPoint?
    var dragging = false
    var finished = false
    let impact = UIImpactFeedbackGenerator(style: .light)
    let success = UINotificationFeedbackGenerator()
}
