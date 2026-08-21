import Lottie
import SwiftUI
import UIKit

/// The app's one door to Lottie playback — every animated JSON in
/// `Resources/Animations/` renders through this wrapper, never through a raw
/// `Lottie.LottieView` at a call site, so the house rules cannot be skipped:
///
/// - **Reduce Motion is a contract, not a suggestion.** A looping animation
///   renders as its first frame, still (the same "hold a static scatter" rule
///   `LeafFallBackdrop` follows); a one-shot flourish disappears entirely,
///   because a decoration that only exists to move has no still form worth
///   keeping. This mirrors how the rest of the app treats RM: crossfades stay,
///   ornament stops.
/// - **Decorative by definition.** Everything played here is ornament beside
///   real copy, so the view is `accessibilityHidden` and never hit-testable.
///   If an animation ever needs to *say* something, give it a label at the
///   call site's text, not here.
/// - **One palette.** The JSONs are authored in Clinical copper/gold/sage. The
///   optional `tint` re-colors every fill through a value provider for the one
///   case where baked copper is wrong: sitting on a filled copper button
///   (`DeepAnalysisSheet`), where the mark must be `Clinical.surface` like the
///   spinner it replaced.
///
/// The animations themselves are code-authored Bodymovin JSON (see
/// `docs/ANIMATIONS.md` for the catalogue and the authoring pipeline).
struct ClinicalLottie: View {
    /// The wrapper's own vocabulary, so call sites never `import Lottie` — the
    /// dependency stays behind this one file and could be swapped without
    /// touching a feature.
    enum Mode {
        /// A waiting state: loops while real work happens.
        case loop
        /// A flourish: plays once at a moment of completion.
        case once
    }

    /// Bundle resource name, without extension — e.g. `"wren-thinking"`.
    let name: String
    /// `.loop` for waiting states; one-shots use `.once`.
    var mode: Mode = .loop
    /// Re-colors every fill in the animation. Nil keeps the authored palette.
    var tint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A one-shot that can't move is nothing: render nothing. A loop that
        // can't move is its resting pose: render frame zero, paused.
        if !(reduceMotion && mode == .once) {
            base
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var base: some View {
        LottieView(animation: .named(name))
            .playbackMode(
                reduceMotion
                    ? .paused(at: .progress(0)) // the loop's resting pose
                    : .playing(.fromProgress(0, toProgress: 1,
                                             loopMode: mode == .loop ? .loop : .playOnce))
            )
            .configure { animationView in
                animationView.contentMode = .scaleAspectFit
                if let tint {
                    animationView.setValueProvider(
                        ColorValueProvider(LottieColor(tint)),
                        keypath: AnimationKeypath(keypath: "**.Color")
                    )
                }
            }
    }
}

private extension LottieColor {
    /// SwiftUI `Color` → Lottie's color type, via UIKit resolution.
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: r, g: g, b: b, a: a)
    }
}
