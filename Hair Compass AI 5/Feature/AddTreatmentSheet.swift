import SwiftData
import SwiftUI

struct AddTreatmentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var treatmentClass: TreatmentClass = .minoxidil
    @State private var name = ""
    @State private var dose = ""
    @State private var startDate = Date.now
    @State private var times = "08:00,21:00"
    @State private var refillBy: Date? = nil

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section("Type") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TreatmentClass.allCases) { c in
                                    let on = c == treatmentClass
                                    Button {
                                        treatmentClass = c
                                        if name.isEmpty || TreatmentClass.allCases.map(\.title).contains(name) {
                                            name = c.title
                                        }
                                        times = defaultTimes(for: c)
                                    } label: {
                                        Label(c.title, systemImage: c.symbol)
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

                    section("Name") {
                        textField("e.g. Minoxidil 5%", text: $name)
                    }
                    section("Dose") {
                        textField("e.g. 1 mL", text: $dose)
                    }

                    if treatmentClass.isDaily {
                        section("Daily times") {
                            textField("08:00,21:00", text: $times)
                            Text("Comma-separated 24-hour times. Drives adherence math.")
                                .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        }
                    }

                    section("Start date") {
                        DateStripPicker(selection: $startDate)
                        Text("Sets the 24-week assessment clock.")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }

                    section("Refill by (optional)") {
                        if refillBy != nil {
                            DateStripPicker(
                                selection: Binding(get: { refillBy ?? .now }, set: { refillBy = $0 }),
                                range: refillRange
                            )
                            Button("Clear refill date") { refillBy = nil }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Clinical.secondary)
                                .buttonStyle(.plain)
                        } else {
                            Button("Set a refill date") {
                                refillBy = Calendar.current.date(byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: .now))
                            }
                            .buttonStyle(ClinicalButtonStyle(filled: false))
                            Text("When your current supply runs out — you'll see a heads-up before it lapses.")
                                .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        }
                    }

                    Button("Add treatment", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("New treatment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { if name.isEmpty { name = treatmentClass.title } }
        }
    }

    private var refillRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        let upper = Calendar.current.date(byAdding: .day, value: 180, to: today) ?? today
        return today...max(today, upper)
    }

    private func defaultTimes(for c: TreatmentClass) -> String {
        switch c.defaultDailyCount {
        case 2: return "08:00,21:00"
        case 1: return "21:00"
        default: return ""
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Eyebrow(text: title); content() }
    }

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 16))
            .padding(12)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    private func save() {
        let t = Treatment(
            name: name.trimmingCharacters(in: .whitespaces),
            treatmentClass: treatmentClass,
            dose: dose.trimmingCharacters(in: .whitespaces),
            scheduleTimes: treatmentClass.isDaily ? times : "",
            startDate: startDate,
            isActive: true,
            refillBy: refillBy
        )
        context.insert(t)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
