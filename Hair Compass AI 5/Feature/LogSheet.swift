import SwiftData
import SwiftUI

/// Daily self-report. Fields are exactly the evidence-backed signals from TrackingSpec.md.
struct LogSheet: View {
    let existing: DailyEntry?
    let condition: HairCondition

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var shed: ShedLevel = .normal
    @State private var flaking = 0
    @State private var erythema = 0
    @State private var itch = 0
    @State private var sleepQuality = 3
    @State private var stress = 3
    @State private var cigarettes = 0
    @State private var alcoholDrinks = 0
    @State private var oiliness = 0
    @State private var note = ""

    private var scalpTotal: Int { HairAnalytics.scalpTotal(flaking: flaking, erythema: erythema, itch: itch) }
    private var scalpBand: SeverityBand { HairAnalytics.scalpBand(total: scalpTotal) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section(variable: "shedding") {
                        ShedDialField(shed: $shed)
                    }

                    section(variable: "scalp") {
                        VStack(spacing: 16) {
                            PipStepper(title: "Flaking", caption: flakingCaption, range: 0...3, value: $flaking)
                            PipStepper(title: "Redness", caption: level3Caption(erythema), range: 0...3, value: $erythema)
                            PipStepper(title: "Itch", caption: level3Caption(itch), range: 0...3, value: $itch)
                        }
                        HStack {
                            Text("Scalp severity")
                                .font(.system(size: 13))
                                .foregroundStyle(Clinical.secondary)
                            Spacer()
                            Text("\(scalpTotal)/16 · \(scalpBand.title)")
                                .font(Clinical.number(14))
                                .foregroundStyle(Clinical.bandColor(scalpBand))
                        }
                        .padding(.top, 2)

                        Divider().overlay(Clinical.hairline).padding(.vertical, 2)

                        PipStepper(title: "Oiliness", caption: oilinessCaption, range: 0...3, value: $oiliness, tint: Clinical.gold)
                        Text("An observation, not a risk driver — it doesn't feed the severity score.")
                            .font(.system(size: 11))
                            .foregroundStyle(Clinical.tertiary)
                    }

                    section("Wellbeing") {
                        VStack(spacing: 16) {
                            PipStepper(title: "Sleep quality", caption: "\(sleepQuality)/5", range: 1...5, value: $sleepQuality, tint: Clinical.ink)
                            PipStepper(title: "Stress", caption: "\(stress)/5", range: 1...5, value: $stress, tint: Clinical.ink)
                        }
                        Stepper(value: $cigarettes, in: 0...60) {
                            HStack {
                                Text("Cigarettes today")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Clinical.ink)
                                Spacer()
                                Text("\(cigarettes)")
                                    .font(Clinical.number(15))
                                    .foregroundStyle(cigarettes > 0 ? Clinical.warning : Clinical.tertiary)
                            }
                        }
                        Stepper(value: $alcoholDrinks, in: 0...30) {
                            HStack {
                                Text("Alcoholic drinks")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Clinical.ink)
                                Spacer()
                                Text("\(alcoholDrinks)")
                                    .font(Clinical.number(15))
                                    .foregroundStyle(Clinical.tertiary)
                            }
                        }
                        Text("Smoking is a strong, quantified risk factor. Sleep and stress are context; alcohol is a weak signal.")
                            .font(.system(size: 11))
                            .foregroundStyle(Clinical.tertiary)
                    }

                    section("Note") {
                        TextField("Anything worth remembering", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(Clinical.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Clinical.hairline, lineWidth: 1)
                            )
                    }

                    Button(existing == nil ? "Save entry" : "Update entry", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .clinicalScreen()
            .navigationTitle(existing == nil ? "Log today" : "Edit today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var flakingCaption: String {
        ["None", "Powdery", "Visible", "Adherent"][min(max(flaking, 0), 3)]
    }
    private var oilinessCaption: String {
        ["Normal", "Slightly oily", "Oily", "Very oily"][min(max(oiliness, 0), 3)]
    }
    private func level3Caption(_ v: Int) -> String {
        ["None", "Mild", "Moderate", "Marked"][min(max(v, 0), 3)]
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: title)
            content()
        }
    }

    @ViewBuilder
    private func section<Content: View>(variable id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VariableSectionHeader(variableID: id)
            content()
        }
    }

    private func loadExisting() {
        guard let e = existing else { return }
        shed = e.shed
        flaking = e.flaking
        erythema = e.erythema
        itch = e.itch
        sleepQuality = e.sleepQuality
        stress = e.stress
        cigarettes = e.cigarettes
        alcoholDrinks = e.alcoholDrinks
        oiliness = e.oiliness
        note = e.note
    }

    private func save() {
        let target: DailyEntry
        if let e = existing {
            target = e
        } else {
            target = DailyEntry(date: .now)
            context.insert(target)
        }
        target.shed = shed
        target.flaking = flaking
        target.erythema = erythema
        target.itch = itch
        target.sleepQuality = sleepQuality
        target.stress = stress
        target.cigarettes = cigarettes
        target.alcoholDrinks = alcoholDrinks
        target.oiliness = oiliness
        target.note = note
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
