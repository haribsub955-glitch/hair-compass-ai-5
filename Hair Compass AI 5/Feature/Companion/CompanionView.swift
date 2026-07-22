import SwiftUI

/// Renders the Wren companion for a moment. Purely decorative: never intercepts touches and is
/// invisible to accessibility — spoken labels live on the surrounding controls. Two variants:
///
/// - `.pose`  — a full illustration that slowly "breathes" via the shared `LivingArtwork`
///   treatment (Reduce-Motion-safe, off-screen-paused). Used in hero/soft moments.
/// - `.avatar` — a small, static, circular-cropped Wren for entry points and the chat header.
struct CompanionView: View {
    enum Variant { case pose, avatar }

    let moment: CompanionMoment
    var variant: Variant = .pose
    var size: CGFloat = 80

    var body: some View {
        content
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .pose:
            LivingArtwork(art: Companion.pose(for: moment), contentMode: .fit)
                .frame(width: size, height: size)
        case .avatar:
            Image(CompanionArt.avatar)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
        }
    }
}
