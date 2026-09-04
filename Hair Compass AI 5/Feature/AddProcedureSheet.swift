import SwiftData
import SwiftUI

/// Books a `ProcedureAppointment` — PRP, microneedling, a transplant, LLLT, mesotherapy, or a
/// custom "other" procedure. Same Clinical form idiom as `AddTreatmentSheet`/`AddLabSheet`: a
/// chip picker, a date strip, a compact time picker, two optional text fields, one save button.
struct AddProcedureSheet: View {
    /// nil = booking a new procedure; non-nil = editing that one in place (same form, prefilled).
    var existing: ProcedureAppointment?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var type: ProcedureType
    @State private var date: Date
    @State private var time: Date
    @State private var location: String
    @State private var note: String

    init(existing: ProcedureAppointment? = nil, initialType: ProcedureType = .prp) {
        self.existing = existing
        // The date-strip day and the time picker both read the one stored instant.
        let instant = existing?.date ?? .now
        _type = State(initialValue: existing?.type ?? initialType)
        _date = State(initialValue: instant)
        _time = State(initialValue: instant)
        _location = State(initialValue: existing?.location ?? "")
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section("Type") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ProcedureType.allCases) { t in
                                    let on = t == type
                                    Button { type = t } label: {
                                        Label(t.title, systemImage: t.symbol)
                                            .font(Clinical.body(14, weight: on ? .semibold : .regular))
                                            .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                                            .padding(.horizontal, 13).padding(.vertical, 9)
                                            .background(on ? Clinical.ink : Clinical.surface)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Text(ProcedureGuide.shortExpectation(for: type))
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    section("Date") {
                        DateStripPicker(selection: $date, range: dateRange)
                    }

                    section("Time") {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .font(Clinical.caption(13))
                            .tint(Clinical.accent)
                    }

                    section("Location (optional)") {
                        textField("e.g. Downtown clinic", text: $location)
                    }

                    section("Note (optional)") {
                        textField("Anything worth remembering", text: $note)
                    }

                    if type == .consultation {
                        Text("This saves an appointment in your record. Contact the clinic yourself to book it.")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }
                    Button(existing == nil ? (type == .consultation ? "Save appointment" : "Add procedure") : "Save changes", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle(existing == nil ? (type == .consultation ? "Clinician visit" : "New procedure") : "Edit procedure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    /// Six months back (logging an already-done procedure) through a year ahead (booking
    /// something scheduled far out, e.g. a transplant) — wider than the daily-treatment strip.
    private var dateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        let lower = Calendar.current.date(byAdding: .month, value: -6, to: today) ?? today
        let upper = Calendar.current.date(byAdding: .year, value: 1, to: today) ?? today
        return lower...upper
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Eyebrow(text: title); content() }
    }

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(
            "",
            text: text,
            prompt: Text(placeholder).foregroundStyle(Clinical.secondary.opacity(0.78))
        )
            .font(Clinical.caption(15))
            .foregroundStyle(Clinical.ink)
            .tint(Clinical.accent)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    /// Merges the date-strip day with the time picker's hour/minute — the two controls edit the
    /// same instant, but SwiftUI needs them as separate bindings for a calm, focused UI.
    private func save() {
        let calendar = Calendar.current
        var combined = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComps = calendar.dateComponents([.hour, .minute], from: time)
        combined.hour = timeComps.hour
        combined.minute = timeComps.minute
        let combinedDate = calendar.date(from: combined) ?? date
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        if let existing {
            existing.type = type
            existing.date = combinedDate
            existing.location = trimmedLocation
            existing.note = trimmedNote
        } else {
            context.insert(ProcedureAppointment(
                type: type,
                date: combinedDate,
                location: trimmedLocation,
                note: trimmedNote
            ))
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
