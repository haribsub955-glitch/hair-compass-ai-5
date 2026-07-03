import SwiftData
import SwiftUI

/// Per-treatment detail: refill tracking and tolerability. Both exist for one honest reason —
/// running low and side effects are the two most common reasons a regimen lapses. This sheet
/// keeps a record for the person's own prescriber conversations; it never gives medical advice.
struct TreatmentDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var treatment: Treatment

    @State private var showLogForm = false
    @State private var newType: SideEffectType = .scalpIrritation
    @State private var newSeverity: Int = 1
    @State private var newNote = ""

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    refillSection
                    tolerabilitySection
                    Text("A private record for your own prescriber conversations — not medical advice.")
                        .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle(treatment.name.isEmpty ? treatment.treatmentClass.title : treatment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: treatment.treatmentClass.symbol)
                .font(.system(size: 16)).foregroundStyle(Clinical.accent)
                .frame(width: 38, height: 38)
                .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(treatment.treatmentClass.title)\(treatment.dose.isEmpty ? "" : " · \(treatment.dose)")")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                Text("Started \(treatment.startDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
            }
            Spacer()
        }
    }

    // MARK: Refill

    private var refillRange: ClosedRange<Date> {
        let today = calendar.startOfDay(for: .now)
        let upper = calendar.date(byAdding: .day, value: 180, to: today) ?? today
        return today...max(today, upper)
    }

    private var refillSection: some View {
        section("Refill") {
            ClinicalCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    if treatment.refillBy != nil {
                        refillStatusLine
                        DateStripPicker(
                            selection: Binding(
                                get: { treatment.refillBy ?? .now },
                                set: { treatment.refillBy = $0 }
                            ),
                            range: refillRange
                        )
                        Button("Clear refill date") { treatment.refillBy = nil }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Clinical.secondary)
                            .buttonStyle(.plain)
                    } else {
                        Text("Note when your supply runs out — running low is the most common reason a routine lapses.")
                            .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Set a refill date") {
                            treatment.refillBy = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: .now))
                        }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var refillStatusLine: some View {
        let days = treatment.daysUntilRefill
        let urgency = HairAnalytics.refillUrgency(daysLeft: days)
        if let days {
            let (text, tint): (String, Color) = {
                switch urgency {
                case .overdue: return ("Refill overdue by \(-days) day\(days == -1 ? "" : "s")", Clinical.critical)
                case .urgent: return (days == 0 ? "Refill due today" : "Refill in \(days) day\(days == 1 ? "" : "s")", Clinical.warning)
                case .soon: return ("Refill in \(days) days", Clinical.warning)
                case .ok, .none: return ("Refill in \(days) days", Clinical.secondary)
                }
            }()
            Label(text, systemImage: "pills.circle")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
        }
    }

    // MARK: Tolerability

    private var sortedLogs: [SideEffectLog] {
        treatment.sideEffects.sorted { $0.date > $1.date }
    }

    private var tolerabilitySection: some View {
        section("Tolerability") {
            ClinicalCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    if sortedLogs.isEmpty && !showLogForm {
                        Text("Nothing logged. Side effects are the main reason people stop \(treatment.treatmentClass.title.lowercased()) — a dated record makes the conversation with your prescriber concrete.")
                            .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(sortedLogs) { log in logRow(log) }

                    if showLogForm {
                        logForm
                    } else {
                        Button("Log side effect") {
                            withAnimation(.easeOut(duration: 0.18)) { showLogForm = true }
                        }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                    }
                }
            }
        }
    }

    private func logRow(_ log: SideEffectLog) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: log.type.symbol)
                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                .frame(width: 28, height: 28)
                .background(Clinical.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(log.type.title)
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                    severityDots(log.severity)
                }
                Text(log.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                if !log.note.isEmpty {
                    Text(log.note).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                context.delete(log)
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Clinical.tertiary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    /// Three pips, filled to the severity, colored by band (mild sage · moderate ochre · severe brick).
    private func severityDots(_ severity: Int) -> some View {
        let band = SeverityBand(rawValue: min(max(severity, 1), 3) - 1) ?? .mild
        return HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i <= severity ? Clinical.bandColor(band) : Clinical.hairline)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("\(band.title) severity")
    }

    private var logForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "New side effect")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SideEffectType.allCases) { t in
                        let on = t == newType
                        Button {
                            newType = t
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Label(t.title, systemImage: t.symbol)
                                .font(.system(size: 13, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(on ? Clinical.ink : Clinical.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let caption = newType.caption {
                Text(caption).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
            }

            ClinicalSegmented(
                options: [1, 2, 3],
                label: { SeverityBand(rawValue: $0 - 1)?.title ?? "\($0)" },
                selection: $newSeverity
            )

            TextField("Note (optional)", text: $newNote)
                .font(.system(size: 15))
                .padding(11)
                .background(Clinical.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))

            HStack(spacing: 10) {
                Button("Cancel") {
                    withAnimation(.easeOut(duration: 0.18)) { showLogForm = false }
                }
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.secondary)
                .buttonStyle(.plain)
                Spacer()
                Button("Save") { saveLog() }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Clinical.surface)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Clinical.accent, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private func saveLog() {
        context.insert(SideEffectLog(
            treatment: treatment,
            type: newType,
            severity: newSeverity,
            date: .now,
            note: newNote.trimmingCharacters(in: .whitespaces)
        ))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        newType = .scalpIrritation
        newSeverity = 1
        newNote = ""
        withAnimation(.easeOut(duration: 0.18)) { showLogForm = false }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Eyebrow(text: title); content() }
    }
}
