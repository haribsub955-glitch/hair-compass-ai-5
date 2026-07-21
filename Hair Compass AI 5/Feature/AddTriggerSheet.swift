import SwiftData
import SwiftUI

/// Records a dated telogen-effluvium trigger — a flu, a crash diet, childbirth, major stress, a
/// new medication, or something else notable. This is both the post-onboarding entry point (so a
/// life event in month 3, or any time after, can still be dated and read against the ~2–3 month
/// shedding lag the app teaches) and, via `existing`, the one place a previously logged event can
/// be corrected — reached from `LifeEventsSheet`'s list or `JourneyChart`'s marker disclosure.
/// Same Clinical form idiom as `AddProcedureSheet`/`AddLabSheet`: a chip picker, a date strip, an
/// optional note, one save button. Pure record-keeping — never advice, never a claim about what
/// caused anything.
struct AddTriggerSheet: View {
    /// nil = logging a new event; non-nil = editing that one in place (same form, prefilled).
    var existing: TriggerEvent?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var type: TriggerType
    @State private var date: Date
    @State private var note: String

    init(existing: TriggerEvent? = nil) {
        self.existing = existing
        _type = State(initialValue: existing?.type ?? .illness)
        _date = State(initialValue: existing?.date ?? .now)
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Shedding often lags a trigger like this by 2–3 months — dating it now lets the journey chart explain a spike later instead of leaving it unexplained.")
                        .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    section("What happened") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TriggerType.allCases) { t in
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
                    }

                    section("When") {
                        DateStripPicker(selection: $date, range: dateRange)
                    }

                    section("Note (optional)") {
                        textField("Anything worth remembering", text: $note)
                    }

                    Button(existing == nil ? "Log this event" : "Save changes", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle(existing == nil ? "Log a life event" : "Edit life event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    /// Six months back — the outer edge of the TE watch window this app teaches — through today.
    /// Never the future: a trigger is something that already happened. When editing an event
    /// dated further back than that (logged during onboarding, or simply old), the lower bound
    /// widens to include its actual date so `DateStripPicker` never clips a value it's supposed
    /// to be showing.
    private var dateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        let sixMonthsBack = Calendar.current.date(byAdding: .month, value: -6, to: today) ?? today
        let lower = min(sixMonthsBack, existing?.date ?? sixMonthsBack)
        return lower...today
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

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        if let existing {
            existing.type = type
            existing.date = date
            existing.note = trimmedNote
        } else {
            context.insert(TriggerEvent(type: type, date: date, note: trimmedNote))
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
