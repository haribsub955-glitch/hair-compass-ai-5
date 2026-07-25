import SwiftUI

/// The "what are you noticing?" choice, as a grid of illustrated cards rather than a list of
/// clinical names.
///
/// This is the screen where the app asks someone to classify something they may never have had
/// words for, and six text rows made that a reading comprehension test. Each pattern has a
/// characteristic *look*, so the picture carries the identification and the words confirm it —
/// recognition instead of vocabulary. The gouache vignettes keep the app's own hand rather than
/// borrowing clinical photography, which on this subject reads as cold and, for a lot of people,
/// frightening.
///
/// Honesty boundary: these illustrate what each pattern *looks like* so a person can find
/// themselves in the list. Choosing one is self-identification for tracking purposes, never a
/// diagnosis — which is why the clinical name stays visible and demoted underneath, and why the
/// footnote below the grid says so plainly.
struct ConditionPicker: View {
    @Binding var selection: HairCondition

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Two across normally. At accessibility sizes a half-width card can't hold a wrapped title
    /// plus a clinical name, so the grid becomes a single column of wide cards.
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(HairCondition.allCases) { condition in
                    card(condition)
                }
            }

            Text("Pick the closest match — this only sets what the app tracks and compares. It isn't a diagnosis, and you can change it whenever you like.")
                .font(Clinical.caption(11))
                .foregroundStyle(Clinical.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func card(_ condition: HairCondition) -> some View {
        let on = selection == condition
        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                       : .spring(response: 0.34, dampingFraction: 0.75)) {
                selection = condition
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(condition.art)
                    .resizable()
                    .scaledToFill()
                    .frame(height: typeSize.isAccessibilitySize ? 120 : 104)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .background(Clinical.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if on {
                            Image(systemName: "checkmark.circle.fill")
                                .font(Clinical.body(18, weight: .semibold))
                                .foregroundStyle(Clinical.accent)
                                .background(Clinical.surface, in: Circle())
                                .padding(6)
                                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        }
                    }
                    .padding(6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(condition.plainTitle)
                        .font(Clinical.headline(15))
                        .foregroundStyle(Clinical.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // The clinical name stays present but demoted — the app never hides the real
                    // term, it just refuses to make it the thing you have to recognise.
                    Text(condition.title.uppercased())
                        .font(Clinical.eyebrow(9))
                        .tracking(1.0)
                        .foregroundStyle(Clinical.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 2)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(on ? Clinical.accentSoft : Clinical.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(on ? Clinical.accent : Clinical.hairline, lineWidth: on ? 2 : 1)
            )
            .shadow(color: on ? Clinical.accent.opacity(0.16) : Clinical.cardShadow,
                    radius: on ? 10 : 6, y: on ? 4 : 2)
            .scaleEffect(on && !reduceMotion ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(condition.plainTitle). \(condition.title).")
        .accessibilityValue(on ? "Selected" : "Not selected")
        .accessibilityHint(condition.plainSummary)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
