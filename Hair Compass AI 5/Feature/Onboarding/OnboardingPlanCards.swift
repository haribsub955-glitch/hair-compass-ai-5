import SwiftUI

/// The same three real next steps expand on the plan and settle into a compact bookmark on
/// the preview/offer. Stable view identity does the work; neither the titles nor prices slide.
struct OnboardingPlanCards: View {
    let items: [StarterPlanItem]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 8) {
            if compact {
                Eyebrow(text: "Your next steps")
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 11) {
                    Text(String(format: "%02d", index + 1))
                        .font(Clinical.eyebrow(11))
                        .foregroundStyle(Clinical.accent)
                        .frame(width: 26, height: compact ? 20 : 28)
                        .background(compact ? .clear : Clinical.accentSoft, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(Clinical.body(compact ? 12 : 15, weight: .medium))
                            .foregroundStyle(Clinical.ink)
                        if !compact {
                            Text(item.why)
                                .font(Clinical.caption(12))
                                .foregroundStyle(Clinical.secondary)
                                .transition(.opacity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, compact ? 5 : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(compact ? .clear : Clinical.surface, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    if !compact {
                        RoundedRectangle(cornerRadius: 17).strokeBorder(Clinical.hairline, lineWidth: 1)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboardPlanItem.\(item.id)")
            }
        }
        .padding(.bottom, compact ? 10 : 0)
        .background(compact ? Clinical.surface : .clear, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            if compact {
                RoundedRectangle(cornerRadius: 18).strokeBorder(Clinical.hairline, lineWidth: 1)
            }
        }
    }
}

/// Read-only clinical detail is kept available rather than replaced with sales copy.
struct OnboardingPlanDetails: View {
    let items: [StarterPlanItem]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(StarterPlanGroup.allCases) { group in
                    let rows = items.filter { $0.group == group }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: group.eyebrow)
                            ForEach(rows) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(Clinical.body(14, weight: .medium))
                                        .foregroundStyle(Clinical.ink)
                                    Text(item.why)
                                        .font(Clinical.caption(12))
                                        .foregroundStyle(Clinical.secondary)
                                    if let caution = item.caution {
                                        Text(caution)
                                            .font(Clinical.caption(12))
                                            .foregroundStyle(Clinical.warning)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Text(StarterPlan.disclaimer)
                    .font(Clinical.caption(11))
                    .foregroundStyle(Clinical.secondary)
            }
            .padding(.vertical, 12)
        } label: {
            Text("Explore your full starting plan")
                .font(Clinical.body(13, weight: .medium))
                .foregroundStyle(Clinical.ink)
        }
        .tint(Clinical.accent)
        .accessibilityIdentifier("onboardPlanDetails")
    }
}

enum OnboardingArt {
    static let journal = "onboarding-plan-journal"
    static let support = "onboarding-wren-support"
}

struct OnboardingIllustration: View {
    let name: String
    var height: CGFloat = 132

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
