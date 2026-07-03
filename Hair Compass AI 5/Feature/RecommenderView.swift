import SwiftUI

/// Evidence-ranked options for the user's stated pattern — education, never a prescription. A
/// disclaimer sits up front and every option carries a "confirm with a clinician" note.
struct RecommenderView: View {
    let condition: HairCondition
    let sex: BiologicalSex

    private var options: [RecommendedOption] { TreatmentRecommender.options(condition: condition, sex: sex) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Guidance", title: "What helps").padding(.top, 8)

                ClinicalCard(padding: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "stethoscope").font(.system(size: 15)).foregroundStyle(Clinical.accent)
                        Text(TreatmentRecommender.disclaimer)
                            .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                    }
                }

                Text(TreatmentRecommender.headline(condition: condition))
                    .font(Clinical.headline(20)).foregroundStyle(Clinical.ink)
                Text("Based on your baseline: \(condition.title.lowercased()). Change it in your baseline if that's not right.")
                    .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)

                ForEach(options) { option in
                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(option.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.ink)
                                Spacer()
                                TierBadge(tier: option.tier)
                            }
                            Text(option.summary).font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                            note(icon: "stethoscope", option.clinicianNote, color: Clinical.accent)
                            if let caution = option.caution {
                                note(icon: "exclamationmark.triangle", caution, color: Clinical.warning)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .clinicalScreen()
    }

    private func note(icon: String, _ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color).padding(.top, 1)
            Text(text).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
        }
    }
}
