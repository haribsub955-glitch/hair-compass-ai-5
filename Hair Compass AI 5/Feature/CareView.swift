import SwiftData
import SwiftUI

struct CareView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]

    @State private var showAdd = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Regimen",
                    title: "Care",
                    trailing: AnyView(
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Clinical.surface)
                                .frame(width: 34, height: 34)
                                .background(Clinical.ink, in: Circle())
                        }
                    )
                ).padding(.top, 8)

                gateExplainer

                if treatments.isEmpty {
                    empty
                } else {
                    ForEach(treatments) { t in treatmentCard(t) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .clinicalScreen()
        .sheet(isPresented: $showAdd) { AddTreatmentSheet() }
    }

    private var gateExplainer: some View {
        ClinicalCard(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 16)).foregroundStyle(Clinical.accent)
                Text("Hair-density change is judged at 24 weeks in clinical trials. Each treatment shows its progress toward that milestone — resist judging sooner.")
                    .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
            }
        }
    }

    private var empty: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "No treatments")
                Text("Add minoxidil, finasteride, or a procedure to track adherence and the 24-week window.")
                    .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                Button("Add treatment") { showAdd = true }
                    .buttonStyle(ClinicalButtonStyle())
                    .padding(.top, 4)
            }
        }
    }

    private func treatmentCard(_ t: Treatment) -> some View {
        let weeks = HairAnalytics.weeksElapsed(since: t.startDate)
        let progress = HairAnalytics.outcomeProgress(weeksElapsed: weeks)
        let ready = HairAnalytics.outcomeReady(weeksElapsed: weeks)
        let dates = doses.filter { $0.treatment?.persistentModelID == t.persistentModelID }.map(\.loggedAt)
        let adherence = HairAnalytics.adherence(doseDates: dates, expectedPerDay: t.treatmentClass.defaultDailyCount)

        return ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: t.treatmentClass.symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(Clinical.accent)
                        .frame(width: 38, height: 38)
                        .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Clinical.ink)
                        Text("\(t.treatmentClass.title)\(t.dose.isEmpty ? "" : " · \(t.dose)")")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }
                    Spacer()
                    Menu {
                        Button(t.isActive ? "Mark inactive" : "Reactivate") { t.isActive.toggle() }
                        Button("Delete", role: .destructive) { context.delete(t) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(Clinical.tertiary)
                            .frame(width: 30, height: 30)
                    }
                }

                // 24-week gate
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Week \(weeks) of \(HairAnalytics.outcomeWindowWeeks)")
                            .font(Clinical.number(13)).foregroundStyle(Clinical.ink)
                        Spacer()
                        Text(ready ? "Ready to assess" : "Too early to judge")
                            .font(Clinical.eyebrow(11))
                            .foregroundStyle(ready ? Clinical.positive : Clinical.tertiary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Clinical.canvas)
                            Capsule().fill(ready ? Clinical.positive : Clinical.accent)
                                .frame(width: max(6, geo.size.width * progress))
                        }
                    }
                    .frame(height: 8)
                }

                if let adherence {
                    HStack {
                        Text("14-day adherence").font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        Spacer()
                        Text("\(Int((adherence * 100).rounded()))%")
                            .font(Clinical.number(13))
                            .foregroundStyle(adherence >= 0.8 ? Clinical.positive : Clinical.warning)
                    }
                } else {
                    Text("Periodic treatment · logged per session")
                        .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                }

                if !t.isActive {
                    Text("Inactive").font(Clinical.eyebrow(10)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
        .opacity(t.isActive ? 1 : 0.6)
    }
}
