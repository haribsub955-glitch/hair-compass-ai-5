import Charts
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct RoutineTab: View {
    @Environment(\.modelContext) private var modelContext
    let profile: HairProfile?
    let entries: [CheckInEntry]
    let tasks: [RoutineTask]
    let medications: [MedicationLog]
    let doseEntries: [MedicationDoseEntry]
    let routineCompletions: [RoutineCompletionEntry]
    let procedureEvents: [ProcedureEvent]
    let lifestyleEntries: [LifestyleEntry]
    let healthInsights: HealthInsightsStore
    let labResults: [LabResultEntry]
    let triggerEvents: [HairTriggerEvent]

    @State private var isPresentingAddTask = false
    @State private var isPresentingAddMedication = false
    @State private var selectedMedicationForEntry: MedicationLog?
    @State private var selectedApprovedMedication: ApprovedMedicationInfo?
    @State private var isPresentingAddProcedure = false
    @State private var selectedLifestyleCategory: LifestyleCategory?
    @State private var selectedSupplementForRoutine: EvidenceBasedSupplementInfo?
    @State private var selectedHairCareForRoutine: EvidenceBasedHairCareInfo?
    @State private var selectedLabTest: HairRelevantLabTest?
    @State private var isPresentingAddLabResult = false
    @State private var selectedTriggerCategory: HairTriggerCategory?
    @State private var selectedLibraryDestination: RoutineLibraryDestination?
    @State private var selectedDate = Date()
    @State private var selectedWorkspace: RoutineWorkspace = .plan

    private var suggestedHairCare: [HairCareRecommendation] {
        HairCareRecommendationEngine.build(
            profile: profile,
            entries: entries,
            triggerEvents: triggerEvents,
            existingTasks: tasks
        )
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? calendar.startOfDay(for: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var selectedWeekday: Int {
        Calendar.current.component(.weekday, from: selectedDate)
    }

    private var selectedDayAgenda: [RoutineAgendaEntry] {
        let scheduledTasks = tasks
            .filter { doesTask($0, occurOn: selectedDate) }
            .map {
                RoutineAgendaEntry(
                    id: "task-\($0.persistentModelID)",
                    title: $0.title,
                    detail: $0.detail,
                    category: $0.category,
                    timeLabel: $0.timeLabel,
                    bucket: bucket(for: $0.timeLabel),
                    source: .task($0),
                    isCompleted: isTaskCompleted($0, on: selectedDate)
                )
            }

        let scheduledMedications = medications
            .filter(\.isActive)
            .flatMap { medication in
                scheduledTimes(for: medication).map { timeLabel in
                    RoutineAgendaEntry(
                        id: "med-\(medication.id.uuidString)-\(timeLabel)",
                        title: medication.name,
                        detail: "\(medication.dosage) • \(medication.schedule)",
                        category: "Medication",
                        timeLabel: timeLabel,
                        bucket: bucket(for: timeLabel),
                        source: .medication(medication),
                        isCompleted: isMedicationLogged(medication, on: selectedDate, timeLabel: timeLabel)
                    )
                }
            }

        return (scheduledTasks + scheduledMedications)
            .sorted { lhs, rhs in
                if lhs.bucket.sortOrder == rhs.bucket.sortOrder {
                    return lhs.timeLabel < rhs.timeLabel
                }
                return lhs.bucket.sortOrder < rhs.bucket.sortOrder
            }
    }

    private var groupedAgenda: [(bucket: RoutineAgendaBucket, entries: [RoutineAgendaEntry])] {
        let grouped = Dictionary(grouping: selectedDayAgenda, by: \.bucket)
        return RoutineAgendaBucket.allCases.compactMap { bucket in
            guard let items = grouped[bucket], !items.isEmpty else { return nil }
            return (bucket, items)
        }
    }

    private var trackingItemCount: Int {
        medications.count + procedureEvents.count + triggerEvents.count + lifestyleEntries.count + labResults.count
    }

    private var referenceItemCount: Int {
        MedicationEvidenceCatalog.androgeneticAlopecia.count +
        MedicationEvidenceCatalog.alopeciaAreata.count +
        HairLabCatalog.core.count +
        HairLabCatalog.selective.count +
        SupplementEvidenceCatalog.deficiencyDirected.count +
        SupplementEvidenceCatalog.limitedAntiDHT.count +
        HairCareEvidenceCatalog.valueAdding.count
    }

    private var workspaceSections: some View {
        Group {
            switch selectedWorkspace {
            case .plan:
                scheduleSection
                routineTasksSection
                quickAddSection
            case .tracking:
                medicationLogSection
                procedureEventsSection
                triggerHistorySection
                lifestyleHealthSection
                loggedLabResultsSection
                lifestyleLogSection
                routineActivitySummarySection
            case .reference:
                libraryHubSection
                approvedMedicationNotesSection
                evidenceBasedSupplementsSection
                hairCareValueSection
                coreHairLabsSection
                selectiveContextLabsSection
            }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Day agenda")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(PremiumTheme.ink)
                    Text("Pick a day to see its schedule. Medication slots follow the times you set for each product.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PremiumTheme.mutedInk)
                }

                weatherRoutineModule {
                    weekCalendarStrip
                }

                HStack {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(selectedDayAgenda.count) scheduled")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PremiumTheme.tealDeep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.85), in: Capsule())
                }

                if groupedAgenda.isEmpty {
                    ContentUnavailableView(
                        "No Items For This Day",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Select another day or add routine items so the agenda can distribute them.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                } else {
                    ForEach(groupedAgenda, id: \.bucket) { group in
                        agendaGroupCard(group)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var weekCalendarStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(weekDates, id: \.self) { day in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            selectedDate = day
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? .white : Color(red: 0.20, green: 0.24, blue: 0.22))
                        .frame(width: 54, height: 68)
                        .background(
                            Calendar.current.isDate(day, inSameDayAs: selectedDate)
                            ? LinearGradient(
                                colors: [PremiumTheme.forest, PremiumTheme.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.86), Color.white.opacity(0.54)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? 0.18 : 0.34), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func agendaGroupCard(_ group: (bucket: RoutineAgendaBucket, entries: [RoutineAgendaEntry])) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.bucket.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PremiumTheme.mutedInk)
                Spacer()
                Text("\(group.entries.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.28, green: 0.43, blue: 0.41))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.55), in: Capsule())
            }

            ForEach(group.entries) { item in
                RoutineAgendaRow(
                    item: item,
                    canMarkComplete: Calendar.current.isDateInToday(selectedDate)
                ) { task in
                    toggleTask(task, on: selectedDate)
                } onLogMedication: { medication, timeLabel in
                    logDose(for: medication, scheduledTimeLabel: timeLabel)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var routineTasksSection: some View {
        Section("Routine Tasks") {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "No Routine Yet",
                    systemImage: "checklist",
                    description: Text("Create a routine to stay consistent with wash, scalp care, and protection.")
                )
            } else {
                ForEach(groupedTasks, id: \.weekday) { section in
                    Section(weekdayName(for: section.weekday)) {
                        ForEach(section.tasks) { task in
                            routineTaskRow(task)
                        }
                        .onDelete { offsets in
                            deleteTasks(offsets: offsets, tasks: section.tasks)
                        }
                    }
                }
            }
        }
    }

    private var quickAddSection: some View {
        Section {
            Button {
                isPresentingAddMedication = true
            } label: {
                Label("Add Medication Record", systemImage: "pills.fill")
            }

            Button {
                isPresentingAddProcedure = true
            } label: {
                Label("Add Procedure Event", systemImage: "cross.case.fill")
            }

            Button {
                selectedLifestyleCategory = .supplement
            } label: {
                Label("Add Nutrition / Supplement Event", systemImage: "leaf.fill")
            }

            Button {
                selectedLifestyleCategory = .smoking
            } label: {
                Label("Add Smoking Event", systemImage: "smoke.fill")
            }

            Button {
                selectedLabTest = HairLabCatalog.core.first
                isPresentingAddLabResult = true
            } label: {
                Label("Log Lab Result", systemImage: "testtube.2")
            }

            Button {
                selectedTriggerCategory = .recentIllness
            } label: {
                Label("Add Trigger History", systemImage: "timeline.selection")
            }
        }
    }

    private var workspaceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Workspace")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(PremiumTheme.ink)

                Text("Planning, tracking, and the evidence library each have their own space.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PremiumTheme.mutedInk)

                HStack(spacing: 10) {
                    workspaceButton(.plan, subtitle: "\(selectedDayAgenda.count) today")
                    workspaceButton(.tracking, subtitle: "\(trackingItemCount) logged")
                    workspaceButton(.reference, subtitle: "\(referenceItemCount) items")
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var libraryHubSection: some View {
        Section("Browse by Category") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Open the exact library you need instead of scrolling through the whole routine screen.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PremiumTheme.mutedInk)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Button {
                        selectedLibraryDestination = .medications
                    } label: {
                        RoutineLibraryCard(
                            title: "Medications",
                            subtitle: "\(medications.count) tracked",
                            systemImage: "pills.fill",
                            tint: Color(red: 0.31, green: 0.51, blue: 0.80)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedLibraryDestination = .supplements
                    } label: {
                        RoutineLibraryCard(
                            title: "Supplements",
                            subtitle: "Evidence-based picks",
                            systemImage: "leaf.fill",
                            tint: Color(red: 0.34, green: 0.58, blue: 0.47)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedLibraryDestination = .hairCare
                    } label: {
                        RoutineLibraryCard(
                            title: "Hair Care",
                            subtitle: "\(HairCareEvidenceCatalog.valueAdding.count) value items",
                            systemImage: "shower.fill",
                            tint: Color(red: 0.35, green: 0.59, blue: 0.70)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedLibraryDestination = .labs
                    } label: {
                        RoutineLibraryCard(
                            title: "Labs",
                            subtitle: "\(labResults.count) logged",
                            systemImage: "testtube.2",
                            tint: Color(red: 0.73, green: 0.52, blue: 0.27)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedLibraryDestination = .procedures
                    } label: {
                        RoutineLibraryCard(
                            title: "Procedures",
                            subtitle: "\(procedureEvents.count) logged",
                            systemImage: "cross.case.fill",
                            tint: Color(red: 0.67, green: 0.44, blue: 0.70)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedLibraryDestination = .triggers
                    } label: {
                        RoutineLibraryCard(
                            title: "Triggers",
                            subtitle: "\(triggerEvents.count) in timeline",
                            systemImage: "timeline.selection",
                            tint: Color(red: 0.84, green: 0.46, blue: 0.28)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var medicationLogSection: some View {
        Section("Medication Log") {
            if medications.isEmpty {
                ContentUnavailableView(
                    "No Medications Logged",
                    systemImage: "pills",
                    description: Text("Track what you are using alongside your routine so it stays in one place.")
                )
            } else {
                ForEach(medications) { medication in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(medication.name)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Spacer()
                            Text(medication.isActive ? "Active" : "Stopped")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background((medication.isActive ? Color.green : Color.gray).opacity(0.14), in: Capsule())
                                .foregroundStyle(medication.isActive ? Color.green : Color.gray)
                        }

                        Text("\(medication.form)  •  \(medication.indication)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text("\(medication.dosage)  •  \(medication.frequencyPerDay)x daily")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(PremiumTheme.tealDeep)

                        Text("Started \(medication.startedAt, format: .dateTime.month().day().year())")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(medication.schedule)
                            .font(.system(size: 14, weight: .medium, design: .rounded))

                        Text(medication.prescribedByClinician ? "Clinician-directed" : "Self-initiated")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(medication.prescribedByClinician ? PremiumTheme.tealDeep : PremiumTheme.warmAmber)

                        Text(todayEntrySummary(for: medication))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.green)

                        if !medication.notes.isEmpty {
                            Text(medication.notes)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button {
                                logDose(
                                    for: medication,
                                    scheduledTimeLabel: scheduledTimes(for: medication).first ?? "09:00"
                                )
                            } label: {
                                Label("Log Now", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                selectedMedicationForEntry = medication
                            } label: {
                                Label("Detailed Entry", systemImage: "square.and.pencil")
                            }
                            .buttonStyle(.bordered)
                        }

                        let recentEntries = recentDoseEntries(for: medication)
                        if !recentEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Recent Entries")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                ForEach(recentEntries) { entry in
                                    HStack {
                                        Image(systemName: entry.wasTaken ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(entry.wasTaken ? Color.green : Color.red)
                                        Text(entry.loggedAt, format: .dateTime.month().day().hour().minute())
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                        if !entry.note.isEmpty {
                                            Text(entry.note)
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .swipeActions {
                        Button(medication.isActive ? "Stop" : "Resume") {
                            medication.isActive.toggle()
                        }
                        .tint(medication.isActive ? .orange : .green)
                    }
                }
                .onDelete(perform: deleteMedications)
            }
        }
    }

    private var approvedMedicationNotesSection: some View {
        Section("Approved Medication Notes") {
            ForEach(MedicationEvidenceCatalog.androgeneticAlopecia) { medication in
                MedicationEvidenceCard(medication: medication) {
                    selectedApprovedMedication = medication
                }
            }

            ForEach(MedicationEvidenceCatalog.alopeciaAreata) { medication in
                MedicationEvidenceCard(medication: medication) {
                    selectedApprovedMedication = medication
                }
            }
        }
    }

    private var procedureEventsSection: some View {
        Section("Procedure Events") {
            if procedureEvents.isEmpty {
                ContentUnavailableView(
                    "No Procedures Logged",
                    systemImage: "cross.case",
                    description: Text("Log sessions like PRP, injectable dutasteride, microneedling, or other interventions so they can appear in your charts.")
                )
            } else {
                ForEach(procedureEvents) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(event.title)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Spacer()
                            Text(event.category)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.89, green: 0.93, blue: 0.97), in: Capsule())
                                .foregroundStyle(PremiumTheme.tealDeep)
                        }

                        Text(event.performedAt, format: .dateTime.month().day().year())
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(event.procedureDescription)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        if !event.clinicianName.isEmpty {
                            Text("Provider: \(event.clinicianName)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.26, green: 0.56, blue: 0.42))
                        }

                        if !event.notes.isEmpty {
                            Text(event.notes)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var triggerHistorySection: some View {
        Section("Trigger History") {
            VStack(alignment: .leading, spacing: 8) {
                Text("High-yield trigger history matters because shedding often appears weeks later. Log illness, surgery, postpartum change, calorie restriction, new medications, traction changes, and seborrheic dermatitis activity here.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if triggerEvents.isEmpty {
                ContentUnavailableView(
                    "No Trigger History Logged",
                    systemImage: "timeline.selection",
                    description: Text("Add trigger events so the chart can compare later shedding and scalp changes against them.")
                )
            } else {
                ForEach(triggerEvents) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(event.title)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Spacer()
                            Text(event.category)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.95, green: 0.92, blue: 0.84), in: Capsule())
                        }

                        Text(triggerDateSummary(for: event))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(event.details)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text("Lag-aware charting will weigh this event most heavily about 2 to 12 weeks later.")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.62, green: 0.41, blue: 0.15))
                    }
                    .padding(.vertical, 6)
                }
                .onDelete(perform: deleteTriggerEvents)
            }
        }
    }

    private var lifestyleHealthSection: some View {
        Section("Lifestyle + Health") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Apple Health")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Text("Sleep, exercise, protein, and water can sync from Apple Health. Smoking and supplement events stay manual so you can log exactly what happened.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Button(healthInsights.authorizationState == .authorized ? "Refresh Health Data" : "Connect Apple Health") {
                    Task {
                        if healthInsights.authorizationState == .authorized {
                            await healthInsights.refresh()
                        } else {
                            await healthInsights.requestAccessAndRefresh()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                if let lastSyncDate = healthInsights.lastSyncDate {
                    Text("Last synced \(lastSyncDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.26, green: 0.56, blue: 0.42))
                }

                if let errorMessage = healthInsights.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var evidenceBasedSupplementsSection: some View {
        Section("Evidence-Based Supplements") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Most defensible for hair health are deficiency-directed supports, not generic supplement stacks.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("No supplement has anti-DHT evidence comparable to finasteride.")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
            }
            .padding(.vertical, 4)

            ForEach(SupplementEvidenceCatalog.deficiencyDirected) { supplement in
                SupplementEvidenceCard(supplement: supplement) {
                    selectedSupplementForRoutine = supplement
                }
            }

            ForEach(SupplementEvidenceCatalog.limitedAntiDHT) { supplement in
                SupplementEvidenceCard(supplement: supplement) {
                    selectedSupplementForRoutine = supplement
                }
            }
        }
    }

    private var hairCareValueSection: some View {
        Section("Hair Care That Adds Value") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The app should only push product categories that make scientific sense. The strongest value here is scalp-symptom control, breakage reduction, and irritation reduction, not cosmetic anti-DHT marketing.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if !suggestedHairCare.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested from your logs")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))

                    ForEach(suggestedHairCare) { recommendation in
                        SuggestedHairCareCard(recommendation: recommendation) {
                            selectedHairCareForRoutine = recommendation.item
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(HairCareEvidenceCatalog.valueAdding) { item in
                HairCareEvidenceCard(item: item) {
                    selectedHairCareForRoutine = item
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What not to overweight")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))

                ForEach(HairCareEvidenceCatalog.lowValueClaims, id: \.self) { claim in
                    Text("• \(claim)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var coreHairLabsSection: some View {
        Section("Core Hair Labs") {
            VStack(alignment: .leading, spacing: 8) {
                Text("These are the most sensible baseline items for common diffuse shedding or nonscarring hair-loss tracking. They should reflect real results, not guesses.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button {
                selectedLabTest = HairLabCatalog.core.first
                isPresentingAddLabResult = true
            } label: {
                Label("Add Lab Result", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            ForEach(HairLabCatalog.core) { test in
                Button {
                    selectedLabTest = test
                    isPresentingAddLabResult = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(test.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))
                            Spacer()
                            Text(test.evidenceStrength)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(PremiumTheme.tealDeep)
                        }
                        Text(test.rationale)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectiveContextLabsSection: some View {
        Section("Selective Context Labs") {
            VStack(alignment: .leading, spacing: 8) {
                Text("These are contextual, not universal defaults. Vitamin D, B12, folate, zinc, and androgen labs should usually be clinician-directed or based on actual risk/context.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            ForEach(HairLabCatalog.selective) { test in
                Button {
                    selectedLabTest = test
                    isPresentingAddLabResult = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(test.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))
                            Spacer()
                            Text(test.evidenceStrength)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.62, green: 0.41, blue: 0.15))
                        }
                        Text(test.rationale)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var loggedLabResultsSection: some View {
        Section("Logged Lab Results") {
            if labResults.isEmpty {
                ContentUnavailableView(
                    "No Lab Results Logged",
                    systemImage: "testtube.2",
                    description: Text("Add ferritin, CBC, thyroid, or other real lab results if you have them.")
                )
            } else {
                ForEach(labResults) { result in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(result.testName)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Spacer()
                            Text(result.status)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.89, green: 0.93, blue: 0.97), in: Capsule())
                        }

                        Text("\(result.valueText) \(result.unit)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(PremiumTheme.tealDeep)

                        Text(result.collectedAt, format: .dateTime.month().day().year())
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        if !result.notes.isEmpty {
                            Text(result.notes)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onDelete(perform: deleteLabResults)
            }
        }
    }

    private var lifestyleLogSection: some View {
        Section("Lifestyle Log") {
            if lifestyleEntries.isEmpty {
                ContentUnavailableView(
                    "No Lifestyle Events Logged",
                    systemImage: "heart.text.square",
                    description: Text("Log smoking or supplement events so charts can compare them with shedding and scalp changes.")
                )
            } else {
                ForEach(lifestyleEntries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.title)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Spacer()
                            Text(entry.category)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.89, green: 0.93, blue: 0.97), in: Capsule())
                        }

                        Text("\(entry.amount.formatted(.number.precision(.fractionLength(0...1)))) \(entry.unit)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(PremiumTheme.tealDeep)

                        Text(entry.loggedAt, format: .dateTime.month().day().year().hour().minute())
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        if !entry.notes.isEmpty {
                            Text(entry.notes)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onDelete(perform: deleteLifestyleEntries)
            }
        }
    }

    @ViewBuilder
    private var routineActivitySummarySection: some View {
        if !routineCompletions.isEmpty || !doseEntries.isEmpty {
            Section("Routine Activity Summary") {
                Text("Logged routine completions: \(routineCompletions.count)")
                Text("Logged medication entries: \(doseEntries.filter(\.wasTaken).count)")
                Text("Logged lifestyle events: \(lifestyleEntries.count)")
                Text("Logged lab results: \(labResults.count)")
            }
        }
    }

    private func workspaceButton(_ workspace: RoutineWorkspace, subtitle: String) -> some View {
        let isSelected = selectedWorkspace == workspace
        let tint = PremiumTheme.forest
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedWorkspace = workspace
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(workspace.title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .opacity(0.78)
            }
            .foregroundStyle(isSelected ? .white : Color(red: 0.15, green: 0.22, blue: 0.19))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                isSelected ? tint : Color.white.opacity(0.85),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func routineTaskRow(_ task: RoutineTask) -> some View {
        HStack(spacing: 14) {
            Button {
                toggleTask(task, on: .now)
            } label: {
                Image(systemName: isTaskCompleted(task, on: .now) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isTaskCompleted(task, on: .now) ? PremiumTheme.forest : Color.gray.opacity(0.8))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .strikethrough(isTaskCompleted(task, on: .now), color: .secondary)

                Text("\(task.itemType)  •  \(task.timeLabel)  •  \(task.category)  •  \(recurrenceSummary(for: task))")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(task.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if task.intelligenceScore > 0 || !task.intelligenceSummary.isEmpty {
                    HStack(spacing: 8) {
                        Text("AI \(task.intelligenceScore)/100")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(PremiumTheme.tealDeep)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PremiumTheme.teal.opacity(0.14), in: Capsule())
                        Text(task.intelligenceSummary)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var body: some View {
        List {
            Section {
                routineHeroCard
            }
            workspaceSection
            workspaceSections
        }
        .scrollContentBackground(.hidden)
        .background(
            ZStack {
                appBackground
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [PremiumTheme.forest.opacity(0.10), .clear],
                            center: .center, startRadius: 10, endRadius: 160
                        )
                    )
                    .frame(width: 300, height: 300)
                    .blur(radius: 50)
                    .offset(x: -80, y: -200)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [PremiumTheme.teal.opacity(0.08), .clear],
                            center: .center, startRadius: 10, endRadius: 130
                        )
                    )
                    .frame(width: 240, height: 240)
                    .blur(radius: 40)
                    .offset(x: 100, y: 300)
            }
            .ignoresSafeArea()
        )
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddTask = true
                } label: {
                    Label("Add Task", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddTask) {
            AddTaskSheet(profile: profile)
        }
        .sheet(isPresented: $isPresentingAddMedication) {
            AddMedicationSheet()
        }
        .sheet(isPresented: $isPresentingAddProcedure) {
            AddProcedureEventSheet()
        }
        .sheet(item: $selectedMedicationForEntry) { medication in
            AddMedicationDoseSheet(medication: medication)
        }
        .sheet(item: $selectedApprovedMedication) { medication in
            QuickAddApprovedMedicationSheet(medication: medication)
        }
        .sheet(item: $selectedLifestyleCategory) { category in
            AddLifestyleEntrySheet(category: category)
        }
        .sheet(item: $selectedSupplementForRoutine) { supplement in
            QuickAddSupplementRoutineSheet(supplement: supplement)
        }
        .sheet(item: $selectedHairCareForRoutine) { item in
            QuickAddHairCareRoutineSheet(item: item)
        }
        .sheet(isPresented: $isPresentingAddLabResult, onDismiss: {
            selectedLabTest = nil
        }) {
            AddLabResultSheet(initialTest: selectedLabTest)
        }
        .sheet(item: $selectedTriggerCategory) { category in
            AddTriggerEventSheet(category: category)
        }
        .navigationDestination(item: $selectedLibraryDestination) { destination in
            switch destination {
            case .medications:
                MedicationTab(medications: medications)
            case .supplements:
                SupplementLibraryView()
            case .hairCare:
                HairCareLibraryView(suggestedHairCare: suggestedHairCare)
            case .labs:
                LabLibraryView()
            case .procedures:
                ProcedureLibraryView(procedureEvents: procedureEvents)
            case .triggers:
                TriggerLibraryView(triggerEvents: triggerEvents)
            }
        }
    }

    private var routineHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "checklist")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(PremiumTheme.forest, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: PremiumTheme.forest.opacity(0.35), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Plan")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(PremiumTheme.ink)
                    Text("Schedule, treatments & tracking")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PremiumTheme.mutedInk)
                }
                Spacer()
                Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(PremiumTheme.forest)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PremiumTheme.forest.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 10) {
                routineHeroMetric(title: "Today", value: "\(selectedDayAgenda.count) items", tint: PremiumTheme.forest)
                routineHeroMetric(title: "Tasks", value: "\(tasks.count)", tint: PremiumTheme.teal)
                routineHeroMetric(title: "Meds", value: "\(medications.filter(\.isActive).count)", tint: PremiumTheme.gold)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }

    private func routineHeroMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(PremiumTheme.mutedInk)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
    }

    private func weatherRoutineModule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PremiumTheme.forest.opacity(0.06), lineWidth: 1)
            )
    }

    private var groupedTasks: [(weekday: Int, tasks: [RoutineTask])] {
        let grouped = Dictionary(grouping: tasks, by: { primaryWeekday(for: $0) })
        return grouped.keys.sorted().map { weekday in
            let weekdayTasks = (grouped[weekday] ?? []).sorted { $0.timeLabel < $1.timeLabel }
            return (weekday, weekdayTasks)
        }
    }

    private func weekdayName(for weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = min(max(weekday - 1, 0), symbols.count - 1)
        return symbols[index]
    }

    private func deleteTasks(offsets: IndexSet, tasks: [RoutineTask]) {
        for index in offsets {
            modelContext.delete(tasks[index])
        }
    }

    private func deleteMedications(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(medications[index])
        }
    }

    private func deleteLifestyleEntries(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(lifestyleEntries[index])
        }
    }

    private func deleteLabResults(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(labResults[index])
        }
    }

    private func deleteTriggerEvents(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(triggerEvents[index])
        }
    }

    private func toggleTask(_ task: RoutineTask, on date: Date) {
        let calendar = Calendar.current
        if let existing = completionEntry(for: task, on: date) {
            modelContext.delete(existing)
            if calendar.isDateInToday(date) {
                task.isCompleted = false
            }
            HapticHelper.light()
        } else {
            modelContext.insert(
                RoutineCompletionEntry(
                    task: task,
                    taskTitle: task.title,
                    category: task.category,
                    completedAt: date
                )
            )
            if calendar.isDateInToday(date) {
                task.isCompleted = true
            }
            HapticHelper.success()
        }
        task.updatedAt = .now
    }

    private func scheduledTimes(for medication: MedicationLog) -> [String] {
        MedicationScheduleFormatter.normalizedLabels(
            from: medication.scheduledTimes,
            fallbackFrequency: medication.frequencyPerDay
        )
    }

    private func bucket(for timeLabel: String) -> RoutineAgendaBucket {
        let components = timeLabel.split(separator: ":")
        let hour = Int(components.first ?? "") ?? 12
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .midday
        case 17..<22:
            return .evening
        default:
            return .anytime
        }
    }

    private func completionEntry(for task: RoutineTask, on date: Date) -> RoutineCompletionEntry? {
        routineCompletions.first {
            (($0.task?.persistentModelID == task.persistentModelID) || ($0.task == nil && $0.taskTitle == task.title)) &&
            Calendar.current.isDate($0.completedAt, inSameDayAs: date)
        }
    }

    private func isTaskCompleted(_ task: RoutineTask, on date: Date) -> Bool {
        completionEntry(for: task, on: date) != nil
    }

    private func isMedicationLogged(_ medication: MedicationLog, on date: Date, timeLabel: String) -> Bool {
        doseEntries.contains {
            (($0.medication?.id == medication.id) || ($0.medication == nil && $0.medicationName == medication.name)) &&
            $0.wasTaken &&
            Calendar.current.isDate($0.loggedAt, inSameDayAs: date) &&
            (
                $0.scheduledTimeLabel == timeLabel ||
                ($0.scheduledTimeLabel.isEmpty && timeLabel == scheduledTimes(for: medication).first)
            )
        }
    }

    private func doesTask(_ task: RoutineTask, occurOn date: Date) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let startDay = calendar.startOfDay(for: task.startDate)
        let endDay = task.endDate.map { calendar.startOfDay(for: $0) }

        guard day >= startDay else { return false }
        if let endDay, day > endDay { return false }

        let recurrence = RoutineRecurrenceType(rawValue: task.recurrenceType) ?? .weekly
        switch recurrence {
        case .daily:
            return true
        case .weekly:
            let configuredWeekdays = recurrenceWeekdays(for: task)
            let weekday = calendar.component(.weekday, from: day)
            return configuredWeekdays.contains(weekday)
        case .everyNDays:
            let offset = calendar.dateComponents([.day], from: startDay, to: day).day ?? 0
            return offset % max(1, task.recurrenceInterval) == 0
        case .monthly:
            let startComponents = calendar.dateComponents([.day], from: startDay)
            let dayComponents = calendar.dateComponents([.day], from: day)
            return startComponents.day == dayComponents.day
        }
    }

    private func recurrenceWeekdays(for task: RoutineTask) -> [Int] {
        let raw = task.recurrenceWeekdays
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return raw.isEmpty ? [task.weekday] : raw
    }

    private func primaryWeekday(for task: RoutineTask) -> Int {
        recurrenceWeekdays(for: task).first ?? task.weekday
    }

    private func recurrenceSummary(for task: RoutineTask) -> String {
        let recurrence = RoutineRecurrenceType(rawValue: task.recurrenceType) ?? .weekly
        switch recurrence {
        case .daily:
            return "Daily"
        case .weekly:
            let labels = recurrenceWeekdays(for: task).map { Calendar.current.shortWeekdaySymbols[$0 - 1] }
            return labels.joined(separator: ", ")
        case .everyNDays:
            return "Every \(max(1, task.recurrenceInterval)) days"
        case .monthly:
            let day = Calendar.current.component(.day, from: task.startDate)
            return "Monthly on day \(day)"
        }
    }

    private func todayEntrySummary(for medication: MedicationLog) -> String {
        let count = doseEntries.filter {
            (($0.medication?.id == medication.id) || ($0.medication == nil && $0.medicationName == medication.name)) &&
            Calendar.current.isDateInToday($0.loggedAt) &&
            $0.wasTaken
        }.count
        return count == 0 ? "No entry today" : "\(count) of \(scheduledTimes(for: medication).count) slots logged today"
    }

    private func recentDoseEntries(for medication: MedicationLog) -> [MedicationDoseEntry] {
        Array(doseEntries.filter {
            ($0.medication?.id == medication.id) || ($0.medication == nil && $0.medicationName == medication.name)
        }.prefix(3))
    }

    private func logDose(for medication: MedicationLog, scheduledTimeLabel: String) {
        let entry = MedicationDoseEntry(
            medication: medication,
            medicationName: medication.name,
            form: medication.form,
            loggedAt: mergedMedicationDate(from: .now, using: scheduledTimeLabel),
            scheduledTimeLabel: scheduledTimeLabel,
            wasTaken: true,
            note: ""
        )
        modelContext.insert(entry)
    }

    private func triggerDateSummary(for event: HairTriggerEvent) -> String {
        if let endedAt = event.endedAt {
            return "\(event.startedAt.formatted(date: .abbreviated, time: .omitted)) to \(endedAt.formatted(date: .abbreviated, time: .omitted)) • \(event.severity)"
        }
        return "\(event.startedAt.formatted(date: .abbreviated, time: .omitted)) • \(event.severity)"
    }
}

