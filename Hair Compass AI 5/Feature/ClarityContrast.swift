import SwiftUI

/// The subscribe moment's one piece of persuasion: the same person, twice, in the two states this
/// app actually moves you between — **guessing** and **seeing clearly**.
///
/// It is deliberately NOT a before/after. Both panels show identical hair: same length, same
/// shape, same density. Only the light changes — the left figure dissolves into cool mist with
/// strands drifting away uncounted, the right is warm, resolved and definite. That is the honest
/// claim, and it is the same axis `ProjectionModel` already draws as `withTracking` vs `without`
/// ("a single week's reading on the universal signal-clarity chart — never hair count").
///
/// Two rules hold this in place, and both matter legally as well as ethically:
/// 1. The artwork must never imply hair was gained, regrown or thickened. `captionLine` says so
///    out loud — "Same hair, six months apart. The difference is what you can see." — so a
///    skim-reader cannot mistake the pair for a results claim.
/// 2. Nothing here promises an outcome. It describes what tracking shows you, not what it grows.
///
/// Shared verbatim by `OnboardingPlanStep` (the onboarding paywall) and `ProGate` (the in-app
/// upsell) so the two conversion surfaces stay identical; `.compact` trims the vertical rhythm
/// for the gate, which sits inside a sheet.
struct ClarityContrast: View {
    enum Size { case full, compact }
    var size: Size = .full
    /// Picks the matching pair of figures. Men get a crown/vertex angle — the view they actually
    /// photograph, and where male-pattern change shows — rather than a generic silhouette.
    var sex: BiologicalSex = .male

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var settled = false

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .center, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    private var artHeight: CGFloat {
        // At accessibility sizes the labels below each panel need the room more than the picture.
        if typeSize.isAccessibilitySize { return size == .compact ? 96 : 116 }
        return size == .compact ? 132 : 168
    }

    var body: some View {
        VStack(spacing: size == .compact ? 10 : 14) {
            // Side by side is the whole point — the contrast only reads when both states are in
            // one glance. But at accessibility text sizes each panel is barely 150pt wide, and the
            // captions cramp into unreadable slivers, so there the pair stacks vertically instead.
            // `AnyLayout` swaps the container without tearing down the panels' state.
            layout {
                panel(
                    art: artName(steady: false),
                    title: "Guessing",
                    caption: "Something's changing. You can't tell what, or whether anything helps.",
                    steady: false
                )
                panel(
                    art: artName(steady: true),
                    title: "Seeing clearly",
                    caption: "The same months, recorded. Now the pattern — and what moves it — is legible.",
                    steady: true
                )
            }

            Text(captionLine)
                .font(Clinical.caption(11))
                .foregroundStyle(Clinical.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !settled else { return }
            if reduceMotion {
                settled = true
            } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.35)) {
                    settled = true
                }
            }
        }
        // One utterance. Without this VoiceOver reads six disconnected fragments and the contrast
        // — the whole point — never lands.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Illustration comparing two states. Without tracking: guessing — something's changing, "
            + "you can't tell what, or whether anything helps. With tracking: seeing clearly — the "
            + "same months, recorded, so the pattern and what moves it is legible. \(captionLine)"
        )
    }

    /// Stated plainly rather than buried in a footnote: the pair is about visibility, not regrowth.
    private var captionLine: String {
        "Same hair, six months apart. The difference is what you can see."
    }

    /// Follows the same convention as `BiologicalSex.stagingScaleName` — only `.female` takes the
    /// female set, and `.other` falls back to the male one, so the app is internally consistent
    /// about which reference it shows rather than inventing a second rule here.
    private func artName(steady: Bool) -> String {
        let base = steady ? "clarity-with" : "clarity-without"
        return sex == .female ? base : "\(base)-male"
    }

    private func panel(art: String, title: String, caption: String, steady: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(art)
                    .resizable()
                    .scaledToFit()
                    .frame(height: artHeight)
                    .frame(maxWidth: .infinity)
                    // The unresolved side sits back a touch; the resolved side comes forward.
                    .saturation(steady ? 1 : 0.92)

                NeedleBadge(steady: steady, settled: settled)
                    .padding(6)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(steady ? Clinical.accentSoft : Clinical.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(steady ? Clinical.accent.opacity(0.35) : Clinical.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 3) {
                Text(title)
                    .font(Clinical.body(14, weight: .semibold))
                    .foregroundStyle(steady ? Clinical.accent : Clinical.secondary)
                Text(caption)
                    .font(Clinical.caption(11))
                    .foregroundStyle(Clinical.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The compass needle, drawn natively so it can actually *move*: it hunts continuously on the
/// "guessing" panel and swings to true north and stays there on the "seeing clearly" panel. This
/// is the idea in motion — the artwork carries the mood, the needle carries the meaning — and it
/// is why the compass isn't baked into the bitmaps.
private struct NeedleBadge: View {
    let steady: Bool
    let settled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hunting = false

    private var diameter: CGFloat { 26 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Clinical.surface.opacity(0.92))
                .overlay(Circle().strokeBorder(steady ? Clinical.accent.opacity(0.4) : Clinical.hairline, lineWidth: 1))

            Capsule()
                .fill(steady ? Clinical.accent : Clinical.tertiary)
                .frame(width: 2, height: diameter * 0.42)
                .offset(y: -diameter * 0.1)
                .rotationEffect(needleAngle)
                .animation(huntAnimation, value: hunting)
                .animation(.spring(response: 0.7, dampingFraction: 0.6), value: settled)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Clinical.shadowWarm.opacity(0.14), radius: 3, y: 1)
        .onAppear { if !steady && !reduceMotion { hunting = true } }
        .accessibilityHidden(true)
    }

    private var needleAngle: Angle {
        if steady {
            // Swings to north once the pair has settled, then holds.
            return .degrees(settled || reduceMotion ? 0 : -38)
        }
        // Never lands: a slow, restless hunt that reads as "no fixed reading". Under Reduce
        // Motion it simply rests off-north, which still reads as "not pointing anywhere".
        return .degrees(reduceMotion ? -34 : (hunting ? 34 : -34))
    }

    /// Only the unresolved needle animates, and only when motion is allowed; `nil` disables the
    /// modifier entirely rather than running a zero-duration animation every frame.
    private var huntAnimation: Animation? {
        (steady || reduceMotion) ? nil : .easeInOut(duration: 2.1).repeatForever(autoreverses: true)
    }
}
