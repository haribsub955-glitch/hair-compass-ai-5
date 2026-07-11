import SwiftData
import SwiftUI

/// The full procedures list — booked/upcoming appointments and a completed history. Reached
/// from the Plan tab's Procedures card; presented as its own sheet (the app's secondary
/// navigation is sheet-based, see `AddTreatmentSheet`), so it wraps its own `NavigationStack`
/// with a "Done" dismiss, mirroring how `CareView` wraps `RecommenderView`.
struct ProceduresView: View {
    @Query(sort: \ProcedureAppointment.date) private var appointments: [ProcedureAppointment]

    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var detail: ProcedureAppointment?

    private var upcoming: [ProcedureAppointment] { appointments.filter(\.isUpcoming) }
    private var done: [ProcedureAppointment] { appointments.filter { !$0.isUpcoming }.sorted { $0.date > $1.date } }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(
                        eyebrow: "Booked & completed",
                        title: "Procedures",
                        trailing: AnyView(
                            HeaderActionButton(systemName: "plus", accessibilityLabel: "Add procedure") {
                                showAdd = true
                            }
                        )
                    )
                    .padding(.top, 8)

                    if appointments.isEmpty {
                        empty
                    } else {
                        if !upcoming.isEmpty {
                            section("Upcoming") {
                                ForEach(upcoming) { appt in row(appt) }
                            }
                        }
                        if !done.isEmpty {
                            section("Done") {
                                ForEach(done) { appt in row(appt) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .clinicalScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showAdd) { AddProcedureSheet() }
            .sheet(item: $detail) { ProcedureDetailSheet(appointment: $0) }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("HC_ADDPROCEDURE") { showAdd = true }
                #endif
            }
        }
    }

    private var empty: some View {
        ClinicalCard {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 32)).foregroundStyle(Clinical.accent)
                Eyebrow(text: "No procedures")
                Text("Book PRP, microneedling, or another in-clinic procedure to get a reminder the day before and track it here.")
                    .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                    .multilineTextAlignment(.center)
                Button("Add procedure") { showAdd = true }
                    .buttonStyle(ClinicalButtonStyle())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Eyebrow(text: title); content() }
    }

    private func row(_ appt: ProcedureAppointment) -> some View {
        Button { detail = appt } label: {
            ClinicalCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: appt.type.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(appt.isCompleted ? Clinical.secondary : Clinical.accent)
                        .frame(width: 34, height: 34)
                        .background(appt.isCompleted ? Clinical.hairline : Clinical.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appt.type.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                        Text(subtitle(appt)).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }
                    Spacer()
                    if appt.isCompleted {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Clinical.positive)
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ appt: ProcedureAppointment) -> String {
        let when = appt.date.formatted(date: .abbreviated, time: .shortened)
        return appt.location.isEmpty ? when : "\(when) · \(appt.location)"
    }
}
