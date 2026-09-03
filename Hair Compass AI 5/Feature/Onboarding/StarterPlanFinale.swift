//
//  StarterPlanFinale.swift
//  Hair Compass AI 5
//
//  Onboarding's last screen: the starting plan as a read-only preview — the same items the Plan
//  tab will show as a checklist a moment later (`StarterPlan.Snapshot.fresh` ↔ `.make` parity is
//  tested). Nothing here writes to the record; "Open my plan" hands over to the tab.
//

import SwiftUI

struct StarterPlanFinale: View {
    let profile: Profile
    let onOpenPlan: () -> Void

    private var items: [StarterPlanItem] {
        StarterPlan.items(for: .fresh(profile: profile))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Your starting plan")
                        Text(profile.name.isEmpty ? "Here's where to begin" : "Here's where to begin, \(profile.name)")
                            .font(Clinical.headline(28))
                            .foregroundStyle(Clinical.ink)
                        Text("Built from your answers. It lives on the Plan tab as a checklist — nothing here is decided for you.")
                            .font(Clinical.caption(14))
                            .foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 24)

                    ForEach(StarterPlanGroup.allCases) { group in
                        let rows = items.filter { $0.group == group }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Eyebrow(text: group.eyebrow).padding(.bottom, 4)
                                Divider().overlay(Clinical.hairline)
                                ForEach(rows) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(Clinical.body(15, weight: .medium))
                                            .foregroundStyle(Clinical.ink)
                                        Text(item.why)
                                            .font(Clinical.caption(12))
                                            .foregroundStyle(Clinical.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Divider().overlay(Clinical.hairline)
                                }
                            }
                        }
                    }

                    Text(TreatmentRecommender.disclaimer)
                        .font(Clinical.caption(11))
                        .foregroundStyle(Clinical.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 24)
            }

            Button("Open my plan", action: onOpenPlan)
                .buttonStyle(ClinicalButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .accessibilityIdentifier("onboardOpenPlan")
        }
        .accessibilityIdentifier("starterPlanFinale")
    }
}
