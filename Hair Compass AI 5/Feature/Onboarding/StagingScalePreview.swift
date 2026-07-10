import SwiftUI

/// The sex-linked staging scale, shown as a generated illustration (Higgsfield gouache, matching
/// the Clinical ivory/copper palette) rather than a schematic — a top-down male head with Norwood
/// M-recession + crown wash, or a top-down female head with a widening Ludwig part. This
/// illustrates the measurement pattern only — it is not a prediction and not the user's own stage.
struct StagingScalePreview: View {
    let sex: BiologicalSex
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isLudwig: Bool { sex == .female }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Image("onboard-pattern-male")
                    .resizable().scaledToFill()
                    .opacity(isLudwig ? 0 : 1)
                Image("onboard-pattern-female")
                    .resizable().scaledToFill()
                    .opacity(isLudwig ? 1 : 0)
            }
            .frame(width: 168, height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
            .shadow(color: Clinical.cardShadow, radius: 10, y: 4)

            VStack(spacing: 3) {
                Text("\(sex.stagingScaleName.uppercased()) SCALE")
                    .font(Clinical.eyebrow(10)).tracking(1.4).foregroundStyle(Clinical.accent)
                Text(isLudwig ? "Thinning shows as a widening part" : "Thinning shows at the hairline and crown")
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isLudwig)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        StagingScalePreview(sex: .male)
        StagingScalePreview(sex: .female)
    }
    .padding()
    .background(Clinical.canvas)
}
