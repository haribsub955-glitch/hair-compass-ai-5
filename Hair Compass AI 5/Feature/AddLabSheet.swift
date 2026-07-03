import SwiftData
import SwiftUI

struct AddLabSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var test: LabTest = .ferritin
    @State private var valueText = ""
    @State private var date = Date.now
    @State private var note = ""

    private var value: Double? { Double(valueText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section("Test") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(LabTest.allCases) { t in
                                    let on = t == test
                                    Button { test = t } label: {
                                        Text(t.title)
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
                        Text(test.note).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }

                    section("Value (\(test.unit))") {
                        TextField("0", text: $valueText)
                            .keyboardType(.decimalPad)
                            .font(Clinical.number(18))
                            .padding(12)
                            .background(Clinical.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                        if let v = value {
                            let flag = HairAnalytics.flag(for: v, test: test)
                            Text("Reference \(test.referenceRange.lowerBound.formatted())–\(test.referenceRange.upperBound.formatted()) · \(flag.title)")
                                .font(.system(size: 12)).foregroundStyle(Clinical.flagColor(flag))
                        }
                    }

                    section("Date") {
                        DateStripPicker(selection: $date)
                    }

                    section("Note") {
                        TextField("Optional", text: $note)
                            .font(.system(size: 15)).padding(12)
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
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Eyebrow(text: title); content() }
    }

    private func save() {
        guard let v = value else { return }
        context.insert(LabResult(test: test, value: v, collectedAt: date, note: note.trimmingCharacters(in: .whitespaces)))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
