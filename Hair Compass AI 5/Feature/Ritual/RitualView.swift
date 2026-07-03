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
                        .font(.system(size: 13.5))
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Clinical.secondary)
                            .frame(width: 34, height: 34)
                            .background(Clinical.surface.opacity(0.85), in: Circle())
                            .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .padding(.trailing, 16)
                }
                Spacer()

                // Under Reduce Motion the frame is static, so offer explicit completion.
                if reduceMotion {
                    Button(action: complete) {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Clinical.surface)
                            .padding(.horizontal, 40).padding(.vertical, 14)
                            .background(Clinical.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 44)
                }
            }
        }
        .onAppear { startedAt = Date() }
    }

    // MARK: Canvas

    private var ritualCanvas: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                if box.ritual == nil { box.ritual = RitualKind.make(kind) }
                var context = ctx

                if reduceMotion {
                    // Static representative frame — no stepping.
                    box.ritual?.draw(in: &context, size: size)
                    return
                }

                let now = timeline.date
                let dt = box.last.map { min(CGFloat(now.timeIntervalSince($0)), 0.05) } ?? 0
                box.last = now
                let beats = box.ritual?.step(dt: dt, size: size) ?? 0
                box.ritual?.draw(in: &context, size: size)

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
        onFinish()
    }

    /// Success beat + finish sequence. Comb/knot use the plain fade; the serum copper-burst is added
    /// in the follow-up — its hook is the `.serum` branch below.
    private func complete() {
        guard !finishing else { return }
        finishing = true
        logger.debug("ritual_completed kind=\(kind.rawValue, privacy: .public) duration=\(Date().timeIntervalSince(startedAt), privacy: .public)")
        box.success.notificationOccurred(.success)   // haptics kept even under Reduce Motion

        if reduceMotion {
            onFinish()
            return
        }

        switch kind {
        case .serum:
            // TODO(follow-up): copper-burst finish — a flat copper circle expands from the
            // completion point covering the screen, 28 droplet particles fly out, then reveal.
            // For now it falls through to the shared fade so the app is still revealed.
            fallthrough
        default:
            // Interaction + backdrop fade out over 0.9s; reveal the destination ≈0.65s after finish.
            withAnimation(.easeInOut(duration: 0.9)) { contentOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { onFinish() }
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
