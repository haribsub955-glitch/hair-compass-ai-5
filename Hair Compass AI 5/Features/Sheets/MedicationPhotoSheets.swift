import Charts
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct AddLifestyleEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let category: LifestyleCategory

    @State private var title: String
    @State private var amount: Double
    @State private var unit: String
    @State private var loggedAt = Date()
    @State private var notes = ""

    init(category: LifestyleCategory) {
        self.category = category
        _title = State(initialValue: category.suggestedTitles.first ?? "")
        _amount = State(initialValue: 1)
        _unit = State(initialValue: category.defaultUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    Picker("Template", selection: $title) {
                        ForEach(category.suggestedTitles, id: \.self) { suggestion in
                            Text(suggestion).tag(suggestion)
                        }
                    }

                    TextField("Custom title", text: $title)
                    TextField("Unit", text: $unit)

                    Stepper(
                        "Amount: \(amount.formatted(.number.precision(.fractionLength(0...1))))",
                        value: $amount,
                        in: 0.5...20,
                        step: 0.5
                    )

                    DatePicker("Logged at", selection: $loggedAt)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle(category == .smoking ? "Add Smoking Event" : "Add Nutrition Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = LifestyleEntry(
                            category: category.rawValue,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (category.suggestedTitles.first ?? category.title) : title,
                            amount: amount,
                            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.defaultUnit : unit,
                            loggedAt: loggedAt,
                            notes: notes
                        )
                        modelContext.insert(entry)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var indication = "Pattern hair loss"
    @State private var form = "Topical"
    @State private var dosage = ""
    @State private var frequencyPerDay = 1
    @State private var schedule = ""
    @State private var scheduledTimes = [medicationTimeDate(from: "09:00")]
    @State private var startedAt = Date()
    @State private var prescribedByClinician = false
    @State private var notes = ""

    private let indications = [
        "Pattern hair loss",
        "Severe alopecia areata",
        "Other clinician-defined indication"
    ]

    private let forms = [
        "Topical",
        "Oral",
        "Injection",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Medication Name", text: $name)

                Picker("Indication", selection: $indication) {
                    ForEach(indications, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }

                Picker("Form", selection: $form) {
                    ForEach(forms, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }

                TextField("Schedule", text: $schedule)
                TextField("Dosage", text: $dosage)
                Stepper("Frequency per day: \(frequencyPerDay)", value: $frequencyPerDay, in: 1...4)
                    .onChange(of: frequencyPerDay) { _, newValue in
                        scheduledTimes = syncedMedicationDates(from: scheduledTimes, targetCount: newValue)
                    }
                Section("Scheduled times") {
                    ForEach(Array(scheduledTimes.indices), id: \.self) { index in
                        DatePicker(
                            "Slot \(index + 1)",
                            selection: Binding(
                                get: { scheduledTimes[index] },
                                set: { scheduledTimes[index] = $0 }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
                DatePicker("Started", selection: $startedAt, displayedComponents: .date)
                Toggle("Prescribed by clinician", isOn: $prescribedByClinician)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("Add Medication")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let medication = MedicationLog(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Medication" : name,
                            indication: indication,
                            form: form,
                            dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Per label or clinician instructions" : dosage,
                            frequencyPerDay: frequencyPerDay,
                            schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Follow label or clinician instructions" : schedule,
                            scheduledTimes: MedicationScheduleFormatter.encodedString(from: scheduledTimes.map(medicationTimeLabel(from:))),
                            startedAt: startedAt,
                            prescribedByClinician: prescribedByClinician,
                            notes: notes
                        )
                        modelContext.insert(medication)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QuickAddApprovedMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let medication: ApprovedMedicationInfo

    @State private var dosage: String
    @State private var frequencyPerDay: Int
    @State private var scheduledTimes: [Date]
    @State private var prescribedByClinician = false

    init(medication: ApprovedMedicationInfo) {
        self.medication = medication
        _dosage = State(initialValue: medication.defaultDosage)
        _frequencyPerDay = State(initialValue: medication.defaultFrequencyPerDay)
        _scheduledTimes = State(initialValue: MedicationScheduleFormatter.defaultTimeLabels(for: medication.defaultFrequencyPerDay).map(medicationTimeDate(from:)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    Text(medication.name)
                    Text(medication.route)
                        .foregroundStyle(.secondary)
                    Text(medication.keyUse)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Section("Adjust") {
                    TextField("Dosage", text: $dosage)
                    Stepper("Frequency per day: \(frequencyPerDay)", value: $frequencyPerDay, in: 1...4)
                        .onChange(of: frequencyPerDay) { _, newValue in
                            scheduledTimes = syncedMedicationDates(from: scheduledTimes, targetCount: newValue)
                        }
                    ForEach(Array(scheduledTimes.indices), id: \.self) { index in
                        DatePicker(
                            "Slot \(index + 1)",
                            selection: Binding(
                                get: { scheduledTimes[index] },
                                set: { scheduledTimes[index] = $0 }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                    Toggle("Prescribed by clinician", isOn: $prescribedByClinician)
                }
            }
            .navigationTitle("Add to Routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let timeLabels = scheduledTimes.map(medicationTimeLabel(from:))
                        let schedule = MedicationScheduleFormatter.displaySummary(for: timeLabels)
                        let log = MedicationLog(
                            name: medication.name,
                            indication: medication.keyUse,
                            form: medication.route,
                            dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? medication.defaultDosage : dosage,
                            frequencyPerDay: frequencyPerDay,
                            schedule: schedule,
                            scheduledTimes: MedicationScheduleFormatter.encodedString(from: timeLabels),
                            prescribedByClinician: prescribedByClinician,
                            notes: "Added from approved medication quick add."
                        )
                        modelContext.insert(log)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddProcedureEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String
    @State private var category: String
    @State private var performedAt = Date()
    @State private var procedureDescription: String
    @State private var clinicianName = ""
    @State private var notes = ""
    @State private var createPhotoFollowUpPlan: Bool

    private let categories = [
        "Injection",
        "Microneedling",
        "PRP",
        "Laser",
        "Clinic treatment",
        "Other"
    ]

    init(template: ProcedureArticle? = nil) {
        _title = State(initialValue: template?.title ?? "Injectable dutasteride")
        _category = State(initialValue: template?.category ?? "Injection")
        _procedureDescription = State(initialValue: template?.defaultDescription ?? "Record the procedure so you can compare later shedding and scalp trends.")
        _createPhotoFollowUpPlan = State(initialValue: template != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Procedure Title", text: $title)
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                DatePicker("Performed At", selection: $performedAt)
                TextField("Description", text: $procedureDescription, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Clinician / Clinic", text: $clinicianName)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)

                Section("Photo Follow-Up") {
                    Toggle("Create monthly follow-up photo reminder", isOn: $createPhotoFollowUpPlan)
                    Text("Use this when you want a standardized baseline now and same-angle reminder photos every month after the procedure.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Procedure")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let event = ProcedureEvent(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Procedure" : title,
                            category: category,
                            performedAt: performedAt,
                            procedureDescription: procedureDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Procedure event logged for chart comparison." : procedureDescription,
                            clinicianName: clinicianName,
                            notes: notes
                        )
                        modelContext.insert(event)

                        if createPhotoFollowUpPlan {
                            let calendar = Calendar.current
                            let followUpTask = RoutineTask(
                                title: "\(event.title) follow-up photos",
                                itemType: RoutineItemType.technique.rawValue,
                                detail: "Capture baseline photos now, then repeat standardized same-angle photos monthly after \(event.title). Keep angle, lighting, wet or dry state, and hair parting consistent.",
                                timeLabel: "10:00",
                                weekday: calendar.component(.weekday, from: performedAt),
                                category: "Photos",
                                recurrenceType: RoutineRecurrenceType.monthly.rawValue,
                                recurrenceInterval: 1,
                                recurrenceWeekdays: "",
                                startDate: performedAt
                            )
                            modelContext.insert(followUpTask)
                        }

                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddMedicationDoseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let medication: MedicationLog

    @State private var loggedAt = Date()
    @State private var selectedSlot: String
    @State private var wasTaken = true
    @State private var note = ""

    init(medication: MedicationLog) {
        self.medication = medication
        _selectedSlot = State(initialValue: MedicationScheduleFormatter.normalizedLabels(from: medication.scheduledTimes, fallbackFrequency: medication.frequencyPerDay).first ?? "09:00")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    Text(medication.name)
                    Text("\(medication.form)  •  \(medication.schedule)")
                        .foregroundStyle(.secondary)
                }

                Picker("Scheduled slot", selection: $selectedSlot) {
                    ForEach(MedicationScheduleFormatter.normalizedLabels(from: medication.scheduledTimes, fallbackFrequency: medication.frequencyPerDay), id: \.self) { time in
                        Text(time).tag(time)
                    }
                }
                DatePicker("Time", selection: $loggedAt)
                    .onAppear {
                        loggedAt = mergedMedicationDate(from: loggedAt, using: selectedSlot)
                    }
                    .onChange(of: selectedSlot) { _, newValue in
                        loggedAt = mergedMedicationDate(from: loggedAt, using: newValue)
                    }
                Toggle("Taken / Applied", isOn: $wasTaken)
                TextField("Notes", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("Medication Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = MedicationDoseEntry(
                            medication: medication,
                            medicationName: medication.name,
                            form: medication.form,
                            loggedAt: loggedAt,
                            scheduledTimeLabel: selectedSlot,
                            wasTaken: wasTaken,
                            note: note
                        )
                        modelContext.insert(entry)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PhotoRecordsTab: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var purchaseManager: PurchaseManager
    let photoRecords: [PhotoRecord]
    let profile: HairProfile?

    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @State private var isPresentingCapture = false
    @State private var isAnalyzing = false
    @State private var analysisError = ""
    @State private var selectedSession: String?
    @State private var comparisonRequest: PhotoComparisonRequest?
    @State private var isPresentingPremiumPaywall = false

    private var groupedSessions: [(session: String, records: [PhotoRecord])] {
        let grouped = Dictionary(grouping: photoRecords, by: \.sessionTitle)
        return grouped.keys.sorted(by: >).map { key in
            let records = (grouped[key] ?? []).sorted { $0.angle < $1.angle }
            return (key, records)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(PremiumTheme.teal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: PremiumTheme.teal.opacity(0.35), radius: 8, y: 4)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Photo Journey")
                                .font(.system(size: 24, weight: .bold, design: .serif))
                                .foregroundStyle(PremiumTheme.ink)
                            Text("Multi-angle sessions & AI analysis")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PremiumTheme.mutedInk)
                        }
                        Spacer()
                        Text("\(photoRecords.count)")
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundStyle(PremiumTheme.teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PremiumTheme.teal.opacity(0.12), in: Capsule())
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SESSIONS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(PremiumTheme.mutedInk)
                            Text("\(groupedSessions.count)")
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .foregroundStyle(PremiumTheme.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(PremiumTheme.forest.opacity(0.06), lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI STATUS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(PremiumTheme.mutedInk)
                            Text(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No key" : "Ready")
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .foregroundStyle(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? PremiumTheme.gold : PremiumTheme.forest)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        )
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Compare the same angle under the same conditions.")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Best comparisons keep angle, lighting, wet or dry state, and hair parting the same. The compare flow only pairs records from the same angle.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    isPresentingCapture = true
                } label: {
                    Label("Capture Multi-Angle Session", systemImage: "camera.fill")
                }
            }

            if groupedSessions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Photo Sessions Yet",
                        systemImage: "camera.viewfinder",
                        description: Text("Capture front, temple, top, crown, or back photos to build a visual record.")
                    )
                }
            } else {
                ForEach(groupedSessions, id: \.session) { session in
                    Section(session.session) {
                        ForEach(session.records) { record in
                            HStack(alignment: .top, spacing: 14) {
                                PhotoThumbnailView(imagePath: record.imagePath)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.angle)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                    Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    if !record.notes.isEmpty {
                                        Text(record.notes)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    if !record.analysisSummary.isEmpty {
                                        Text(record.analysisSummary)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color(red: 0.18, green: 0.32, blue: 0.29))
                                            .lineLimit(4)
                                    }

                                    if let comparison = comparisonCandidate(for: record) {
                                        Button {
                                            comparisonRequest = PhotoComparisonRequest(primary: record, comparison: comparison)
                                        } label: {
                                            Label("Compare same angle", systemImage: "square.split.2x1")
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Button {
                            if purchaseManager.hasPremiumAccess {
                                Task {
                                    await analyze(session: session.session)
                                }
                            } else {
                                isPresentingPremiumPaywall = true
                            }
                        } label: {
                            if purchaseManager.hasPremiumAccess && isAnalyzing && selectedSession == session.session {
                                ProgressView()
                            } else if purchaseManager.hasPremiumAccess {
                                Label("Analyze This Session with GPT", systemImage: "sparkles")
                            } else {
                                Label("Unlock Session Analysis", systemImage: "lock.fill")
                            }
                        }
                        .disabled(purchaseManager.hasPremiumAccess && (isAnalyzing || openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    }
                }
            }

            if !analysisError.isEmpty {
                Section("Analysis Error") {
                    Text(analysisError)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(
            ZStack {
                appBackground
                Circle()
                    .fill(Color(red: 0.63, green: 0.45, blue: 0.73).opacity(0.12))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: -80, y: -200)
                Circle()
                    .fill(PremiumTheme.gold.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .blur(radius: 50)
                    .offset(x: 100, y: 300)
            }
            .ignoresSafeArea()
        )
        .navigationTitle("Photo Records")
        .sheet(isPresented: $isPresentingCapture) {
            CapturePhotoSessionSheet()
        }
        .sheet(isPresented: $isPresentingPremiumPaywall) {
            PremiumPaywallView()
        }
        .sheet(item: $comparisonRequest) { request in
            PhotoComparisonSheet(request: request)
        }
    }

    @MainActor
    private func analyze(session: String) async {
        guard purchaseManager.hasPremiumAccess else {
            analysisError = "Hair Compass Pro is required for AI photo session analysis."
            return
        }

        guard let sessionGroup = groupedSessions.first(where: { $0.session == session }) else { return }

        isAnalyzing = true
        selectedSession = session
        analysisError = ""

        defer {
            isAnalyzing = false
            selectedSession = nil
        }

        do {
            let summary = try await OpenAIAnalysisService(apiKey: openAIAPIKey)
                .analyze(records: sessionGroup.records, profile: profile)

            for record in sessionGroup.records {
                record.analysisSummary = summary
                record.analysisUpdatedAt = .now
            }
        } catch {
            analysisError = error.localizedDescription
        }
    }

    private func comparisonCandidate(for record: PhotoRecord) -> PhotoRecord? {
        photoRecords
            .filter { $0.id != record.id && $0.angle == record.angle }
            .sorted { $0.createdAt > $1.createdAt }
            .first { $0.createdAt < record.createdAt }
    }
}

struct CapturePhotoSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var sessionTitle = "Session \(Date.now.formatted(date: .abbreviated, time: .omitted))"
    @State private var angleImages: [PhotoAngle: UIImage] = [:]
    @State private var angleNotes: [PhotoAngle: String] = [:]
    @State private var pickerAngle: PhotoAngle?
    @State private var pickerItem: PhotosPickerItem?
    @State private var cameraAngle: PhotoAngle?
    @State private var isShowingCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Session Title", text: $sessionTitle)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Capture the same angles over time with consistent lighting, distance, and styling for more reliable comparison.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        standardizationBullet("Same angle each session")
                        standardizationBullet("Same lighting and room setup")
                        standardizationBullet("Same wet or dry hair state")
                        standardizationBullet("Same hair parting")
                        standardizationBullet("Use fixed interval comparisons such as monthly")
                    }

                    ForEach(PhotoAngle.allCases) { angle in
                        angleCard(angle)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Photo Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSession()
                    }
                    .disabled(angleImages.isEmpty)
                }
            }
        }
        .photosPicker(isPresented: Binding(
            get: { pickerAngle != nil },
            set: { if !$0 { pickerAngle = nil } }
        ), selection: $pickerItem, matching: .images)
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView { image in
                if let cameraAngle, let image {
                    angleImages[cameraAngle] = image
                }
                cameraAngle = nil
                isShowingCamera = false
            }
        }
        .task(id: pickerItem) {
            guard let pickerItem, let angle = pickerAngle else { return }
            if let data = try? await pickerItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                angleImages[angle] = image
            }
            self.pickerItem = nil
            self.pickerAngle = nil
        }
    }

    private func angleCard(_ angle: PhotoAngle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(angle.rawValue)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Text(angle.capturePrompt)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let image = angleImages[angle] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.7))
                    .frame(height: 120)
                    .overlay(
                        Text("No image yet")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    )
            }

            TextField("Notes for \(angle.rawValue)", text: Binding(
                get: { angleNotes[angle, default: ""] },
                set: { angleNotes[angle] = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    cameraAngle = angle
                    isShowingCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    pickerAngle = angle
                } label: {
                    Label("Library", systemImage: "photo")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func saveSession() {
        let safeTitle = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Session \(Date.now.formatted(date: .abbreviated, time: .omitted))"
            : sessionTitle
        let observation = dailyObservation(for: .now)

        for (angle, image) in angleImages {
            do {
                let path = try PhotoFileStore.shared.save(image: image)
                let record = PhotoRecord(
                    sessionTitle: safeTitle,
                    angle: angle.rawValue,
                    imagePath: path,
                    notes: angleNotes[angle, default: ""],
                    dailyObservation: observation
                )
                modelContext.insert(record)
            } catch {
                continue
            }
        }

        dismiss()
    }

    private func dailyObservation(for date: Date) -> DailyObservation {
        let dayStart = Calendar.current.startOfDay(for: date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let descriptor = FetchDescriptor<DailyObservation>(
            predicate: #Predicate<DailyObservation> {
                $0.date >= dayStart && $0.date < nextDay
            }
        )

        if let observation = try? modelContext.fetch(descriptor).first {
            if observation.summary.isEmpty {
                observation.summary = "Photo session captured."
            }
            return observation
        }

        let observation = DailyObservation(date: dayStart, summary: "Photo session captured.")
        modelContext.insert(observation)
        return observation
    }

    private func standardizationBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.26, green: 0.56, blue: 0.42))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.34, green: 0.40, blue: 0.37))
        }
    }
}

struct PhotoThumbnailView: View {
    let imagePath: String

    var body: some View {
        Group {
            if let image = PhotoFileStore.shared.loadImage(at: imagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PhotoComparisonRequest: Identifiable {
    let primary: PhotoRecord
    let comparison: PhotoRecord

    var id: String { "\(primary.id.uuidString)-\(comparison.id.uuidString)" }
}

struct PhotoComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: PhotoComparisonRequest

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.primary.angle)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Side-by-side review is limited to the same angle so visual changes are easier to judge honestly.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        comparisonColumn(title: "Earlier", record: request.comparison)
                        comparisonColumn(title: "Latest", record: request.primary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Compare carefully")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        comparisonBullet("Use the same hair part and same wet or dry state before interpreting change.")
                        comparisonBullet("Lighting and camera distance can make density look better or worse.")
                        comparisonBullet("Interpret short gaps cautiously. Hair change often needs weeks to months.")
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Compare Photos")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func comparisonColumn(title: String, record: PhotoRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.40, green: 0.46, blue: 0.43))

            Group {
                if let image = PhotoFileStore.shared.loadImage(at: record.imagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.gray.opacity(0.16))
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))

            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.28, green: 0.48, blue: 0.42))
                .padding(.top, 3)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.34, green: 0.40, blue: 0.37))
        }
    }
}

func medicationTimeDate(from label: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter.date(from: label) ?? .now
}

func medicationTimeLabel(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

func syncedMedicationDates(from existing: [Date], targetCount: Int) -> [Date] {
    let defaults = MedicationScheduleFormatter.defaultTimeLabels(for: targetCount).map(medicationTimeDate(from:))
    if existing.count == targetCount {
        return existing
    }
    if existing.count > targetCount {
        return Array(existing.prefix(targetCount))
    }

    return existing + defaults.dropFirst(existing.count)
}

func mergedMedicationDate(from base: Date, using timeLabel: String) -> Date {
    let timeDate = medicationTimeDate(from: timeLabel)
    let calendar = Calendar.current
    let dayComponents = calendar.dateComponents([.year, .month, .day], from: base)
    let timeComponents = calendar.dateComponents([.hour, .minute], from: timeDate)
    return calendar.date(from: DateComponents(
        year: dayComponents.year,
        month: dayComponents.month,
        day: dayComponents.day,
        hour: timeComponents.hour,
        minute: timeComponents.minute
    )) ?? base
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            let image = info[.originalImage] as? UIImage
            completion(image)
        }
    }
}

struct DashboardPill: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.62))

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                Text(unit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let caption: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(PremiumTheme.mutedInk)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(PremiumTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            trendArrow

            Spacer(minLength: 0)

            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PremiumTheme.mutedInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PremiumTheme.forest.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: PremiumTheme.forest.opacity(0.05), radius: 10, y: 5)
    }

    @ViewBuilder
    private var trendArrow: some View {
        if caption.contains("lower") {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                Text("lower")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(PremiumTheme.forest)
        } else if caption.contains("higher") {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                Text("higher")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(PremiumTheme.gold)
        } else if caption.contains("Stable") {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                Text("steady")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(PremiumTheme.mutedInk)
        }
    }
}

