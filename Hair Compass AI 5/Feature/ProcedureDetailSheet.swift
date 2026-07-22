import SwiftData
import SwiftUI

/// Per-appointment detail: the booked/logged procedure, a "Mark completed" action while it's
/// still pending, and delete. A private record for the user's own clinician conversations —
/// never medical advice, matching `TreatmentDetailSheet`'s framing.
struct ProcedureDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var appointment: ProcedureAppointment
    @State private var showEdit = false
    @State private var calendarFeedback: String?
    /// Consultation-only: presents `ExportSheet` so a doctor-visit appointment can hand off
    /// straight into the visit report the app already builds — the "see a dermatologist" loop's
    /// missing link.
    @State private var showExportSheet = false
    @State private var showAgenda = false
    /// Drives the delete confirmation dialog — confirm-first, matching every other irreversible
    /// delete in the app.
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if !appointment.type.art.isEmpty {
                        BrandBanner(art: appointment.type.art, height: 140)
                    }
                    header
                    if !appointment.isCompleted {
                        Button("Mark completed", action: markCompleted)
                            .buttonStyle(ClinicalButtonStyle())
                    }
                    if appointment.isUpcoming {
                        Button(action: addToCalendar) {
                            Label(calendarFeedback ?? "Add to Calendar",
                                  systemImage: calendarFeedback == nil ? "calendar.badge.plus" : "checkmark")
                                .font(Clinical.body(15, weight: .medium))
                        }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                        .disabled(calendarFeedback != nil)
                    }
                    if appointment.type == .consultation {
                        consultationAgendaCard
                        Button {
                            showExportSheet = true
                        } label: {
                            Label("Prepare visit report", systemImage: "doc.richtext")
                                .font(Clinical.body(15, weight: .medium))
                        }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                    }
                    if appointment.type == .transplant && appointment.isCompleted {
                        transplantTimelineCard
                    }
                    expectationsCard
                    deleteButton
                    Text("A private record for your own clinician conversations — not medical advice.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle(appointment.type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Edit") { showEdit = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showEdit) { AddProcedureSheet(existing: appointment) }
            .sheet(isPresented: $showAgenda) { VisitAgendaEditor(appointment: appointment) }
            .sheet(isPresented: $showExportSheet) { ExportSheet(consultation: appointment) }
            .confirmationDialog(
                "Delete this procedure record?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    context.delete(appointment)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    // MARK: Header

    private var consultationAgendaCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Visit agenda")
                Text(appointment.hasVisitAgenda
                     ? "Your editable talking points and questions are ready."
                     : "Capture what changed, what you want reviewed, and questions you don't want to forget.")
                    .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                Button(appointment.hasVisitAgenda ? "Edit agenda" : "Prepare agenda") { showAgenda = true }
                    .buttonStyle(ClinicalButtonStyle(filled: false))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: appointment.type.symbol)
                    .font(Clinical.caption(16)).foregroundStyle(Clinical.accent)
                    .frame(width: 38, height: 38)
                    .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(appointment.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()))
                        .font(Clinical.body(14, weight: .medium)).foregroundStyle(Clinical.ink)
                    Text(statusLine)
                        .font(Clinical.body(12, weight: .medium)).foregroundStyle(statusTint)
                }
                Spacer()
            }
            if !appointment.location.isEmpty {
                Label(appointment.location, systemImage: "mappin.and.ellipse")
                    .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
            }
            if !appointment.note.isEmpty {
                Text(appointment.note)
                    .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Education (expectations & aftercare)

    /// General orientation for this procedure type — what's typical to feel afterward, how
    /// results build, and when they're fair to judge. Education only, never directive; matches
    /// `TreatmentGuide`'s posture and the "private record, not medical advice" footer below.
    private var expectationsCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "What to expect")
                    Text(ProcedureGuide.expectations(for: appointment.type))
                        .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(Clinical.hairline)
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: appointment.type == .consultation ? "Before your visit" : "Typical aftercare")
                    ForEach(Array(ProcedureGuide.aftercareNotes(for: appointment.type).enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Clinical.accent).frame(width: 4, height: 4).padding(.top, 6)
                            Text(note).font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(appointment.type == .consultation
                         ? "General prep, not a checklist from your clinic — bring whatever they've asked for too."
                         : "Typical practice — always follow your clinic's own instructions.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Transplant-only: a "weeks since" recovery timeline anchored on the completion date,
    /// replacing the universal 24-week outcome gate with the much longer transplant-specific arc
    /// (`ProcedureGuide.transplantTimeline`) — graft security, shock loss, early regrowth,
    /// thickening, and the 12–18-month judging window.
    private var transplantTimelineCard: some View {
        let anchor = appointment.completedAt ?? appointment.date
        let weeks = HairAnalytics.weeksElapsed(since: anchor)
        let milestone = ProcedureGuide.transplantMilestone(weeksElapsed: weeks)
        let progress = min(1, Double(weeks) / Double(ProcedureGuide.transplantJudgingWindowWeeks))
        let inJudgingWindow = weeks >= 53

        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Recovery timeline")
                HStack {
                    Text("Week \(weeks) since your transplant")
                        .font(Clinical.number(13)).foregroundStyle(Clinical.ink)
                    Spacer()
                    Text(milestone.title)
                        .font(Clinical.eyebrow(11))
                        .foregroundStyle(inJudgingWindow ? Clinical.positive : Clinical.accent)
                }
                ProgressBar(value: progress, tint: inJudgingWindow ? Clinical.positive : Clinical.accent)
                    .frame(height: 8)
                Text(milestone.body)
                    .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusLine: String {
        if appointment.isCompleted {
            let done = appointment.completedAt ?? appointment.date
            return "Completed \(done.formatted(date: .abbreviated, time: .omitted))"
        }
        return appointment.isUpcoming ? "Upcoming" : "Past · not marked done"
    }
    private var statusTint: Color {
        if appointment.isCompleted { return Clinical.positive }
        return appointment.isUpcoming ? Clinical.accent : Clinical.warning
    }

    // MARK: Actions

    private func markCompleted() {
        appointment.isCompleted = true
        appointment.completedAt = .now
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func addToCalendar() {
        Task {
            switch await CalendarService.addProcedure(
                title: appointment.type.title,
                date: appointment.date,
                location: appointment.location,
                notes: appointment.note
            ) {
            case .added:
                calendarFeedback = "Added to Calendar"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .denied:
                calendarFeedback = "Calendar access is off"
            case .failed:
                calendarFeedback = "Couldn't add it"
            }
        }
    }

    /// Hand-drawn destructive style (matches `PhotoDetailView.deleteButton`) rather than
    /// `ClinicalButtonStyle(filled: false)`, which hard-codes its label to `Clinical.ink` and
    /// would bury the destructive intent.
    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete procedure", systemImage: "trash")
                .font(Clinical.body(16, weight: .semibold))
                .foregroundStyle(Clinical.critical)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Clinical.surface)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Clinical.critical.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Consultation-only, user-owned checklist. Suggestions are neutral prompts derived entirely
/// from existing records; they never interpret a condition or recommend a treatment change.
private struct VisitAgendaEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query private var treatments: [Treatment]
    @Query private var sideEffects: [SideEffectLog]
    @Query private var labs: [LabResult]
    @Bindable var appointment: ProcedureAppointment

    @State private var mainConcern: String
    @State private var changedWhen: String
    @State private var treatmentsToReview: String
    @State private var safetyConcerns: String
    @State private var questions: [String]
    @State private var newQuestion = ""

    init(appointment: ProcedureAppointment) {
        self.appointment = appointment
        _mainConcern = State(initialValue: appointment.agendaMainConcern)
        _changedWhen = State(initialValue: appointment.agendaChangedWhen)
        _treatmentsToReview = State(initialValue: appointment.agendaTreatmentsToReview)
        _safetyConcerns = State(initialValue: appointment.agendaSafetyConcerns)
        _questions = State(initialValue: appointment.agendaQuestions)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    agendaField("My main concern", text: $mainConcern)
                    agendaField("What changed and when", text: $changedWhen)
                    agendaField("Treatments I want reviewed", text: $treatmentsToReview)
                    agendaField("Side effects or safety concerns", text: $safetyConcerns)
                    questionsSection
                    Text("Suggestions organize your own records and neutral questions. They are not medical advice.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Visit agenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear { if questions.isEmpty { questions = suggestedQuestions } }
        }
    }

    private func agendaField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
            TextField("Add your notes", text: text, axis: .vertical)
                .font(Clinical.body(14)).foregroundStyle(Clinical.ink).lineLimit(2...5)
                .padding(12).background(Clinical.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Clinical.hairline))
        }
    }

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Questions I don't want to forget")
            ForEach(Array(questions.enumerated()), id: \.offset) { index, _ in
                HStack(alignment: .top) {
                    TextField("Question", text: $questions[index], axis: .vertical)
                        .font(Clinical.body(14)).foregroundStyle(Clinical.ink)
                    Button { questions.remove(at: index) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Clinical.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(11).background(Clinical.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                TextField("Add a question", text: $newQuestion)
                    .font(Clinical.body(14)).textFieldStyle(.plain)
                Button("Add", action: addQuestion).disabled(newQuestion.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(11).background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("Suggested from your records — fully editable")
                .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
        }
    }

    private var suggestedQuestions: [String] {
        var result: [String] = []
        if entries.prefix(7).filter({ $0.shed == .heavy }).count >= 3 {
            result.append("My records show persistent heavy shedding. What context would be useful to review?")
        }
        if sideEffects.contains(where: { $0.severity >= 3 }) {
            result.append("I recorded a severe side effect. What should we review together?")
        }
        if labs.contains(where: { $0.flag != .normal }) {
            result.append("I have a lab result outside its recorded reference range. How does it fit my overall history?")
        }
        if profiles.first?.pregnancyStatus.flagsMedicationCaution == true {
            result.append("What pregnancy or breastfeeding context is relevant to reviewing my current plan?")
        }
        if !treatments.isEmpty {
            result.append("Can we review the treatments and dates in my record?")
        }
        result.append("What would count as success at my next review?")
        return result
    }

    private func addQuestion() {
        let value = newQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        questions.append(value)
        newQuestion = ""
    }

    private func save() {
        appointment.agendaMainConcern = mainConcern.trimmingCharacters(in: .whitespacesAndNewlines)
        appointment.agendaChangedWhen = changedWhen.trimmingCharacters(in: .whitespacesAndNewlines)
        appointment.agendaTreatmentsToReview = treatmentsToReview.trimmingCharacters(in: .whitespacesAndNewlines)
        appointment.agendaSafetyConcerns = safetyConcerns.trimmingCharacters(in: .whitespacesAndNewlines)
        appointment.agendaQuestions = questions
        dismiss()
    }
}
