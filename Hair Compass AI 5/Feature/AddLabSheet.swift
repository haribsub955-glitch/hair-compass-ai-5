import SwiftData
import SwiftUI

struct AddLabSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var test: LabTest = .ferritin
    @State private var valueText = ""
    @State private var date = Date.now
    @State private var note = ""
    /// Which of `test.unitOptions` the entered value is in — always resets to the canonical
    /// unit (index 0) when the test changes, so switching tests never silently carries over a
    /// unit label that doesn't apply.
    @State private var unitLabel = LabTest.ferritin.unit
    /// "Use the range printed on your report" — off by default (the built-in adult range).
    @State private var useCustomRange = false
    @State private var refLowText = ""
    @State private var refHighText = ""
    /// Non-nil right after Save when the entered value is out of range — presented as a sheet
    /// over this one, so the honest proposal pops up immediately instead of waiting for the
    /// user to find it in Labs. This sheet only dismisses once that one closes (see `.sheet`
    /// below), never before.
    @State private var proposal: LabProposal?

    private var enteredValue: Double? { Double(valueText.replacingOccurrences(of: ",", with: ".")) }
    private var selectedUnit: LabUnitOption { test.unitOptions.first { $0.label == unitLabel } ?? test.unitOptions[0] }
    /// The value actually stored — converted to `test`'s canonical unit if a non-canonical
    /// unit was picked, so `LabResult.value` is always comparable to `test.referenceRange`.
    private var value: Double? { enteredValue.map(selectedUnit.toCanonical) }
    private var refLow: Double? { Double(refLowText.replacingOccurrences(of: ",", with: ".")) }
    private var refHigh: Double? { Double(refHighText.replacingOccurrences(of: ",", with: ".")) }
    /// The entered custom interval, only once it's actually a valid low < high range.
    private var validCustomRange: (low: Double, high: Double)? {
        guard useCustomRange, let refLow, let refHigh, refLow < refHigh else { return nil }
        return (refLow, refHigh)
    }
    /// What the live preview flags against: the valid custom interval, otherwise the built-in
    /// default — mirrors `LabResult.effectiveRange`.
    private var displayedRange: ClosedRange<Double> {
        if let r = validCustomRange { return r.low...r.high }
        return test.referenceRange
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section("Test") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(LabTest.allCases) { t in
                                    let on = t == test
                                    Button {
                                        test = t
                                        // A unit or override picked for the previous test
                                        // doesn't apply to the new one — reset both.
                                        unitLabel = t.unit
                                        useCustomRange = false
                                        refLowText = ""; refHighText = ""
                                    } label: {
                                        Text(t.title)
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
                        Text(test.note).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }

                    section("Value") {
                        HStack(spacing: 10) {
                            TextField(
                                "",
                                text: $valueText,
                                prompt: Text("0").foregroundStyle(Clinical.secondary.opacity(0.78))
                            )
                                .keyboardType(.decimalPad)
                                .font(Clinical.number(18))
                                .foregroundStyle(Clinical.ink)
                                .tint(Clinical.accent)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Clinical.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                            // Some labs report in a different unit (a UK/EU report often gives
                            // vitamin D in nmol/L, B12 in pmol/L) — only shown when this test
                            // actually has an alternate, so most tests keep the plain layout.
                            if test.unitOptions.count > 1 {
                                Menu {
                                    ForEach(test.unitOptions) { option in
                                        Button(option.label) { unitLabel = option.label }
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(unitLabel)
                                        Image(systemName: "chevron.down").font(Clinical.body(9, weight: .semibold))
                                    }
                                    .font(Clinical.body(13, weight: .medium))
                                    .foregroundStyle(Clinical.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 12)
                                    .background(Clinical.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                                }
                            } else {
                                Text(test.unit)
                                    .font(Clinical.body(13, weight: .medium)).foregroundStyle(Clinical.secondary)
                            }
                        }
                        if let v = value {
                            let flag = HairAnalytics.flag(for: v, range: displayedRange)
                            HStack(spacing: 4) {
                                Text("Reference \(displayedRange.lowerBound.formatted())–\(displayedRange.upperBound.formatted()) \(test.unit) · \(flag.title)")
                                if validCustomRange != nil {
                                    Text("· from your lab report").foregroundStyle(Clinical.tertiary)
                                }
                            }
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.flagColor(flag))
                            if unitLabel != test.unit {
                                Text("Converted to \(v.formatted(.number.precision(.fractionLength(0...1)))) \(test.unit) for storage — Hair Compass always keeps one unit per test.")
                                    .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                            }
                        }
                    }

                    section("Reference range") {
                        Toggle("Use the range printed on your report", isOn: $useCustomRange.animation())
                            .font(Clinical.body(13, weight: .medium)).foregroundStyle(Clinical.ink)
                            .tint(Clinical.accent)
                        if useCustomRange {
                            HStack(spacing: 10) {
                                rangeField("Low", text: $refLowText)
                                Text("–").foregroundStyle(Clinical.tertiary)
                                rangeField("High", text: $refHighText)
                                Text(test.unit).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                            }
                            Text("Overrides the built-in default for this result — every lab prints its own interval, and ferritin ranges differ by sex.")
                                .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                        }
                    }

                    section("Date") {
                        DateStripPicker(selection: $date)
                    }

                    section("Note") {
                        TextField(
                            "",
                            text: $note,
                            prompt: Text("Optional").foregroundStyle(Clinical.secondary.opacity(0.78))
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

                    Button("Save result", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                        .disabled(value == nil)
                        .opacity(value == nil ? 0.5 : 1)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Log lab result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            // Fires whether the proposal sheet closed via its own Done button or a swipe —
            // either way, this sheet's job is done and it dismisses in step.
            .sheet(item: $proposal, onDismiss: { dismiss() }) { proposal in
                LabProposalSheet(proposal: proposal)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Eyebrow(text: title); content() }
    }

    private func rangeField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Clinical.secondary.opacity(0.78)))
            .keyboardType(.decimalPad)
            .font(Clinical.number(15))
            .foregroundStyle(Clinical.ink)
            .tint(Clinical.accent)
            .textFieldStyle(.plain)
            .padding(10)
            .frame(width: 76)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    private func save() {
        guard let v = value else { return }
        let result = LabResult(
            test: test, value: v, collectedAt: date, note: note.trimmingCharacters(in: .whitespaces),
            refLow: validCustomRange?.low, refHigh: validCustomRange?.high
        )
        context.insert(result)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Out of range → hold this sheet open and pop the honest proposal card over it instead
        // of dismissing immediately; in range → the original one-tap dismiss, unchanged.
        if let next = LabProposal.for(result) {
            proposal = next
        } else {
            dismiss()
        }
    }
}
