import SwiftUI

/// Evidence-ranked options for the user's stated pattern — education, never a prescription. A
/// disclaimer sits up front and every option carries a "confirm with a clinician" note.
///
/// Section-shaped, not screen-shaped. This used to be its own sheet destination — own
/// `ScrollView`, own `ScreenHeader`, own `.clinicalScreen()` — presented from `CareView`. It now
/// lives inline inside `ShopView`'s single scroll, so it owns none of that chrome any more:
/// `ShopView` is the page (header, canvas, scroll, `BrandWash`), this is just one of its sections.
/// A `ScrollView` nested in `ShopView`'s own `ScrollView` would fight it for the vertical pan and
/// could strand `ScienceProductsSection` below it — see the Task 9 fix-round notes.
struct RecommenderView: View {
    let condition: HairCondition
    let sex: BiologicalSex
    var onAction: (RecommendedAction) -> Void = { _ in }

    private var options: [RecommendedOption] { TreatmentRecommender.options(condition: condition, sex: sex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClinicalCard(padding: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "stethoscope").font(Clinical.caption(15)).foregroundStyle(Clinical.accent)
                    Text(TreatmentRecommender.disclaimer)
                        .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                }
            }

            Text(TreatmentRecommender.headline(condition: condition))
                .font(Clinical.headline(20)).foregroundStyle(Clinical.ink)
            Text("Based on your baseline: \(condition.title.lowercased()). Change it in your baseline if that's not right.")
                .font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)

            ForEach(options) { option in
                ClinicalCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(option.name).font(Clinical.body(15, weight: .semibold)).foregroundStyle(Clinical.ink)
                            Spacer()
                            TierBadge(tier: option.tier)
                        }
                        Text(option.summary).font(Clinical.caption(14)).foregroundStyle(Clinical.secondary)
                        note(icon: "stethoscope", option.clinicianNote, color: Clinical.accent)
                        if let caution = option.caution {
                            note(icon: "exclamationmark.triangle", caution, color: Clinical.warning)
                        }
                        if let action = option.action {
                            Button(action.title) { onAction(action) }
                                .buttonStyle(ClinicalButtonStyle(filled: false))
                                .padding(.top, 3)
                        }
                    }
                }
            }
        }
    }

    private func note(icon: String, _ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(Clinical.caption(12)).foregroundStyle(color).padding(.top, 1)
            Text(text).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
        }
    }
}
