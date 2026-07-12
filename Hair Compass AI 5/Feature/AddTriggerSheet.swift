import SwiftData
import SwiftUI

/// Records a dated telogen-effluvium trigger — a flu, a crash diet, childbirth, major stress, a
/// new medication, or something else notable. Onboarding is the only place `TriggerEvent` gets
/// created today; this sheet is the post-onboarding entry point so a life event in month 3 (or
/// any time after) can still be dated and read against the ~2–3 month shedding lag the app
/// teaches. Same Clinical form idiom as `AddProcedureSheet`/`AddLabSheet`: a chip picker, a date
/// strip, an optional note, one save button. Pure record-keeping — never advice, never a claim
/// about what caused anything.
struct AddTriggerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var type: TriggerType = .illness
    @State private var date = Date.now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Shedding often lags a trigger like this by 2–3 months — dating it now lets the journey chart explain a spike later instead of leaving it unexplained.")
                        .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    section("What happened") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TriggerType.allCases) { t in
                                    let on = t == type
                                    Button { type = t } label: {
                                        Label(t.title, systemImage: t.symbol)
                                            .font(.system(size: 14, weight: on ? .semibold : .regular))
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

                    Button("Log this event", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Log a life event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    /// Six months back — the outer edge of the TE watch window this app teaches — through today.
    /// Never the future: a trigger is something that already happened.
    private var dateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        let lower = Calendar.current.date(byAdding: .month, value: -6, to: today) ?? today
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
            .font(.system(size: 15))
            .foregroundStyle(Clinical.ink)
            .tint(Clinical.accent)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    private func save() {
        context.insert(TriggerEvent(
            type: type,
            date: date,
            note: note.trimmingCharacters(in: .whitespaces)
        ))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
