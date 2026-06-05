import Foundation
import SwiftData

struct HairInsightCalculator {
    static func averageScore(
        for entries: [CheckInEntry],
        keyPath: KeyPath<CheckInEntry, Int>
    ) -> Int {
        guard !entries.isEmpty else { return 0 }

        let total = entries.reduce(0) { partialResult, entry in
            partialResult + entry[keyPath: keyPath]
        }

        return Int((Double(total) / Double(entries.count)).rounded())
    }

    static func completionRate(for tasks: [RoutineTask]) -> Int {
        guard !tasks.isEmpty else { return 0 }

        let completedCount = tasks.filter(\.isCompleted).count
        return Int((Double(completedCount) / Double(tasks.count) * 100).rounded())
    }

    static func currentStreak(
        for entries: [CheckInEntry],
        calendar: Calendar = .current
    ) -> Int {
        let uniqueDays = Set(entries.map { calendar.startOfDay(for: $0.date) })
        guard let mostRecentDay = uniqueDays.max() else { return 0 }

        var streak = 0
        var day = mostRecentDay

        while uniqueDays.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = calendar.startOfDay(for: previousDay)
        }

        return streak
    }

    static func nextWashDate(
        from referenceDate: Date,
        frequencyDays: Int,
        preferredHour: Int,
        calendar: Calendar = .current
    ) -> Date {
        let nextDay = calendar.date(byAdding: .day, value: max(1, frequencyDays), to: referenceDate) ?? referenceDate
        var components = calendar.dateComponents([.year, .month, .day], from: nextDay)
        components.hour = preferredHour
        components.minute = 0
        return calendar.date(from: components) ?? nextDay
    }
}

enum SampleDataSeeder {
    static func seedIfNeeded(
        modelContext: ModelContext,
        profiles: [HairProfile],
        entries: [CheckInEntry],
        tasks: [RoutineTask]
    ) {
        guard profiles.isEmpty, entries.isEmpty, tasks.isEmpty else {
            return
        }

        let profile = HairProfile(
            name: "Harib",
            texture: "Wavy 2C / 3A",
            primaryGoal: "Length retention",
            washFrequencyDays: 4,
            preferredWashHour: 19,
            scalpSensitivity: "Balanced",
            hairLossFocus: HairLossFocus.androgeneticAlopecia.rawValue,
            patternDistribution: "Frontal and temple tracking",
            familyHistorySummary: "",
            hasCompletedOnboarding: false,
            notes: "Use this space for your own observations and clinician-directed tracking context."
        )

        modelContext.insert(profile)
    }

    /// Debug-only: seeds a populated, onboarding-complete profile with ~45 days of
    /// check-ins, routine completions, and medication doses so charts/insights can be
    /// inspected with realistic data. Gated behind the `HC_SEED_DEMO` launch argument,
    /// so it never runs for real users.
    static func seedDemoData(
        modelContext: ModelContext,
        profiles: [HairProfile],
        entries: [CheckInEntry]
    ) {
        guard entries.isEmpty else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -45, to: today) ?? today

        if let existing = profiles.first {
            existing.hasCompletedOnboarding = true
        } else {
            modelContext.insert(
                HairProfile(
                    name: "Demo",
                    texture: "Wavy 2C / 3A",
                    primaryGoal: "Length retention",
                    washFrequencyDays: 4,
                    preferredWashHour: 19,
                    scalpSensitivity: "Balanced",
                    hairLossFocus: HairLossFocus.androgeneticAlopecia.rawValue,
                    patternDistribution: "Frontal and temple tracking",
                    familyHistorySummary: "",
                    hasCompletedOnboarding: true,
                    notes: ""
                )
            )
        }

        let medication = MedicationLog(
            name: "Minoxidil 5%",
            indication: "Androgenetic alopecia",
            form: "Topical",
            dosage: "1 mL",
            frequencyPerDay: 2,
            schedule: "Morning and night",
            scheduledTimes: "08:00,21:00",
            startedAt: start,
            prescribedByClinician: true,
            isActive: true
        )
        modelContext.insert(medication)

        let task = RoutineTask(
            title: "Gentle scalp massage",
            detail: "5 minutes, fingertips only",
            timeLabel: "21:00",
            weekday: 2,
            category: "Scalp",
            recurrenceType: RoutineRecurrenceType.daily.rawValue,
            startDate: start
        )
        modelContext.insert(task)

        for offset in stride(from: 45, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            // Simulate realistic gaps: skip roughly one in three days.
            if offset % 3 == 1 { continue }

            let progress = Double(45 - offset) / 45.0           // 0 → 1 over the window
            let noise = Double((offset * 7) % 11) - 5            // deterministic -5...5

            func clamp(_ value: Double) -> Int { max(5, min(95, Int(value.rounded()))) }
            let shedding = clamp(70 - progress * 35 + noise)     // improving downward trend
            let stress = clamp(60 - progress * 20 + noise)
            let scalp = clamp(55 + progress * 30 + noise)
            let hydration = clamp(50 + progress * 25 + noise)

            modelContext.insert(
                CheckInEntry(
                    date: day,
                    scalpScore: scalp,
                    hydrationScore: hydration,
                    sheddingLevel: shedding,
                    stressLevel: stress,
                    hasItch: false,
                    hasFlaking: offset % 7 == 0,
                    hasScalpPain: false,
                    hasPatchyHairLoss: false,
                    hasTightStyleTension: false,
                    isWashDay: offset % 4 == 0,
                    note: ""
                )
            )

            if offset % 2 == 0 {
                modelContext.insert(
                    RoutineCompletionEntry(
                        task: task,
                        taskTitle: task.title,
                        category: task.category,
                        completedAt: day
                    )
                )
            }

            for slot in ["08:00", "21:00"] where offset % 5 != 2 {
                modelContext.insert(
                    MedicationDoseEntry(
                        medication: medication,
                        medicationName: medication.name,
                        form: medication.form,
                        loggedAt: day,
                        scheduledTimeLabel: slot,
                        wasTaken: true
                    )
                )
            }
        }

        try? modelContext.save()
    }
}

struct RoutineImpactPoint: Identifiable, Sendable {
    let date: Date
    let sheddingScore: Double
    let stressScore: Double
    let scalpScore: Double
    let hydrationScore: Double
    let routineActions: Int
    let medicationEntries: Int
    let minoxidilEntries: Int
    let expectedMedicationEntries: Int
    let expectedMinoxidilEntries: Int
    let procedureEvents: Int
    let dutasterideProcedureEvents: Int
    let sleepHours: Double
    let exerciseMinutes: Double
    let proteinGrams: Double
    let waterLiters: Double
    let smokingCount: Double
    let supplementEntries: Int
    let triggerEvents: Int
    let tractionEvents: Int
    let sebDermEvents: Int
    let recentTriggerLoad: Double
    let recentProcedureLoad: Double
    let hasCheckInData: Bool
    let hasHealthData: Bool

    init(
        date: Date,
        sheddingScore: Double,
        stressScore: Double,
        scalpScore: Double,
        hydrationScore: Double,
        routineActions: Int,
        medicationEntries: Int,
        minoxidilEntries: Int,
        expectedMedicationEntries: Int,
        expectedMinoxidilEntries: Int,
        procedureEvents: Int,
        dutasterideProcedureEvents: Int,
        sleepHours: Double,
        exerciseMinutes: Double,
        proteinGrams: Double,
        waterLiters: Double,
        smokingCount: Double,
        supplementEntries: Int,
        triggerEvents: Int,
        tractionEvents: Int,
        sebDermEvents: Int,
        recentTriggerLoad: Double,
        recentProcedureLoad: Double,
        hasCheckInData: Bool = true,
        hasHealthData: Bool = true
    ) {
        self.date = date
        self.sheddingScore = sheddingScore
        self.stressScore = stressScore
        self.scalpScore = scalpScore
        self.hydrationScore = hydrationScore
        self.routineActions = routineActions
        self.medicationEntries = medicationEntries
        self.minoxidilEntries = minoxidilEntries
        self.expectedMedicationEntries = expectedMedicationEntries
        self.expectedMinoxidilEntries = expectedMinoxidilEntries
        self.procedureEvents = procedureEvents
        self.dutasterideProcedureEvents = dutasterideProcedureEvents
        self.sleepHours = sleepHours
        self.exerciseMinutes = exerciseMinutes
        self.proteinGrams = proteinGrams
        self.waterLiters = waterLiters
        self.smokingCount = smokingCount
        self.supplementEntries = supplementEntries
        self.triggerEvents = triggerEvents
        self.tractionEvents = tractionEvents
        self.sebDermEvents = sebDermEvents
        self.recentTriggerLoad = recentTriggerLoad
        self.recentProcedureLoad = recentProcedureLoad
        self.hasCheckInData = hasCheckInData
        self.hasHealthData = hasHealthData
    }

    var id: Date { date }

    var combinedSupportScore: Int {
        routineActions + medicationEntries + supplementEntries
    }
}

struct HealthDailyMetric: Identifiable, Equatable, Sendable {
    let date: Date
    let sleepHours: Double
    let exerciseMinutes: Double
    let proteinGrams: Double
    let waterLiters: Double

    var id: Date { date }
}

enum LifestyleCategory: String, CaseIterable, Identifiable {
    case smoking = "Smoking"
    case supplement = "Supplement"

    var id: String { rawValue }

    var title: String { rawValue }

    var defaultUnit: String {
        switch self {
        case .smoking:
            return "count"
        case .supplement:
            return "serving"
        }
    }

    var suggestedTitles: [String] {
        switch self {
        case .smoking:
            return ["Cigarette", "Cigar", "Nicotine pouch", "Hookah"]
        case .supplement:
            return ["Protein shake", "Multivitamin", "Iron supplement", "Vitamin D"]
        }
    }
}

struct HairRelevantLabTest: Identifiable {
    let id: String
    let name: String
    let unitHint: String
    let rationale: String
    let evidenceStrength: String
    let category: String
}

enum HairLabCatalog {
    static let core: [HairRelevantLabTest] = [
        HairRelevantLabTest(
            id: "ferritin",
            name: "Ferritin",
            unitHint: "ng/mL",
            rationale: "Low iron stores are among the more defensible lab issues to review in diffuse shedding and nonscarring alopecia.",
            evidenceStrength: "Core baseline",
            category: "Core baseline"
        ),
        HairRelevantLabTest(
            id: "cbc-hemoglobin",
            name: "CBC / Hemoglobin",
            unitHint: "g/dL",
            rationale: "Helps capture anemia patterns that can overlap with low iron states and diffuse hair shedding.",
            evidenceStrength: "Core baseline",
            category: "Core baseline"
        ),
        HairRelevantLabTest(
            id: "tsh",
            name: "TSH / Thyroid",
            unitHint: "mIU/L",
            rationale: "Thyroid dysfunction can contribute to diffuse hair shedding and is worth tracking if tested.",
            evidenceStrength: "Core baseline",
            category: "Core baseline"
        )
    ]

    static let selective: [HairRelevantLabTest] = [
        HairRelevantLabTest(
            id: "vitamin-d",
            name: "25-OH Vitamin D",
            unitHint: "ng/mL",
            rationale: "Useful when deficiency risk exists or if a clinician included it in the workup. It should not be treated as a universal default explanation.",
            evidenceStrength: "Selective context test",
            category: "Selective context"
        ),
        HairRelevantLabTest(
            id: "b12",
            name: "Vitamin B12",
            unitHint: "pg/mL",
            rationale: "Useful mainly when deficiency risk exists or prior testing suggests low status.",
            evidenceStrength: "Selective context test",
            category: "Selective context"
        ),
        HairRelevantLabTest(
            id: "folate",
            name: "Folate",
            unitHint: "ng/mL",
            rationale: "More selective than ferritin or thyroid testing, but can matter in broader nutrition deficiency patterns.",
            evidenceStrength: "Selective context test",
            category: "Selective context"
        ),
        HairRelevantLabTest(
            id: "zinc",
            name: "Zinc",
            unitHint: "ug/dL",
            rationale: "Can be relevant in deficiency states, but routine zinc testing for every hair-loss case is not strongly supported.",
            evidenceStrength: "Selective context test",
            category: "Selective context"
        ),
        HairRelevantLabTest(
            id: "total-testosterone",
            name: "Total Testosterone",
            unitHint: "ng/dL",
            rationale: "Androgen testing is not a generic default for every hair-loss case. It is more appropriate when a clinician suspects a specific endocrine context.",
            evidenceStrength: "Selective endocrine context",
            category: "Selective endocrine context"
        ),
        HairRelevantLabTest(
            id: "dhea-s",
            name: "DHEA-S",
            unitHint: "ug/dL",
            rationale: "Consider only in selected endocrine or hyperandrogenism workups rather than as a routine hair-loss panel item.",
            evidenceStrength: "Selective endocrine context",
            category: "Selective endocrine context"
        )
    ]
}

enum HairLossFocus: String, CaseIterable, Identifiable {
    case androgeneticAlopecia = "Androgenetic alopecia"
    case alopeciaAreata = "Alopecia areata"
    case inflammatoryScarring = "Inflammatory / scarring warning pattern"
    case telogenEffluvium = "Telogen effluvium trigger history"
    case notSure = "Not sure yet"

    var id: String { rawValue }
}

enum HairTriggerCategory: String, CaseIterable, Identifiable {
    case recentIllness = "Recent illness / fever"
    case surgery = "Surgery / anesthesia"
    case postpartum = "Postpartum status"
    case weightLoss = "Weight loss / calorie restriction"
    case newMedication = "New medication"
    case tractionStyling = "Traction / styling change"
    case sebDerm = "Seborrheic dermatitis activity"

    var id: String { rawValue }

    var templateTitle: String {
        rawValue
    }

    var summary: String {
        switch self {
        case .recentIllness:
            return "Track febrile illness or major systemic illness because shedding shifts can show up weeks later."
        case .surgery:
            return "Track surgery and anesthesia because telogen effluvium-type shedding often lags behind the event."
        case .postpartum:
            return "Track postpartum status since shedding often follows a delayed timetable rather than a same-day change."
        case .weightLoss:
            return "Track significant weight loss or calorie restriction because hair changes can follow later."
        case .newMedication:
            return "Track medication starts and stops so later changes can be reviewed against them."
        case .tractionStyling:
            return "Track tight styling or extension changes because traction can worsen loss over time."
        case .sebDerm:
            return "Track flaring dandruff or seborrheic dermatitis activity because scalp inflammation can alter comfort and shedding."
        }
    }
}

enum OnboardingScalpState: String, CaseIterable, Identifiable {
    case calm = "Mostly calm"
    case drySensitive = "Dry or sensitive"
    case flaky = "Flaky or dandruff-prone"
    case oily = "Oily quickly"

    var id: String { rawValue }
}

enum OnboardingWashPreference: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case everyOtherDay = "Every 2-3 days"
    case twiceWeekly = "Twice weekly"
    case weekly = "Weekly"

    var id: String { rawValue }

    var frequencyDays: Int {
        switch self {
        case .daily: return 1
        case .everyOtherDay: return 2
        case .twiceWeekly: return 4
        case .weekly: return 7
        }
    }
}

enum OnboardingMedicationStatus: String, CaseIterable, Identifiable {
    case none = "No current hair medication"
    case minoxidil = "Using minoxidil"
    case oralPrescription = "Using oral prescription"
    case both = "Using both"

    var id: String { rawValue }
}

struct OnboardingSurveyResponse {
    var name: String = ""
    var texture: String = "Wavy 2C / 3A"
    var primaryGoal: String = "Reduce shedding"
    var hairLossFocus: HairLossFocus = .notSure
    var scalpState: OnboardingScalpState = .calm
    var washPreference: OnboardingWashPreference = .twiceWeekly
    var hasTightStyles = false
    var medicationStatus: OnboardingMedicationStatus = .none
    var wantsMonthlyPhotos = true
    var wantsNightProtection = false
    var familyHistorySummary: String = ""
    var patternDistribution: String = ""
    var patchAreaSummary: String = ""
    var hasEyebrowOrBeardInvolvement = false
    var hasScalpBurningTenderness = false
    var hasPustulesOrScale = false
    var recentIllnessTrigger = false
    var recentSurgeryTrigger = false
    var postpartumTrigger = false
    var recentWeightLossTrigger = false
    var recentMedicationChangeTrigger = false
    var includeBaselineTracking = true
    var includeWashRhythm = true
    var includeScalpSupport = true
    var includeTriggerLogging = true
    var includePhotoReminder = true
    var includeNightProtectionTask = false
    var includeMedicationTracker = true
    var ageRange: String = ""
    var biologicalSex: String = ""
    var hairLossDuration: String = ""
}

struct OnboardingPlanPreview {
    let taskTitles: [String]
    let triggerTitles: [String]
    let medicationTitles: [String]

    var totalItems: Int {
        taskTitles.count + triggerTitles.count + medicationTitles.count
    }
}

enum InitialRoutinePlanner {
    static let taskMarker = "Created from onboarding plan."
    static let medicationMarker = "Created from onboarding plan."
    static let triggerMarker = "Created from onboarding plan."

    static func apply(
        response: OnboardingSurveyResponse,
        to profile: HairProfile,
        modelContext: ModelContext
    ) {
        removePreviousAutogeneratedPlan(from: modelContext)

        profile.name = response.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "User" : response.name
        profile.texture = response.texture
        profile.primaryGoal = response.primaryGoal
        profile.washFrequencyDays = response.washPreference.frequencyDays
        profile.scalpSensitivity = scalpSensitivity(from: response.scalpState)
        profile.hairLossFocus = response.hairLossFocus.rawValue
        profile.patternDistribution = resolvedPatternDistribution(from: response)
        profile.familyHistorySummary = response.familyHistorySummary
        profile.ageRange = response.ageRange
        profile.biologicalSex = response.biologicalSex
        profile.hairLossDuration = response.hairLossDuration
        profile.hasCompletedOnboarding = true

        recommendedTasks(for: response).forEach(modelContext.insert)
        recommendedTriggers(for: response).forEach(modelContext.insert)
        recommendedMedication(for: response).forEach(modelContext.insert)
    }

    static func preview(for response: OnboardingSurveyResponse) -> OnboardingPlanPreview {
        OnboardingPlanPreview(
            taskTitles: recommendedTasks(for: response).map(\.title),
            triggerTitles: recommendedTriggers(for: response).map(\.title),
            medicationTitles: recommendedMedication(for: response).map(\.name)
        )
    }

    private static func removePreviousAutogeneratedPlan(from modelContext: ModelContext) {
        if let tasks = try? modelContext.fetch(FetchDescriptor<RoutineTask>()) {
            tasks
                .filter { $0.detail.contains(taskMarker) }
                .forEach(modelContext.delete)
        }

        if let medications = try? modelContext.fetch(FetchDescriptor<MedicationLog>()) {
            medications
                .filter { $0.notes.contains(medicationMarker) }
                .forEach(modelContext.delete)
        }

        if let triggers = try? modelContext.fetch(FetchDescriptor<HairTriggerEvent>()) {
            triggers
                .filter { $0.details.contains(triggerMarker) }
                .forEach(modelContext.delete)
        }
    }

    private static func recommendedTasks(for response: OnboardingSurveyResponse) -> [RoutineTask] {
        var tasks: [RoutineTask] = []

        if response.includeBaselineTracking {
            tasks.append(task(
                title: "Check-in + symptom log",
                detail: "Log scalp comfort, hydration, shedding, and stress on a repeated cadence so later charts and summaries mean something. \(taskMarker)",
                timeLabel: "20:00",
                weekday: 1,
                category: "Tracking",
                recurrenceType: .weekly,
                recurrenceWeekdays: [1, 4]
            ))
            tasks.append(task(
                title: "Weekly progress review",
                detail: "Review the week before changing products or routines. Look for repeated patterns instead of reacting to one difficult day. \(taskMarker)",
                timeLabel: "18:30",
                weekday: 7,
                category: "Review",
                recurrenceType: .weekly,
                recurrenceWeekdays: [7]
            ))
        }

        if response.includeWashRhythm {
            tasks.append(washTask(for: response.washPreference))
            tasks.append(task(
                title: "Post-wash scalp response note",
                detail: "After wash days, note itch, flaking, oil rebound, or dryness so wash spacing can be adjusted from evidence rather than guesswork. \(taskMarker)",
                timeLabel: "20:30",
                weekday: 6,
                category: "Wash",
                recurrenceType: response.washPreference == .daily ? .daily : .weekly,
                recurrenceWeekdays: washWeekdays(for: response.washPreference)
            ))
        }

        if response.includeScalpSupport {
            switch response.scalpState {
            case .drySensitive:
                tasks.append(task(
                    title: "Gentle scalp barrier check",
                    detail: "Use a gentle wash or low-irritation routine and note tightness, burning, or sensitivity before escalating products. \(taskMarker)",
                    timeLabel: "08:00",
                    weekday: 3,
                    category: "Scalp",
                    recurrenceType: .weekly,
                    recurrenceWeekdays: [3, 6]
                ))
                tasks.append(task(
                    title: "Hydration support after wash",
                    detail: "Track conditioner, leave-in, or moisture-support steps that reduce dryness without heavy buildup. \(taskMarker)",
                    timeLabel: "21:00",
                    weekday: 6,
                    category: "Hydration",
                    recurrenceType: .weekly,
                    recurrenceWeekdays: washWeekdays(for: response.washPreference)
                ))
            case .flaky:
                tasks.append(task(
                    title: "Anti-flake treatment wash",
                    detail: "If using a dandruff or seb derm-directed product, track flaking, itch, and scalp comfort after each treatment wash. \(taskMarker)",
                    timeLabel: "19:00",
                    weekday: 3,
                    category: "Scalp",
                    recurrenceType: .weekly,
                    recurrenceWeekdays: [3, 6]
                ))
                tasks.append(task(
                    title: "Flare note",
                    detail: "Log when flaking, redness, or itch flare so scalp-care changes can be reviewed later against real symptoms. \(taskMarker)",
                    timeLabel: "20:30",
                    weekday: 1,
                    category: "Scalp",
                    recurrenceType: .weekly,
                    recurrenceWeekdays: [1, 5]
                ))
            case .oily:
                tasks.append(task(
                    title: "Oil buildup check",
                    detail: "Track how quickly oil returns and whether shorter or longer wash spacing changes itch, comfort, or visible buildup. \(taskMarker)",
                    timeLabel: "18:00",
                    weekday: 4,
                    category: "Scalp",
                    recurrenceType: .weekly,
                    recurrenceWeekdays: [2, 4, 6]
                ))
            case .calm:
                break
            }
        }

        if response.hasTightStyles {
            tasks.append(task(
                title: "Low-tension style review",
                detail: "Check tension at temples, hairline, and crown. Switch out tight styles early if soreness, breakage, or edge thinning appears. \(taskMarker)",
                timeLabel: "09:00",
                weekday: 2,
                category: "Protection",
                recurrenceType: .weekly,
                recurrenceWeekdays: [2, 5]
            ))
            tasks.append(task(
                title: "Hairline breakage check",
                detail: "Use the same mirror view or photos to see whether the hairline is recovering or being stressed by styling choices. \(taskMarker)",
                timeLabel: "18:00",
                weekday: 7,
                category: "Protection",
                recurrenceType: .weekly,
                recurrenceWeekdays: [7]
            ))
        }

        if response.includeNightProtectionTask && response.wantsNightProtection {
            tasks.append(task(
                title: "Night protection",
                detail: "Use a satin or silk wrap or a low-friction sleep setup and track whether breakage and dryness improve. \(taskMarker)",
                timeLabel: "22:00",
                weekday: 7,
                category: "Protection",
                recurrenceType: .daily
            ))
        }

        if response.includePhotoReminder && response.wantsMonthlyPhotos {
            tasks.append(task(
                title: "Standardized photo session",
                detail: "Capture the same angle, lighting, parting, and wet/dry state on a fixed interval for meaningful comparison. \(taskMarker)",
                timeLabel: "10:00",
                weekday: 1,
                category: "Photos",
                recurrenceType: .monthly
            ))
            tasks.append(task(
                title: "Photo comparison review",
                detail: "Compare only same-angle sessions so changes are interpreted from matched images instead of memory. \(taskMarker)",
                timeLabel: "18:00",
                weekday: 1,
                category: "Photos",
                recurrenceType: .monthly
            ))
        }

        switch response.hairLossFocus {
        case .alopeciaAreata:
            tasks.append(task(
                title: "Patch map review",
                detail: "Track the same patch zones with fixed-angle notes or photos instead of relying on memory. \(taskMarker)",
                timeLabel: "18:30",
                weekday: 7,
                category: "Photos",
                recurrenceType: .weekly,
                recurrenceWeekdays: [7]
            ))
            if response.hasEyebrowOrBeardInvolvement {
                tasks.append(task(
                    title: "Eyebrow / beard involvement note",
                    detail: "Log eyebrow or beard changes separately so regrowth and extension patterns are not lost inside scalp tracking. \(taskMarker)",
                    timeLabel: "18:45",
                    weekday: 7,
                    category: "Tracking",
                    recurrenceType: .weekly,
                    recurrenceWeekdays: [7]
                ))
            }
        case .inflammatoryScarring:
            tasks.append(task(
                title: "Inflammation symptom review",
                detail: "Log burning, tenderness, pustules, scale, or pain clearly. Warning-pattern symptoms deserve clinician review rather than trial-and-error care. \(taskMarker)",
                timeLabel: "18:00",
                weekday: 2,
                category: "Scalp",
                recurrenceType: .weekly,
                recurrenceWeekdays: [2, 5]
            ))
            tasks.append(task(
                title: "Urgent flare photo note",
                detail: "If visible redness, scale, or soreness increases, document it quickly with the same angle and date context. \(taskMarker)",
                timeLabel: "18:15",
                weekday: 2,
                category: "Photos",
                recurrenceType: .weekly,
                recurrenceWeekdays: [2]
            ))
        case .telogenEffluvium:
            tasks.append(task(
                title: "Trigger timeline review",
                detail: "Review illness, surgery, postpartum, weight change, and new medication history because shedding often appears weeks later. \(taskMarker)",
                timeLabel: "20:30",
                weekday: 1,
                category: "Tracking",
                recurrenceType: .weekly,
                recurrenceWeekdays: [1]
            ))
            tasks.append(task(
                title: "Weekly shedding burden check",
                detail: "Track whether shedding is easing, stable, or worsening over the week rather than reacting to one wash or one brush session. \(taskMarker)",
                timeLabel: "19:00",
                weekday: 7,
                category: "Tracking",
                recurrenceType: .weekly,
                recurrenceWeekdays: [7]
            ))
        case .androgeneticAlopecia, .notSure:
            tasks.append(task(
                title: "Hairline / crown comparison review",
                detail: "Use the same zones and same-angle photos to watch temples, crown, or part line over time rather than checking randomly. \(taskMarker)",
                timeLabel: "18:00",
                weekday: 7,
                category: "Photos",
                recurrenceType: .monthly
            ))
            tasks.append(task(
                title: "Routine consistency checkpoint",
                detail: "Pattern-focused tracking is most useful when routine and treatment adherence stay steady long enough to compare against photos and symptoms. \(taskMarker)",
                timeLabel: "20:00",
                weekday: 3,
                category: "Tracking",
                recurrenceType: .weekly,
                recurrenceWeekdays: [3]
            ))
        }

        return tasks
    }

    private static func recommendedTriggers(for response: OnboardingSurveyResponse) -> [HairTriggerEvent] {
        guard response.includeTriggerLogging else { return [] }

        var triggers: [HairTriggerEvent] = []

        if response.hasTightStyles {
            triggers.append(
                HairTriggerEvent(
                    category: HairTriggerCategory.tractionStyling.rawValue,
                    title: "Traction-prone styling history",
                    details: "Added from onboarding so temple or hairline changes can be interpreted in context. \(triggerMarker)",
                    startedAt: .now,
                    severity: "Moderate"
                )
            )
        }

        if response.scalpState == .flaky {
            triggers.append(
                HairTriggerEvent(
                    category: HairTriggerCategory.sebDerm.rawValue,
                    title: "Flaking / seb derm context",
                    details: "Added from onboarding because dandruff-like activity may affect scalp comfort tracking. \(triggerMarker)",
                    startedAt: .now,
                    severity: "Moderate",
                    affectsSheddingRisk: false
                )
            )
        }

        if response.recentIllnessTrigger {
            triggers.append(trigger(for: .recentIllness))
        }
        if response.recentSurgeryTrigger {
            triggers.append(trigger(for: .surgery))
        }
        if response.postpartumTrigger {
            triggers.append(trigger(for: .postpartum))
        }
        if response.recentWeightLossTrigger {
            triggers.append(trigger(for: .weightLoss))
        }
        if response.recentMedicationChangeTrigger {
            triggers.append(trigger(for: .newMedication))
        }

        if response.hairLossFocus == .inflammatoryScarring,
           response.hasScalpBurningTenderness || response.hasPustulesOrScale {
            triggers.append(
                HairTriggerEvent(
                    category: "Inflammatory / scarring alopecia",
                    title: "Inflammatory scalp warning pattern",
                    details: "Added from onboarding because burning, tenderness, pustules, or scale were reported. \(triggerMarker)",
                    startedAt: .now,
                    severity: "High",
                    affectsSheddingRisk: false
                )
            )
        }

        return triggers
    }

    private static func recommendedMedication(for response: OnboardingSurveyResponse) -> [MedicationLog] {
        guard response.includeMedicationTracker else { return [] }

        switch response.medicationStatus {
        case .none:
            return []
        case .minoxidil:
            return [MedicationLog(
                name: "Minoxidil",
                indication: response.hairLossFocus.rawValue,
                form: "Topical",
                dosage: "1 mL / label amount",
                frequencyPerDay: 2,
                schedule: "Twice daily",
                scheduledTimes: "08:00,20:00",
                prescribedByClinician: false,
                notes: "Created from onboarding plan. Adjust to your actual product instructions."
            )]
        case .oralPrescription:
            return [MedicationLog(
                name: "Hair prescription",
                indication: response.hairLossFocus.rawValue,
                form: "Oral",
                dosage: "Per clinician instructions",
                frequencyPerDay: 1,
                schedule: "Once daily",
                scheduledTimes: "08:00",
                prescribedByClinician: true,
                notes: "Created from onboarding plan. Replace with your actual medication name."
            )]
        case .both:
            return [
                MedicationLog(
                    name: "Minoxidil",
                    indication: response.hairLossFocus.rawValue,
                    form: "Topical",
                    dosage: "1 mL / label amount",
                    frequencyPerDay: 2,
                    schedule: "Twice daily",
                    scheduledTimes: "08:00,20:00",
                    prescribedByClinician: false,
                    notes: "Created from onboarding plan. Adjust to your actual product instructions."
                ),
                MedicationLog(
                    name: "Hair prescription",
                    indication: response.hairLossFocus.rawValue,
                    form: "Oral",
                    dosage: "Per clinician instructions",
                    frequencyPerDay: 1,
                    schedule: "Once daily",
                    scheduledTimes: "08:00",
                    prescribedByClinician: true,
                    notes: "Created from onboarding plan. Replace with your actual medication name."
                )
            ]
        }
    }

    private static func scalpSensitivity(from state: OnboardingScalpState) -> String {
        switch state {
        case .calm:
            return "Balanced"
        case .drySensitive:
            return "Sensitive"
        case .flaky:
            return "Flaky"
        case .oily:
            return "Oily"
        }
    }

    private static func resolvedPatternDistribution(from response: OnboardingSurveyResponse) -> String {
        let trimmedPattern = response.patternDistribution.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPattern.isEmpty {
            return trimmedPattern
        }

        if response.hairLossFocus == .alopeciaAreata {
            let trimmedPatch = response.patchAreaSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPatch.isEmpty {
                return trimmedPatch
            }
        }

        return ""
    }

    private static func trigger(for category: HairTriggerCategory) -> HairTriggerEvent {
        HairTriggerEvent(
            category: category.rawValue,
            title: category.templateTitle,
            details: "\(category.summary) \(triggerMarker)",
            startedAt: .now,
            severity: "Moderate"
        )
    }

    private static func task(
        title: String,
        detail: String,
        timeLabel: String,
        weekday: Int,
        category: String,
        recurrenceType: RoutineRecurrenceType,
        recurrenceWeekdays: [Int] = [],
        recurrenceInterval: Int = 1,
        itemType: RoutineItemType = .habit
    ) -> RoutineTask {
        RoutineTask(
            title: title,
            itemType: itemType.rawValue,
            detail: detail,
            timeLabel: timeLabel,
            weekday: weekday,
            category: category,
            recurrenceType: recurrenceType.rawValue,
            recurrenceInterval: recurrenceInterval,
            recurrenceWeekdays: recurrenceWeekdays.map(String.init).joined(separator: ",")
        )
    }

    private static func washTask(for preference: OnboardingWashPreference) -> RoutineTask {
        switch preference {
        case .daily:
            return task(
                title: "Wash day routine",
                detail: "Follow your current wash cadence and note whether the scalp feels calmer, drier, itchier, or more reactive afterward. \(taskMarker)",
                timeLabel: "19:00",
                weekday: 2,
                category: "Wash",
                recurrenceType: .daily
            )
        case .everyOtherDay:
            return task(
                title: "Wash day routine",
                detail: "Keep a steady every-2-3-day wash rhythm so scalp and shedding changes can be interpreted against a consistent routine. \(taskMarker)",
                timeLabel: "19:00",
                weekday: 2,
                category: "Wash",
                recurrenceType: .everyNDays,
                recurrenceInterval: 2
            )
        case .twiceWeekly:
            return task(
                title: "Wash day routine",
                detail: "Keep a twice-weekly wash rhythm and notice whether spacing changes scalp comfort or visible buildup. \(taskMarker)",
                timeLabel: "19:00",
                weekday: 3,
                category: "Wash",
                recurrenceType: .weekly,
                recurrenceWeekdays: washWeekdays(for: preference)
            )
        case .weekly:
            return task(
                title: "Wash day routine",
                detail: "Keep a weekly wash rhythm and review whether longer spacing affects itch, flakes, or oil rebound. \(taskMarker)",
                timeLabel: "19:00",
                weekday: 6,
                category: "Wash",
                recurrenceType: .weekly,
                recurrenceWeekdays: washWeekdays(for: preference)
            )
        }
    }

    private static func washWeekdays(for preference: OnboardingWashPreference) -> [Int] {
        switch preference {
        case .daily:
            return Array(1...7)
        case .everyOtherDay:
            return [2, 4, 6]
        case .twiceWeekly:
            return [3, 6]
        case .weekly:
            return [6]
        }
    }
}

struct IntelligenceReport {
    let headline: String
    let confidenceLabel: String
    let observations: [String]
    let suggestions: [String]
    let dataGaps: [String]
    let reviewFlags: [String]

    static let empty = IntelligenceReport(
        headline: "",
        confidenceLabel: "",
        observations: [],
        suggestions: [],
        dataGaps: [],
        reviewFlags: []
    )

    var hasMeaningfulSignals: Bool {
        !observations.isEmpty || !suggestions.isEmpty || !reviewFlags.isEmpty
    }

    var compactPromptSummary: String {
        """
        Headline: \(headline)
        Confidence: \(confidenceLabel)
        Observations: \(observations.joined(separator: " | "))
        Suggestions: \(suggestions.joined(separator: " | "))
        Data gaps: \(dataGaps.joined(separator: " | "))
        Review flags: \(reviewFlags.joined(separator: " | "))
        """
    }
}

enum MedicationScheduleFormatter {
    static func defaultTimeLabels(for frequencyPerDay: Int) -> [String] {
        switch frequencyPerDay {
        case ...1:
            return ["09:00"]
        case 2:
            return ["09:00", "21:00"]
        case 3:
            return ["08:00", "14:00", "20:00"]
        default:
            return ["08:00", "12:00", "16:00", "21:00"]
        }
    }

    static func normalizedLabels(from rawValue: String, fallbackFrequency: Int) -> [String] {
        let explicit = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if explicit.isEmpty {
            return defaultTimeLabels(for: fallbackFrequency)
        }

        let deduplicated = Array(NSOrderedSet(array: explicit)) as? [String] ?? explicit
        return deduplicated.sorted()
    }

    static func encodedString(from labels: [String]) -> String {
        labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: ",")
    }

    static func displaySummary(for labels: [String]) -> String {
        guard !labels.isEmpty else { return "No schedule set" }
        return labels.joined(separator: " • ")
    }
}
