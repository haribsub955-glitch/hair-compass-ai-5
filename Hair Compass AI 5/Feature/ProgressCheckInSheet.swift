import SwiftData
import SwiftUI

/// The between-visit questions a dermatologist asks, captured periodically (~monthly): new
/// regrowth, density/shedding/hairline trend, overall, and a scalp-symptom red flag. Same
/// Clinical form idiom as `AddProcedureSheet`/`AddLabSheet` — a horizontal chip picker per
/// question, free text, one save button. Answers are self-reported *context*, never a
/// measurement or a diagnosis; the scalp-pain caption is a safety nudge, not a diagnosis.
struct ProgressCheckInSheet: View {
    /// nil = a new check-in; non-nil = editing that one in place.
    var existing: ProgressCheckIn?
    /// "You've been on Minoxidil for 20 weeks." — shown under the title when available, so the
    /// regrowth/shedding answers below are read against what the person is actually doing.
    var treatmentContext: String?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var regrowth: RegrowthLevel
    @State private var density: ProgressTrend
    @State private var shedding: ProgressTrend
    @State private var hairline: ProgressTrend
    @State private var overall: ProgressTrend
    @State private var scalpPain: Bool
    @State private var scalpPainNote: String
    @State private var note: String

    init(existing: ProgressCheckIn? = nil, treatmentContext: String? = nil) {
        self.existing = existing
        self.treatmentContext = treatmentContext
        _regrowth = State(initialValue: existing?.regrowth ?? .none)
        _density = State(initialValue: existing?.density ?? .same)
        _shedding = State(initialValue: existing?.shedding ?? .same)
        _hairline = State(initialValue: existing?.hairline ?? .same)
        _overall = State(initialValue: existing?.overall ?? .same)
        _scalpPain = State(initialValue: existing?.scalpPain ?? false)
        _scalpPainNote = State(initialValue: existing?.scalpPainNote ?? "")
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if let treatmentContext {
                        Text(treatmentContext)
                            .font(.system(size: 13))
                            .foregroundStyle(Clinical.secondary)
                    }

                    section("New regrowth (baby hairs)") {
                        Text("Any new fine \u{201c}baby\u{201d} hairs at your hairline, part, or crown?")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        chipRow(RegrowthLevel.allCases, selection: $regrowth) { $0.title }
                    }

                    section("Density") {
                        Text("Compared to last time, does your scalp show through\u{2026}")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        chipRow(ProgressTrend.allCases, selection: $density) { $0.label(for: .density) }
                    }

                    section("Shedding") {
                        Text("Your shedding lately is\u{2026}")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        chipRow(ProgressTrend.allCases, selection: $shedding) { $0.label(for: .shedding) }
                    }

                    section("Hairline / part") {
                        Text("Your hairline or part is\u{2026}")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        chipRow(ProgressTrend.allCases, selection: $hairline) { $0.label(for: .hairline) }
                    }

                    section("Overall") {
                        Text("Overall, your hair feels\u{2026}")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        chipRow(ProgressTrend.allCases, selection: $overall) { $0.label(for: .overall) }
                    }

                    section("Scalp symptoms") {
                        Toggle(isOn: $scalpPain) {
                            Text("Any scalp pain, burning, or tender spots?")
                                .font(.system(size: 14)).foregroundStyle(Clinical.ink)
                        }
                        .tint(Clinical.accent)
                        if scalpPain {
                            textField("Where, and what does it feel like? (optional)", text: $scalpPainNote)
                            // A safety nudge, never a diagnosis — persistent scalp pain/tenderness
                            // with hair loss can signal a scarring alopecia that needs prompt
                            // dermatology attention.
                            Text("Persistent scalp pain is worth mentioning to your dermatologist soon.")
                                .font(.system(size: 12)).foregroundStyle(Clinical.warning)
                        }
                    }

                    section("Note (optional)") {
                        textField("Anything worth remembering", text: $note)
                    }

                    Button(existing == nil ? "Save check-in" : "Update check-in", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Progress check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Eyebrow(text: title); content() }
    }

    /// The `AddProcedureSheet`/`AddLabSheet` horizontal-chip idiom, generalized over any
    /// `CaseIterable` enum — used for the regrowth row (4 chips) and each trend row (3 chips).
    private func chipRow<T: Hashable & CaseIterable>(
        _ cases: T.AllCases,
        selection: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View where T.AllCases: RandomAccessCollection {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(cases), id: \.self) { c in
                    let on = c == selection.wrappedValue
                    Button {
                        selection.wrappedValue = c
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(label(c))
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

    /// Inserts a new `ProgressCheckIn`, or mutates `existing` in place when editing. No
    /// diagnosis branch on `scalpPain == true` — the in-form caption already delivered the
    /// honest nudge; saving just persists the answer.
    private func save() {
        if let existing {
            existing.regrowth = regrowth
            existing.density = density
            existing.shedding = shedding
            existing.hairline = hairline
            existing.overall = overall
            existing.scalpPain = scalpPain
            existing.scalpPainNote = scalpPain ? scalpPainNote.trimmingCharacters(in: .whitespaces) : ""
            existing.note = note.trimmingCharacters(in: .whitespaces)
        } else {
            context.insert(ProgressCheckIn(
                regrowth: regrowth,
                density: density,
                shedding: shedding,
                hairline: hairline,
                overall: overall,
                scalpPain: scalpPain,
                scalpPainNote: scalpPain ? scalpPainNote.trimmingCharacters(in: .whitespaces) : "",
                note: note.trimmingCharacters(in: .whitespaces)
            ))
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
