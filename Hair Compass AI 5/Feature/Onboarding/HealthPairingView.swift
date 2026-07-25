import SwiftUI

/// The Apple Health pairing visual for onboarding's connect step: this app's mark, a link, and the
/// Health heart — two tiles that "shake hands" until they're joined.
///
/// Modelled on the pairing animation the user liked (Yazio's activity-tracking screen), with one
/// deliberate difference: **that loop is decorative and runs forever regardless of what's actually
/// happening.** This one is driven by `HealthKitService.authorization`, so the animation *is* the
/// status:
///
/// - `.idle` — the tiles pulse alternately and the link is faint and dashed. Nothing is joined yet,
///   and the picture says so.
/// - `.connecting` — the link brightens and the tiles lean toward each other while the system
///   permission sheet is up.
/// - `.joined` — the link goes solid copper and settles once, with a checkmark. It then *stops*.
///   A finished connection that keeps animating reads as still-working.
///
/// Everything is native SwiftUI over two SF Symbols and the app's own compass mark; there is no
/// bitmap of Apple's Health icon here, because reproducing another company's app icon inside your
/// own onboarding is a trademark problem. A pink heart glyph is the conventional, safe way to
/// denote Health, and is what Apple's own HIG guidance for third-party apps points to.
struct HealthPairingView: View {
    enum State { case idle, connecting, joined }

    let state: State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tile: CGFloat { 66 }

    var body: some View {
        HStack(spacing: 14) {
            appTile
            connector
            healthTile
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Hair Compass and Apple Health, not connected"
        case .connecting: return "Connecting Hair Compass to Apple Health"
        case .joined: return "Hair Compass is connected to Apple Health"
        }
    }

    // MARK: Tiles

    private var appTile: some View {
        pairTile {
            Image("intro-compass")
                .resizable()
                .scaledToFit()
                .padding(8)
        }
        // Phase-offset from the Health tile so the two alternate rather than pulse in unison —
        // that alternation is what reads as a handshake instead of a throb.
        .modifier(PairPulse(active: state == .idle && !reduceMotion, phase: 0))
    }

    private var healthTile: some View {
        pairTile {
            Image(systemName: "heart.fill")
                .font(.system(size: tile * 0.42, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.32, blue: 0.40),
                                 Color(red: 0.91, green: 0.16, blue: 0.36)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .modifier(PairPulse(active: state == .idle && !reduceMotion, phase: 0.5))
    }

    private func pairTile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: tile, height: tile)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
            .shadow(color: Clinical.cardShadow, radius: 8, y: 3)
    }

    // MARK: Connector

    private var connector: some View {
        ZStack {
            // A dashed rule that becomes solid once joined — the state change is legible without
            // colour alone, which matters for colour-blind users.
            Capsule()
                .strokeBorder(
                    state == .joined ? Clinical.accent : Clinical.hairline,
                    style: StrokeStyle(lineWidth: 2, dash: state == .joined ? [] : [3, 3])
                )
                .frame(width: 34, height: 2)

            Image(systemName: state == .joined ? "checkmark.circle.fill" : "link")
                .font(Clinical.body(15, weight: .semibold))
                .foregroundStyle(state == .idle ? Clinical.tertiary : Clinical.accent)
                .padding(5)
                .background(Clinical.canvas, in: Circle())
                .scaleEffect(state == .connecting && !reduceMotion ? 1.12 : 1)
                .animation(
                    reduceMotion || state != .connecting
                        ? .easeInOut(duration: 0.25)
                        : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: state
                )
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: state)
    }
}

/// One beat of the idle loop: two breaths, then a flip — the punctuation from the reference
/// animation, which keeps the pair feeling alive rather than merely throbbing.
private enum PairBeat: CaseIterable {
    case riseA, fallA, riseB, flip

    var scale: CGFloat {
        switch self {
        case .riseA, .riseB: return 1.045
        case .fallA: return 0.985
        case .flip: return 1
        }
    }

    var lift: CGFloat {
        switch self {
        case .riseA, .riseB: return -2
        case .fallA: return 2
        case .flip: return 0
        }
    }

    /// A **full 360°** turn, not 180°. A half turn would leave the face mirrored, and while both
    /// marks here are near-symmetric enough to survive it, a full turn is correct for any artwork
    /// that might replace them later.
    var spin: Double { self == .flip ? 360 : 0 }

    var animation: Animation {
        switch self {
        case .flip: return .easeInOut(duration: 0.85)
        default: return .easeInOut(duration: 1.15)
        }
    }
}

/// The alternating breath plus the periodic flip. A `PhaseAnimator` rather than a repeating
/// `.animation` so the sequence can give the flip its own faster curve, and so the whole thing
/// simply stops — not freezes mid-scale — when `active` goes false.
///
/// The two tiles stay out of step by **starting at different points in the same cycle** rather
/// than by delaying one of them. A delay inside a repeating phase animator re-applies on every
/// step and drifts; rotating the phase array is exact and drift-free.
private struct PairPulse: ViewModifier {
    let active: Bool
    /// 0 for the leading tile, 0.5 for the trailing one — half a cycle apart.
    let phase: Double

    private var beats: [PairBeat] {
        let all = PairBeat.allCases
        let shift = Int((Double(all.count) * phase).rounded()) % all.count
        return Array(all[shift...] + all[..<shift])
    }

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator(beats) { view, beat in
                view
                    .scaleEffect(beat.scale)
                    .offset(y: beat.lift)
                    .rotation3DEffect(
                        .degrees(beat.spin),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.45
                    )
            } animation: { beat in
                beat.animation
            }
        } else {
            content
        }
    }
}
