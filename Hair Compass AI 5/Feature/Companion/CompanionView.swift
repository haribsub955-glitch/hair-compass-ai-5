import SwiftUI

/// Renders the Wren companion for a moment. Purely decorative: never intercepts touches and is
/// invisible to accessibility — spoken labels live on the surrounding controls. Two variants:
///
/// - `.pose`  — a full illustration with moment-specific, restrained breathing and inclination
///   (Reduce-Motion-safe, off-screen-paused). Used in hero/soft moments.
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
            companionPose
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

    private var companionPose: some View {
        let motion = Companion.motion(for: moment)
        return MotionTimeline(cadence: .decorative, paused: MotionQA.isStatic) { timeline, reduceMotion in
            let isStatic = reduceMotion || MotionQA.isStatic
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let angle = (elapsed / motion.period) * (.pi * 2) + motion.phase
            let breathWave = sin(angle)
            let attentionWave = sin(angle * 0.5 + motion.phase)

            Image(Companion.pose(for: moment))
                .resizable()
                .scaledToFit()
                .scaleEffect(
                    isStatic ? 1 : 1 + motion.breath * (0.5 + 0.5 * breathWave),
                    anchor: .bottom
                )
                .rotationEffect(
                    .degrees(isStatic ? 0 : motion.tiltDegrees * attentionWave),
                    anchor: .bottom
                )
                .offset(y: isStatic ? 0 : -motion.verticalTravel * breathWave)
        }
    }
}
