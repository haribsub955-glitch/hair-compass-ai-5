import PhotosUI
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
    /// Non-nil while the prescription confirmation card is up — set by `save()` when the
    /// final field values describe a usually-prescription-only medication.
    @State private var rxRequirement: RxGate.Requirement? = nil

    // MARK: Ingredients photo + AI summary (custom item support)
    @State private var ingredientPickerItem: PhotosPickerItem?
    @State private var ingredientImage: UIImage?
    @State private var ingredientPhotoPath = ""
    @State private var aiIngredientSummary = ""
    @State private var analysisService = CloudAnalysisService()
    /// Consent gate for the "Analyze with AI" tap — the photo leaves the device, mirroring the
    /// same allow/not-now flow `TodayView` uses before `DeepAnalysisSheet`.
    @State private var showAIConsent = false
    @State private var aiConsentJustGranted = false

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
                                        selectClass(c)
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

                    let presets = TreatmentGuide.presets(for: treatmentClass)
                    if !presets.isEmpty {
                        section("Common regimen") {
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(presets) { p in presetChip(p) }
                            }
                            Text("A common regimen — confirm what's right for you with your prescriber.")
                                .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
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

                    ingredientPhotoSection

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
            .onAppear {
                if name.isEmpty { name = treatmentClass.title }
                #if DEBUG
                // HC_RXCONFIRM (launched with HC_ADDTREATMENT): preselect finasteride, apply its
                // standard regimen, and run the real save path so the prescription confirmation
                // card presents itself — same delayed-trigger pattern as CareView's HC_ flags.
                if ProcessInfo.processInfo.arguments.contains("HC_RXCONFIRM") {
                    selectClass(.finasteride)
                    if let preset = TreatmentGuide.presets(for: .finasteride).first { apply(preset) }
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        save()
                    }
                }
                #endif
            }
            // Sheet-over-sheet (the app's whole flow is sheet-based): the card floats over the
            // form at a medium detent, so "Go back" lands on the untouched form underneath.
            .sheet(item: $rxRequirement) { requirement in
                RxConfirmSheet(
                    name: name.trimmingCharacters(in: .whitespaces),
                    dose: dose.trimmingCharacters(in: .whitespaces),
                    schedule: treatmentClass.isDaily ? times : "",
                    requirement: requirement
                ) {
                    rxRequirement = nil
                    insertAndDismiss()
                }
            }
            // One-time consent before the ingredient photo leaves the device — same allow/not-now
            // pattern as TodayView's gate in front of DeepAnalysisSheet. The next step (running the
            // analysis) fires from onDismiss, not from onAllow, so only one sheet is ever presented.
            .sheet(isPresented: $showAIConsent, onDismiss: {
                if aiConsentJustGranted {
                    aiConsentJustGranted = false
                    runIngredientAnalysis()
                }
            }) {
                AIConsentSheet(
                    onAllow: {
                        aiConsentJustGranted = true
                        showAIConsent = false
                    },
                    onNotNow: { showAIConsent = false }
                )
            }
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

    /// Switching class resets any placeholder or preset-filled fields, but never hand-typed ones.
    private func selectClass(_ c: TreatmentClass) {
        let previousPresets = TreatmentGuide.presets(for: treatmentClass)
        treatmentClass = c
        if name.isEmpty
            || TreatmentClass.allCases.map(\.title).contains(name)
            || previousPresets.map(\.name).contains(name) {
            name = c.title
        }
        if previousPresets.map(\.dose).contains(dose) { dose = "" }
        times = defaultTimes(for: c)
    }

    // MARK: Common-regimen presets (one explicit tap — never auto-applied)

    private func isApplied(_ p: DosePreset) -> Bool {
        name == p.name && dose == p.dose && (!treatmentClass.isDaily || times == p.scheduleTimes)
    }

    private func apply(_ p: DosePreset) {
        name = p.name
        dose = p.dose
        times = p.scheduleTimes.isEmpty ? defaultTimes(for: treatmentClass) : p.scheduleTimes
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func presetChip(_ p: DosePreset) -> some View {
        let applied = isApplied(p)
        return Button {
            apply(p)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: applied ? "checkmark.circle.fill" : "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(applied ? Clinical.accent : Clinical.gold)
                    Text(p.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                }
                Text(p.summary)
                    .font(.system(size: 11)).foregroundStyle(Clinical.secondary)
                Text(p.note)
                    .font(.system(size: 10)).foregroundStyle(Clinical.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(applied ? Clinical.accentSoft : Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(applied ? Clinical.accent.opacity(0.5) : Clinical.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            .font(.system(size: 16))
            .foregroundStyle(Clinical.ink)
            .tint(Clinical.accent)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    // MARK: Ingredients photo + AI summary

    /// Optional — mainly for a custom item (class `.other`) whose ingredients aren't in the
    /// evidence library. A photo of the label lets the AI identify it; nothing leaves the device
    /// until the consent gate is passed.
    private var ingredientPhotoSection: some View {
        section("Ingredients photo (optional)") {
            VStack(alignment: .leading, spacing: 12) {
                if let ingredientImage {
                    Image(uiImage: ingredientImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                }

                PhotosPicker(selection: $ingredientPickerItem, matching: .images) {
                    Label(ingredientImage == nil ? "Add a photo of the label" : "Replace photo", systemImage: "camera")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(ClinicalButtonStyle(filled: false))
                .onChange(of: ingredientPickerItem) { _, item in loadIngredientPhoto(item) }

                if ingredientImage != nil {
                    Button(action: analyzeIngredientsTapped) {
                        Label(analysisService.isRunning ? "Analyzing…" : "Analyze with AI", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(ClinicalButtonStyle(filled: false))
                    .disabled(analysisService.isRunning)

                    if !aiIngredientSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(aiIngredientSummary)
                                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                            Text("AI summary · not medical advice")
                                .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                        }
                    }

                    if let error = analysisService.errorMessage {
                        Text(error).font(.system(size: 12)).foregroundStyle(Clinical.critical)
                    }
                }

                Text("Sends this one photo off-device to identify what it is — record-keeping, not medical advice.")
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    private func loadIngredientPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) else { return }
            ingredientImage = ui
            aiIngredientSummary = ""
            if let path = PhotoStore.shared.save(ui) {
                ingredientPhotoPath = path
            }
        }
    }

    private func analyzeIngredientsTapped() {
        guard ingredientImage != nil else { return }
        // Consent gate: this photo leaves the device, so the first tap asks in plain language.
        // Once granted (revocable in Privacy), straight in — mirrors TodayView's deep-analysis gate.
        if AIConsent.isGranted() {
            runIngredientAnalysis()
        } else {
            showAIConsent = true
        }
    }

    private func runIngredientAnalysis() {
        guard let ingredientImage else { return }
        Task {
            if let summary = await analysisService.analyzeIngredients(image: ingredientImage) {
                aiIngredientSummary = summary
            }
        }
    }

    private func save() {
        // Usually-prescription-only medications pause on a friendly confirmation instead of
        // saving silently. The gate reads the final field values — never a preset's identity —
        // so hand-edited names/doses are what get judged.
        if let requirement = RxGate.requirement(
            treatmentClass: treatmentClass,
            name: name.trimmingCharacters(in: .whitespaces),
            dose: dose.trimmingCharacters(in: .whitespaces)
        ) {
            rxRequirement = requirement
            return
        }
        insertAndDismiss()
    }

    /// The unchanged save path — run directly for non-prescription treatments, or as the
    /// confirmed action after the Rx card.
    private func insertAndDismiss() {
        let t = Treatment(
            name: name.trimmingCharacters(in: .whitespaces),
            treatmentClass: treatmentClass,
            dose: dose.trimmingCharacters(in: .whitespaces),
            scheduleTimes: treatmentClass.isDaily ? times : "",
            startDate: startDate,
            isActive: true,
            refillBy: refillBy,
            ingredientPhotoPath: ingredientPhotoPath,
            aiIngredientSummary: aiIngredientSummary
        )
        context.insert(t)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
