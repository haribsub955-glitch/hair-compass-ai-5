import SwiftUI

/// No write until the user opens their plan. finish() seeds the real answers, then opens Plan.
struct StarterPlanFinale: View {
    let profile: Profile
    let onOpenPlan: () -> Void

    private var items: [StarterPlanItem] { StarterPlan.items(for: .fresh(profile: profile)) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    OnboardingIllustration(name: OnboardingArt.journal, height: 138)
                    VStack(alignment: .leading, spacing: 7) {
                        Eyebrow(text: "Your starting plan")
                        Text(profile.name.isEmpty ? "Ready when you are." : "Ready when you are, \(profile.name).")
                            .font(Clinical.headline(28))
                            .foregroundStyle(Clinical.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text("Your answers become your first check-in, not a diagnosis. Make a record, check the cause with a clinician, then agree on care. One step at a time.")
                            .font(Clinical.caption(14))
                            .foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    OnboardingPlanCards(items: OnboardingPlanSummary.items(from: items))
                    OnboardingPlanDetails(items: items)
                    Text(StarterPlan.safetyNote)
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.warning)
                    StarterPlanSources()
                    Text("Your plan lives on the Plan tab. It’s a starting point for your record and conversations with your clinician—not a treatment prescription.")
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            Button("Open my plan", action: onOpenPlan)
                .buttonStyle(ClinicalButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityIdentifier("onboardOpenPlan")
        }
    }
}
