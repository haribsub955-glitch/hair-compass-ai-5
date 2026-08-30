import SwiftUI

/// The first-run cover: four illustrated pages that say what the app is *for* before
/// `OnboardingFlow` starts asking questions. It replaces the old single `welcome` step, so the
/// questionnaire behind it — and everything it seeds into `Profile`/`DailyEntry` — is untouched.
///
/// Everything except the artwork is native SwiftUI: type, buttons, dots and the page gesture are
/// all system views, and the only bitmaps are transparent gouache layers from the asset catalog.
/// Each page stacks **two** layers so they can move at different rates as the page turns, which is
/// what sells the depth (see `IntroArtStage`).
///
/// Dark mode: `Clinical`'s palette is hardcoded to the light ivory theme, so this file carries its
/// own `IntroPalette` that resolves against `\.colorScheme`. Values track Clinical exactly in
/// light mode — the cover is pixel-identical to the rest of the app — and invert to a warm
/// espresso theme in dark. (The app root still applies `.preferredColorScheme(.light)` globally;
/// see `HairCompassApp`. This view is correct the moment that lock is lifted.)
struct OnboardingIntro: View {
    /// Called when the last page's primary action is tapped — hands off to the questionnaire.
    var onFinish: () -> Void
    /// The welcome step's quiet escape hatch for anyone migrating phones. Preserved verbatim.
    var onRestore: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var page: Int? = OnboardingIntro.initialPage

    /// Jump straight to a page for QA/screenshots — mirrors `OnboardingFlow.initialStep`'s
    /// `HC_ONBOARD_STEP`. DEBUG-only, so it can't be triggered in a shipping build.
    private static var initialPage: Int {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "HC_INTRO_PAGE"), i + 1 < a.count, let n = Int(a[i + 1]) {
            return max(0, min(IntroPage.all.count - 1, n))
        }
        #endif
        return 0
    }

    private var palette: IntroPalette { IntroPalette(scheme) }
    private var pages: [IntroPage] { IntroPage.all }
    /// The page the chrome should reflect. `scrollPosition` is nil mid-flight between pages.
    private var current: Int { page ?? 0 }
    private var isLast: Bool { current == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            pager
            chrome
        }
        // The `Color` paints under the status bar on its own; the *content* must keep respecting
        // the safe area, or a long headline at accessibility sizes slides under the clock.
        .background(palette.canvas.ignoresSafeArea())
    }

    // MARK: Pager

    /// A horizontal paging `ScrollView` rather than `TabView(.page)`: it exposes a live scroll
    /// phase to `.scrollTransition`, which is what drives the per-layer parallax. A `TabView`
    /// gives no such hook, so the art could only cross-fade.
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    IntroPageView(page: page, palette: palette, isActive: current == index)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page, anchor: .center)
        .scrollIndicators(.hidden)
        // VoiceOver can't swipe a paging ScrollView reliably; the explicit adjustable action below
        // gives it a first-class way through the pages.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Introduction, page \(current + 1) of \(pages.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(to: min(current + 1, pages.count - 1))
            case .decrement: go(to: max(current - 1, 0))
            @unknown default: break
            }
        }
    }

    // MARK: Chrome — dots, primary action, restore link

    private var chrome: some View {
        VStack(spacing: 16) {
            IntroPageDots(count: pages.count, current: current, palette: palette)

            Button(isLast ? "Set up my compass" : "Continue") {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                if isLast {
                    onFinish()
                } else {
                    go(to: current + 1)
                }
            }
            .buttonStyle(IntroButtonStyle(palette: palette))
            .padding(.horizontal, 20)
            // Stable across all four pages even though the label changes on the last one, so UI
            // tests can walk the cover without hard-coding copy.
            .accessibilityIdentifier("onboardIntroPrimary")

            // Only the first page offers this, matching the welcome step it replaces. It is
            // *removed* rather than hidden-but-laid-out: an invisible label still reserves its
            // height, and at accessibility text sizes that left a large dead band under the button.
            if current == 0 {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onRestore()
                } label: {
                    Text("Restoring from a backup?")
                        .font(Clinical.caption(13))
                        .foregroundStyle(palette.tertiary)
                }
                .accessibilityIdentifier("onboardRestoreFromBackup")
                .transition(.opacity)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 22)
    }

    private func go(to index: Int) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                   : .spring(response: 0.45, dampingFraction: 0.86)) {
            page = index
        }
    }
}

// MARK: - Page model

/// One intro page: the words, and the two art layers behind them.
struct IntroPage: Identifiable {
    let id: Int
    let eyebrow: String
    let title: String
    let body: String
    /// Far layer — drifts slowly, reads as distance.
    let backArt: String
    /// Near layer — the subject; travels further as the page turns.
    let frontArt: String
    let motif: IntroMotif
    /// Layer geometry is per-page: one shared size made the wide garland clump against the
    /// journal and let Wren cover the compass's centre. Each pair is sized so the far layer
    /// clearly frames the near one.
    let backSize: CGFloat
    let frontSize: CGFloat
    /// Nudges the subject within the stage — Wren perches low so the star's points stay visible.
    let frontOffset: CGSize

    static let all: [IntroPage] = [
        IntroPage(
            id: 0,
            eyebrow: "Meet \(Companion.name)",
            title: "Your hair,\nunderstood.",
            body: "I'm \(Companion.name). I'll help you notice what your hair is actually doing — a little at a time.",
            backArt: "intro-compass",
            frontArt: CompanionArt.greeting,
            motif: .compass,
            backSize: 300,
            frontSize: 152,
            frontOffset: CGSize(width: 10, height: 46)
        ),
        IntroPage(
            id: 1,
            eyebrow: "Every day",
            title: "Notice the\nsmall things.",
            body: "A few taps a day — shedding, scalp, sleep, stress. The quiet signals that turn out to matter most.",
            backArt: "intro-ritual-back",
            frontArt: "intro-ritual-front",
            motif: .ritual,
            backSize: 360,
            frontSize: 196,
            frontOffset: CGSize(width: 0, height: -10)
        ),
        IntroPage(
            id: 2,
            eyebrow: "Over time",
            title: "See the pattern\nemerge.",
            body: "Weeks of small notes become a picture you can read — and hand to a clinician who can act on it.",
            backArt: "intro-trend-back",
            frontArt: "intro-trend-front",
            motif: .growth,
            backSize: 300,
            frontSize: 210,
            frontOffset: .zero
        ),
        IntroPage(
            id: 3,
            eyebrow: "Private by design",
            title: "Yours alone.",
            body: "Your entries stay on this device. \(Companion.name) can answer on-device, or — only if you say yes — with a secure cloud model. Your name and photos are never sent, either way.",
            backArt: "intro-private-back",
            frontArt: "intro-private-front",
            motif: .safekeeping,
            backSize: 296,
            frontSize: 150,
            frontOffset: CGSize(width: 0, height: 12)
        ),
    ]
}

/// Which idle motion the near layer gets. Each is tuned to what the object *is*: a compass turns,
/// a seedling grows, a lock settles and holds.
enum IntroMotif {
    case compass      // back layer turns very slowly; Wren breathes above it
    case ritual       // a slow, shallow breath — a still life at rest
    case growth       // springs up from its base on arrival, then sways
    case safekeeping  // settles once and stays put
}

// MARK: - A single page

private struct IntroPageView: View {
    let page: IntroPage
    let palette: IntroPalette
    let isActive: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility text sizes the words need the room more than the picture does, so the
    /// stage gives most of its height back rather than crowding the copy.
    private var artHeight: CGFloat {
        typeSize.isAccessibilitySize ? 130 : 290
    }

    var body: some View {
        // The copy at AccessibilityXXXL is taller than the screen, so the page has to be able to
        // scroll — without this it clipped the headline off the top and truncated the body
        // mid-sentence with no way to reach the rest. `minHeight: geo.size.height` keeps the
        // familiar centred composition at normal sizes, and `.basedOnSize` suppresses the rubber
        // -band bounce when everything already fits.
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    IntroArtStage(page: page, isActive: isActive)
                        .frame(height: artHeight)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    Spacer().frame(height: typeSize.isAccessibilitySize ? 22 : 30)

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: page.eyebrow, color: palette.accent)
                        Text(page.title)
                            .font(Clinical.headline(34))
                            .foregroundStyle(palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(page.body)
                            .font(Clinical.caption(15))
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    // One utterance per page instead of three fragments.
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 0)
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Layered art

/// The two-layer stage. Depth comes from three stacked effects:
///
/// 1. **Parallax on turn** — `.scrollTransition` offsets each layer by a different multiple of the
///    live scroll phase, so the near layer outruns the far one as you swipe.
/// 2. **Entrance** — the near layer springs in when its page becomes active.
/// 3. **Idle motion** — a slow ambient loop per `IntroMotif`.
///
/// All three collapse to a static frame under Reduce Motion.
private struct IntroArtStage: View {
    let page: IntroPage
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            backLayer
            frontLayer
        }
        .compositingGroup()
    }

    // MARK: Far layer

    private var backLayer: some View {
        Image(page.backArt)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: page.backSize, maxHeight: page.backSize)
            // Held back from full strength so the near layer clearly sits in front of it.
            .opacity(0.82)
            .rotationEffect(.degrees(page.motif == .compass && spin && !reduceMotion ? 360 : 0))
            .animation(
                page.motif == .compass && !reduceMotion
                    ? .linear(duration: 120).repeatForever(autoreverses: false)
                    : .default,
                value: spin
            )
            .scaleEffect(breathe && !reduceMotion ? 1.015 : 1)
            .animation(
                reduceMotion ? .default : .easeInOut(duration: 5.5).repeatForever(autoreverses: true),
                value: breathe
            )
            .parallax(magnitude: 26, fade: 0.5, reduceMotion: reduceMotion)
            .onAppear {
                spin = true
                breathe = true
            }
    }

    // MARK: Near layer

    private var frontLayer: some View {
        IntroSubject(page: page, isActive: isActive)
            .parallax(magnitude: 78, fade: 0.75, reduceMotion: reduceMotion)
    }
}

/// The near-layer subject and its per-motif idle loop, split out so the `PhaseAnimator`/
/// `KeyframeAnimator` state doesn't re-run every time the parent's scroll phase changes.
private struct IntroSubject: View {
    let page: IntroPage
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var art: some View {
        Image(page.frontArt)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: page.frontSize, maxHeight: page.frontSize)
            .shadow(color: Clinical.shadowWarm.opacity(0.18), radius: 16, y: 10)
            .offset(page.frontOffset)
    }

    var body: some View {
        Group {
            if reduceMotion {
                art
            } else {
                switch page.motif {
                case .compass, .ritual, .safekeeping:
                    // A shared, very shallow float. `PhaseAnimator` gives a continuous native loop
                    // without a Timer or TimelineView.
                    art.phaseAnimator([0.0, 1.0]) { view, phase in
                        view
                            .offset(y: phase == 0 ? -4 : 4)
                            .rotationEffect(.degrees(page.motif == .safekeeping ? 0 : (phase == 0 ? -0.7 : 0.7)))
                    } animation: { _ in
                        .easeInOut(duration: page.motif == .safekeeping ? 4.2 : 3.2)
                    }
                case .growth:
                    // The seedling earns a real entrance: it springs up from its own base, so it
                    // reads as *growing* rather than sliding in.
                    art.keyframeAnimator(initialValue: GrowthValues(), trigger: grown) { view, v in
                        view
                            .scaleEffect(x: v.scaleX, y: v.scaleY, anchor: .bottom)
                            .rotationEffect(.degrees(v.tilt), anchor: .bottom)
                    } keyframes: { _ in
                        KeyframeTrack(\.scaleY) {
                            SpringKeyframe(1.0, duration: 1.1, spring: .bouncy(duration: 0.9))
                            CubicKeyframe(1.012, duration: 2.2)
                            CubicKeyframe(1.0, duration: 2.2)
                        }
                        KeyframeTrack(\.scaleX) {
                            SpringKeyframe(1.0, duration: 1.1, spring: .snappy)
                            CubicKeyframe(0.995, duration: 2.2)
                            CubicKeyframe(1.0, duration: 2.2)
                        }
                        KeyframeTrack(\.tilt) {
                            CubicKeyframe(0, duration: 1.1)
                            CubicKeyframe(1.2, duration: 2.2)
                            CubicKeyframe(0, duration: 2.2)
                        }
                    }
                }
            }
        }
        .onChange(of: isActive) { _, active in
            // Re-trigger the growth entrance each time the page is returned to.
            if active { grown.toggle() }
        }
    }
}

/// Keyframe-animated properties for the seedling's growth entrance.
private struct GrowthValues {
    var scaleX: Double = 0.9
    var scaleY: Double = 0.82
    var tilt: Double = 0
}

private extension View {
    /// Ties a layer to the live paging scroll phase. Larger `magnitude` = nearer the viewer.
    /// Under Reduce Motion the layer is pinned and only cross-fades.
    func parallax(magnitude: CGFloat, fade: Double, reduceMotion: Bool) -> some View {
        scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .offset(x: reduceMotion ? 0 : phase.value * magnitude)
                .opacity(1 - abs(phase.value) * fade)
                .scaleEffect(reduceMotion ? 1 : 1 - abs(phase.value) * 0.05)
        }
    }
}

// MARK: - Page dots

private struct IntroPageDots: View {
    let count: Int
    let current: Int
    let palette: IntroPalette

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? palette.accent : palette.hairline)
                    .frame(width: i == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
        // The pager already announces "page N of M"; the dots are a duplicate for VoiceOver.
        .accessibilityHidden(true)
    }
}

// MARK: - Button

/// `ClinicalButtonStyle` with the palette swapped in, so the copper bar stays legible on the dark
/// canvas. Geometry, corner radius, glow and press feedback are identical to the shared style.
private struct IntroButtonStyle: ButtonStyle {
    let palette: IntroPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Clinical.body(16, weight: .semibold))
            .foregroundStyle(palette.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(palette.accent)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: palette.accent.opacity(0.28), radius: 12, y: 5)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Adaptive palette

/// Light values are copied verbatim from `Clinical` so the cover is indistinguishable from the
/// rest of the app; dark values are the same hues re-seated on a warm espresso ground (never a
/// neutral grey/black, which would break the brand's warmth). Accent is lifted in dark mode
/// because #B1592E on near-black falls under the 4.5:1 body-text threshold.
struct IntroPalette {
    let canvas: Color
    let ink: Color
    let secondary: Color
    let tertiary: Color
    let hairline: Color
    let accent: Color
    /// Foreground for text sitting *on* `accent`.
    let onAccent: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            canvas = Color(red: 0.086, green: 0.067, blue: 0.055)     // #16110E espresso ground
            ink = Color(red: 0.961, green: 0.929, blue: 0.886)        // #F5EDE2 warm paper
            secondary = Color(red: 0.769, green: 0.706, blue: 0.639)  // #C4B4A3
            tertiary = Color(red: 0.604, green: 0.545, blue: 0.486)   // #9A8B7C
            hairline = Color(red: 0.227, green: 0.184, blue: 0.149)   // #3A2F26
            accent = Color(red: 0.851, green: 0.478, blue: 0.278)     // #D97A47 lifted copper
            onAccent = Color(red: 0.106, green: 0.082, blue: 0.067)   // #1B1511
        } else {
            canvas = Clinical.canvas
            ink = Clinical.ink
            secondary = Clinical.secondary
            tertiary = Clinical.tertiary
            hairline = Clinical.hairline
            accent = Clinical.accent
            onAccent = Clinical.surface
        }
    }
}
