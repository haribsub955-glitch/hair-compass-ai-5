import SwiftData
import SwiftUI

/// Per-treatment detail: refill tracking and tolerability. Both exist for one honest reason —
/// running low and side effects are the two most common reasons a regimen lapses. This sheet
/// keeps a record for the person's own prescriber conversations; it never gives medical advice.
struct TreatmentDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var treatment: Treatment
    /// Set by callers that already know the user wants to log a side effect (e.g. LogSheet's
    /// "Log a side effect" shortcut) so the form is open on first appearance instead of one more
    /// tap away.
    var startWithLogForm = false

    // Everything a per-treatment progress report needs — this sheet doesn't otherwise touch
    // most of these, but `ProgressReport.build` is a pure app-wide synthesis, not something
    // scoped to a single Treatment's own relationships.
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query private var allTreatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query private var labs: [LabResult]
    @Query private var sideEffectLogs: [SideEffectLog]
    @Query private var triggerEvents: [TriggerEvent]
    @Query(sort: \PhotoRecord.createdAt) private var photoRecords: [PhotoRecord]

    @State private var showLogForm = false
    @State private var newType: SideEffectType = .scalpIrritation
    @State private var newSeverity: Int = 1
    @State private var newNote = ""
    /// Side effects are often noticed and recalled days later — defaults to today but is
    /// backdatable, same ~30-day-back idiom `LogSheet`'s `DateStripPicker` already uses for
    /// backfill, so a late entry doesn't get mis-dated or skipped.
    @State private var newDate = Date.now
    @State private var showReport = false

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    whatToExpectCard
                    if let report = treatmentReport { progressReportRow(report) }
                    scheduleSection
                    refillSection
                    ingredientsSection
                    tolerabilitySection
                    Text("A private record for your own prescriber conversations — not medical advice.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle(treatment.name.isEmpty ? treatment.treatmentClass.title : treatment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if startWithLogForm { showLogForm = true }
            }
            .sheet(isPresented: $showReport) {
                if let report = treatmentReport { ProgressReportSheet(report: report, photos: photoRecords) }
            }
        }
    }

    /// This treatment's own progress report — focused via `ProgressReport.build(focus:)` so a
    /// treatment added well after another one gets its own week clock and honest read instead of
    /// reusing whichever treatment happens to be earliest (round-5 fix).
    private var treatmentReport: ProgressReport? {
        ProgressReport.build(
            entries: entries, treatments: allTreatments, doses: doses,
            labs: labs, sideEffects: sideEffectLogs, triggers: triggerEvents,
            focus: treatment
        )
    }

    private func progressReportRow(_ report: ProgressReport) -> some View {
        Button { showReport = true } label: {
            ClinicalCard(padding: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(Clinical.caption(15)).foregroundStyle(Clinical.accent)
                        .frame(width: 34, height: 34)
                        .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Progress report").font(Clinical.body(14, weight: .semibold)).foregroundStyle(Clinical.ink)
                        Text("Week \(report.weekNumber) · this treatment's own trajectory")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: treatment.treatmentClass.symbol)
                .font(Clinical.caption(16)).foregroundStyle(Clinical.accent)
                .frame(width: 38, height: 38)
                .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(treatment.treatmentClass.title)\(treatment.dose.isEmpty ? "" : " · \(treatment.dose)")")
                    .font(Clinical.body(14, weight: .medium)).foregroundStyle(Clinical.ink)
                Text("Started \(treatment.startDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
            }
            Spacer()
        }
    }

    // MARK: What to expect

    /// General orientation for this treatment's class — what's typical in the early weeks, how
    /// results build, and when it's fair to judge — plus a week-anchored phase line where there's
    /// a distinct one to call out (minoxidil's early shed, an SRI's slow onset), and a thin
    /// progress bar to the app's 24-week judging point: the same clock `AddTreatmentSheet` sets
    /// and `CareView`/`ProgressReport` already judge every treatment against. Mirrors
    /// `ProcedureDetailSheet.expectationsCard`/`.transplantTimelineCard`'s posture: education, not
    /// a reason to start or stop anything.
    private var whatToExpectCard: some View {
        let weeks = HairAnalytics.weeksElapsed(since: treatment.startDate)
        let progress = HairAnalytics.outcomeProgress(weeksElapsed: weeks)
        let ready = HairAnalytics.outcomeReady(weeksElapsed: weeks)
        let weeksToGo = max(0, HairAnalytics.outcomeWindowWeeks - weeks)

        return ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "What to expect")
                    Text(TreatmentGuide.expectations(for: treatment.treatmentClass))
                        .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(Clinical.hairline)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Week \(weeks) since starting")
                            .font(Clinical.number(13)).foregroundStyle(Clinical.ink)
                        Spacer()
                        Text(ready ? "24-week checkpoint reached" : "\(weeksToGo) week\(weeksToGo == 1 ? "" : "s") to the 24-week checkpoint")
                            .font(Clinical.eyebrow(11))
                            .foregroundStyle(ready ? Clinical.positive : Clinical.accent)
                    }
                    ProgressBar(value: progress, tint: ready ? Clinical.positive : Clinical.accent)
                        .frame(height: 8)
                    if let phase = TreatmentGuide.phase(for: treatment.treatmentClass, weeksElapsed: weeks) {
                        Text(phase)
                            .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Schedule (weekday cadence)

    /// Editable weekday cadence for the periodic classes with a real weekly-ish rhythm — the
    /// care products plus the home-use devices (microneedling, LLLT). This is the only place the
    /// cadence can be fixed after creation: `AddTreatmentSheet` sets it once at add time, but a
    /// wrong or empty selection there (empty reads as "every day" to `isDueToday()`) previously
    /// had no way back short of deleting and re-adding the treatment.
    @ViewBuilder
    private var scheduleSection: some View {
        if treatment.treatmentClass.supportsWeekdaySchedule {
            section("Days") {
                ClinicalCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        WeekdaySchedulePicker(selection: Binding(
                            get: { treatment.scheduledWeekdays },
                            set: { treatment.scheduledWeekdays = $0 }
                        ))
                        if let hint = TreatmentGuide.scheduleHint(for: treatment.treatmentClass) {
                            Text(hint)
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        }
                        Text(treatment.scheduledWeekdays.isEmpty
                             ? "Every day. Tap days to use it only on those."
                             : "Shows in your routine on the selected days.")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }
                }
            }
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
                            .font(Clinical.body(13, weight: .medium))
                            .foregroundStyle(Clinical.secondary)
                            .buttonStyle(.plain)
                    } else {
                        Text("Note when your supply runs out — running low is the most common reason a routine lapses.")
                            .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
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
                .font(Clinical.body(13, weight: .medium)).foregroundStyle(tint)
        }
    }

    // MARK: Ingredients (custom items with an AI-identified label photo)

    /// Only present when a photo was attached at add time (see `AddTreatmentSheet`) — most
    /// treatments from the evidence library never set these fields, so the section disappears.
    @ViewBuilder
    private var ingredientsSection: some View {
        if !treatment.ingredientPhotoPath.isEmpty || !treatment.aiIngredientSummary.isEmpty {
            section("Ingredients") {
                ClinicalCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !treatment.ingredientPhotoPath.isEmpty,
                           let thumbnail = PhotoStore.shared.loadThumbnail(treatment.ingredientPhotoPath) {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                        }
                        if !treatment.aiIngredientSummary.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(treatment.aiIngredientSummary)
                                    .font(Clinical.caption(13)).foregroundStyle(Clinical.ink)
                                Text("AI summary · not medical advice")
                                    .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                            }
                        }
                    }
                }
            }
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
                            .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
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
                .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                .frame(width: 28, height: 28)
                .background(Clinical.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(log.type.title)
                        .font(Clinical.body(14, weight: .medium)).foregroundStyle(Clinical.ink)
                    severityDots(log.severity)
                }
                Text(log.date.formatted(date: .abbreviated, time: .omitted))
                    .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                if !log.note.isEmpty {
                    Text(log.note).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                context.delete(log)
            } label: {
                Image(systemName: "xmark").font(Clinical.body(10, weight: .semibold)).foregroundStyle(Clinical.tertiary)
                    .frame(width: 24, height: 24)
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Delete this entry")
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
                                .font(Clinical.body(13, weight: on ? .semibold : .regular))
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
                Text(caption).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
            }

            DateStripPicker(selection: $newDate, range: sideEffectDateRange)

            ClinicalSegmented(
                options: [1, 2, 3],
                label: { SeverityBand(rawValue: $0 - 1)?.title ?? "\($0)" },
                selection: $newSeverity
            )

            TextField("Note (optional)", text: $newNote)
                .font(Clinical.caption(15))
                .padding(11)
                .background(Clinical.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))

            HStack(spacing: 10) {
                Button("Cancel") {
                    withAnimation(.easeOut(duration: 0.18)) { showLogForm = false }
                }
                .font(Clinical.body(14, weight: .medium)).foregroundStyle(Clinical.secondary)
                .buttonStyle(.plain)
                Spacer()
                Button("Save") { saveLog() }
                    .font(Clinical.body(14, weight: .semibold)).foregroundStyle(Clinical.surface)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Clinical.accent, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    /// 30 days back (recalled-late entries) through today — never the future.
    private var sideEffectDateRange: ClosedRange<Date> {
        let today = calendar.startOfDay(for: .now)
        let lower = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        return lower...today
    }

    private func saveLog() {
        context.insert(SideEffectLog(
            treatment: treatment,
            type: newType,
            severity: newSeverity,
            date: newDate,
            note: newNote.trimmingCharacters(in: .whitespaces)
        ))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        newType = .scalpIrritation
        newSeverity = 1
        newNote = ""
        newDate = .now
        withAnimation(.easeOut(duration: 0.18)) { showLogForm = false }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Eyebrow(text: title); content() }
    }
}
