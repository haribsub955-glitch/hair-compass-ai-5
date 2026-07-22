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
    /// Which weekdays a periodic item is used (Calendar weekday numbers 1=Sun…7=Sat). Empty = every
    /// day. Only shown/used for classes where `supportsWeekdaySchedule` is true — the care
    /// products plus the home-use devices with a real weekly-ish cadence (microneedling, LLLT).
    @State private var scheduledWeekdays: Set<Int> = []
    @State private var refillBy: Date? = nil
    /// Non-nil while the prescription confirmation card is up — set by `save()` when the
    /// final field values describe a usually-prescription-only medication.
    @State private var rxRequirement: RxGate.Requirement? = nil

    /// The profile drives the pregnancy caution: if she said pregnant / trying / breastfeeding,
    /// adding one of the recognised medications pauses on an honest note first.
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @State private var pregnancyInfo: PregnancyCaution.Info? = nil
    @State private var proceedAfterPregnancyCaution = false

    // MARK: Baseline photo nudge
    /// The strongest evidence for the week-24 judgment is a dated baseline photo set taken at
    /// treatment start — `CompareView`/the Visit PDF both depend on one existing. Read-only, so
    /// this needs the existing record, not anything new.
    @Query(sort: \PhotoRecord.createdAt) private var photoRecords: [PhotoRecord]
    @State private var showBaselinePrompt = false
    @State private var showGuidedCapture = false

    // MARK: Ingredients photo + AI summary (custom item support)
    @State private var ingredientPickerItem: PhotosPickerItem?
    @State private var ingredientImage: UIImage?
    /// Text read off the label on-device by Vision the moment a photo is picked — instant, free,
    /// and private, shown before (and independent of) the optional off-device AI identification.
    @State private var detectedLabelText = ""
    @State private var ingredientPhotoPath = ""
    @State private var aiIngredientSummary = ""
    @State private var analysisService = OnDeviceAnalysisService()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    section("Type") {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(TreatmentClass.allCases) { c in
                                        let on = c == treatmentClass
                                        Button {
                                            selectClass(c)
                                        } label: {
                                            Label(c.title, systemImage: c.symbol)
                                                .font(Clinical.body(14, weight: on ? .semibold : .regular))
                                                .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                                                .padding(.horizontal, 13).padding(.vertical, 9)
                                                .background(on ? Clinical.ink : Clinical.surface)
                                                .clipShape(Capsule())
                                                .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .id(c)
                                    }
                                }
                            }
                            // The care products sit past the fold; bring the chosen chip into view
                            // so the selection is always visible, however far along it is.
                            .onChange(of: treatmentClass) { _, c in
                                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(c, anchor: .center) }
                            }
                        }
                        Text(TreatmentGuide.shortExpectation(for: treatmentClass))
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    let presets = TreatmentGuide.presets(for: treatmentClass)
                    if !presets.isEmpty {
                        section("Common regimen") {
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(presets) { p in presetChip(p) }
                            }
                            Text("A common regimen — confirm what's right for you with your prescriber.")
                                .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                        }
                    }

                    section("Name") {
                        textField(namePlaceholder, text: $name)
                    }
                    section(doseLabel) {
                        textField(dosePlaceholder, text: $dose)
                    }

                    if treatmentClass.isDaily {
                        section("Daily times") {
                            textField("08:00,21:00", text: $times)
                            Text("Comma-separated 24-hour times. Drives adherence math.")
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        }
                    }

                    if treatmentClass.supportsWeekdaySchedule {
                        section("Days") {
                            WeekdaySchedulePicker(selection: $scheduledWeekdays)
                            if let hint = TreatmentGuide.scheduleHint(for: treatmentClass) {
                                Text(hint)
                                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                            }
                            Text(scheduledWeekdays.isEmpty
                                 ? "Every day. Tap days to use it only on those."
                                 : "Shows in your routine on the selected days.")
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        }
                    }

                    section("Start date") {
                        DateStripPicker(selection: $startDate)
                        Text("Sets the 24-week assessment clock.")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }

                    section("Refill by (optional)") {
                        if refillBy != nil {
                            DateStripPicker(
                                selection: Binding(get: { refillBy ?? .now }, set: { refillBy = $0 }),
                                range: refillRange
                            )
                            Button("Clear refill date") { refillBy = nil }
                                .font(Clinical.body(13, weight: .medium))
                                .foregroundStyle(Clinical.secondary)
                                .buttonStyle(.plain)
                        } else {
                            Button("Set a refill date") {
                                refillBy = Calendar.current.date(byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: .now))
                            }
                            .buttonStyle(ClinicalButtonStyle(filled: false))
                            Text("When your current supply runs out — you'll see a heads-up before it lapses.")
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        }
                    }

                    ingredientPhotoSection

                    Button("Add to plan", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("New plan item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                if name.isEmpty { name = treatmentClass.title }
                #if DEBUG
                // HC_ADDCLASS <rawValue> preselects a category so the adaptive form (icon,
                // dose/amount label, per-type schedule) can be inspected without tapping.
                let launchArgs = ProcessInfo.processInfo.arguments
                if let i = launchArgs.firstIndex(of: "HC_ADDCLASS"), i + 1 < launchArgs.count,
                   let c = TreatmentClass(rawValue: launchArgs[i + 1]) {
                    selectClass(c)
                }
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
            // Pregnancy caution floats over the form first. "Add anyway" flags `proceed` and
            // dismisses; the rest of the save (Rx check → insert) runs from `onDismiss` so two
            // sheets never contend — the same pattern the AI-consent gate below uses.
            .sheet(item: $pregnancyInfo, onDismiss: {
                if proceedAfterPregnancyCaution {
                    proceedAfterPregnancyCaution = false
                    runRxCheckThenInsert()
                }
            }) { info in
                PregnancyCautionSheet(info: info) {
                    proceedAfterPregnancyCaution = true
                    pregnancyInfo = nil
                }
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
            // One-time, fully skippable — fires only right after a today-dated save with no
            // recent photo on record, never blocking or repeating.
            .confirmationDialog(
                "Capture a baseline photo set now?",
                isPresented: $showBaselinePrompt,
                titleVisibility: .visible
            ) {
                Button("Capture now") { showGuidedCapture = true }
                Button("Not now", role: .cancel) { dismiss() }
            } message: {
                Text("The week-24 comparison starts here.")
            }
            .sheet(isPresented: $showGuidedCapture, onDismiss: { dismiss() }) {
                GuidedCaptureView(defaultRegion: .frontal)
            }
        }
    }

    private var refillRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        let upper = Calendar.current.date(byAdding: .day, value: 180, to: today) ?? today
        return today...max(today, upper)
    }

    // MARK: Type-aware field copy
    //
    // The category reshapes the form: a shampoo or oil has an "Amount" (there's no mg/mL), and
    // every type gets a name/dose placeholder in its own language so the fields never read like a
    // medication when the item isn't one.

    private var doseLabel: String {
        switch treatmentClass {
        case .shampoo, .oil: return "Amount"
        default: return "Dose"
        }
    }

    private var dosePlaceholder: String {
        switch treatmentClass {
        case .minoxidil: return "e.g. 1 mL"
        case .finasteride, .dutasteride: return "e.g. 1 mg"
        case .spironolactone: return "e.g. 100 mg"
        case .microneedling: return "e.g. 1.5 mm roller"
        case .prp, .lllt: return "e.g. per clinic protocol"
        case .shampoo: return "e.g. coin-sized, 2\u{2013}3\u{00d7} a week"
        case .oil: return "e.g. a few drops, a few evenings a week"
        case .supplement: return "e.g. 1 capsule (5000 mcg)"
        case .other: return "e.g. as directed"
        }
    }

    private var namePlaceholder: String {
        switch treatmentClass {
        case .minoxidil: return "e.g. Minoxidil 5%"
        case .finasteride: return "e.g. Finasteride 1 mg"
        case .dutasteride: return "e.g. Dutasteride 0.5 mg"
        case .spironolactone: return "e.g. Spironolactone 100 mg"
        case .microneedling: return "e.g. Dermaroller"
        case .prp: return "e.g. PRP session"
        case .lllt: return "e.g. Laser cap"
        case .shampoo: return "e.g. Ketoconazole 2% shampoo"
        case .oil: return "e.g. Rosemary oil"
        case .supplement: return "e.g. Biotin 5000 mcg"
        case .other: return "e.g. your product\u{2019}s name"
        }
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
                        .font(Clinical.caption(11))
                        .foregroundStyle(applied ? Clinical.accent : Clinical.gold)
                    Text(p.label)
                        .font(Clinical.body(13, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                }
                Text(p.summary)
                    .font(Clinical.caption(11)).foregroundStyle(Clinical.secondary)
                Text(p.note)
                    .font(Clinical.caption(10)).foregroundStyle(Clinical.tertiary)
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
            .font(Clinical.caption(16))
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
                        .font(Clinical.body(14, weight: .medium))
                }
                .buttonStyle(ClinicalButtonStyle(filled: false))
                .onChange(of: ingredientPickerItem) { _, item in loadIngredientPhoto(item) }

                if !detectedLabelText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Read on the label", systemImage: "text.viewfinder")
                            .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.tertiary)
                        Text(detectedLabelText)
                            .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                            .lineLimit(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                }

                if ingredientImage != nil, analysisService.isAvailable {
                    Button(action: analyzeIngredientsTapped) {
                        Label(analysisService.isRunning ? "Analyzing…" : "Analyze with AI", systemImage: "sparkles")
                            .font(Clinical.body(14, weight: .medium))
                    }
                    .buttonStyle(ClinicalButtonStyle(filled: false))
                    .disabled(analysisService.isRunning || detectedLabelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !aiIngredientSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(aiIngredientSummary)
                                .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                            Text("AI summary · not medical advice")
                                .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                        }
                    }

                    if let error = analysisService.errorMessage {
                        Text(error).font(Clinical.caption(12)).foregroundStyle(Clinical.critical)
                    }
                }

                Text("Reads the label on your device to identify what it is — private, nothing leaves your iPhone. Record-keeping, not medical advice.")
                    .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    private func loadIngredientPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) else { return }
            ingredientImage = ui
            aiIngredientSummary = ""
            detectedLabelText = ""
            if let path = PhotoStore.shared.save(ui) {
                ingredientPhotoPath = path
            }
            // On-device OCR — instant, free, private. Runs regardless of the AI consent gate.
            detectedLabelText = await TextScanner.recognizeText(in: ui)
        }
    }

    private func analyzeIngredientsTapped() {
        guard ingredientImage != nil else { return }
        // Fully on-device: the label was already read by Vision OCR (loadIngredientPhoto) and the
        // summary is generated by Apple Intelligence without anything leaving the device — no consent.
        runIngredientAnalysis()
    }

    private func runIngredientAnalysis() {
        let labelText = detectedLabelText
        Task {
            if let summary = await analysisService.analyzeIngredients(labelText: labelText) {
                aiIngredientSummary = summary
            }
        }
    }

    private func save() {
        // Safety first: if she's pregnant / trying / breastfeeding and this is one of the
        // medications usually avoided then, pause on the honest note before the Rx check. "Add
        // anyway" (from that card) continues here via `proceedAfterPregnancyCaution`.
        if let info = PregnancyCaution.info(
            treatmentClass: treatmentClass,
            name: name.trimmingCharacters(in: .whitespaces),
            status: profiles.first?.pregnancyStatus ?? .unspecified
        ) {
            pregnancyInfo = info
            return
        }
        runRxCheckThenInsert()
    }

    /// Usually-prescription-only medications pause on a friendly confirmation instead of saving
    /// silently. The gate reads the final field values — never a preset's identity — so
    /// hand-edited names/doses are what get judged.
    private func runRxCheckThenInsert() {
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
            scheduledWeekdays: treatmentClass.supportsWeekdaySchedule ? scheduledWeekdays : [],
            startDate: startDate,
            isActive: true,
            refillBy: refillBy,
            ingredientPhotoPath: ingredientPhotoPath,
            aiIngredientSummary: aiIngredientSummary
        )
        context.insert(t)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if shouldPromptBaseline {
            showBaselinePrompt = true
        } else {
            dismiss()
        }
    }

    /// Only for a today-dated start (a backfilled/future start date isn't "right now"), and only
    /// when there's no photo already near it — so a treatment added to a record that already has
    /// a recent photo set, or backfilled after the fact, is never asked.
    private var shouldPromptBaseline: Bool {
        guard Calendar.current.isDateInToday(startDate) else { return false }
        return !HairAnalytics.hasNearbyDate(anchor: startDate, candidates: photoRecords.map(\.createdAt))
    }
}
