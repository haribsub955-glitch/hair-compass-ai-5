import Foundation
import SwiftData

enum IntelligenceComposer {
    static func build(
        entries: [CheckInEntry],
        impactPoints: [RoutineImpactPoint],
        labResults: [LabResultEntry],
        healthMetrics: [HealthDailyMetric],
        medications: [MedicationLog],
        procedureEvents: [ProcedureEvent]
    ) -> IntelligenceReport {
        guard !entries.isEmpty else {
            return IntelligenceReport(
                headline: "Intelligence needs more data",
                confidenceLabel: "Low",
                observations: [],
                suggestions: [
                    "Start with consistent check-ins, routine logs, and same-angle photos before asking AI to summarize patterns."
                ],
                dataGaps: [
                    "No check-ins are logged yet.",
                    "Pattern analysis becomes more useful after at least a few weeks of entries."
                ],
                reviewFlags: []
            )
        }

        let calendar = Calendar.current
        let recentEntries = entries
            .sorted { $0.date > $1.date }
            .filter {
                let cutoff = calendar.date(byAdding: .day, value: -45, to: .now) ?? .now
                return $0.date >= cutoff
            }
        let activeEntries = recentEntries.isEmpty ? entries : recentEntries
        let averageShedding = HairInsightCalculator.averageScore(for: activeEntries, keyPath: \.sheddingLevel)
        let averageStress = HairInsightCalculator.averageScore(for: activeEntries, keyPath: \.stressLevel)
        let averageScalp = HairInsightCalculator.averageScore(for: activeEntries, keyPath: \.scalpScore)

        var observations: [String] = []
        var suggestions: [String] = []
        var dataGaps: [String] = []

        if activeEntries.count >= 4 {
            if averageShedding >= 45 {
                observations.append("Recent shedding scores are elevated across your latest check-ins.")
            } else if averageShedding <= 25 {
                observations.append("Recent shedding scores are trending in a lower range.")
            }

            if averageStress >= 55 {
                observations.append("Stress has been showing up at the higher end of your recent logs.")
            }

            if averageScalp >= 75 {
                observations.append("Scalp comfort has been relatively strong in your recent check-ins.")
            } else if averageScalp > 0, averageScalp <= 55 {
                observations.append("Scalp comfort has been staying on the lower side recently.")
            }
        } else {
            dataGaps.append("Fewer than four recent check-ins are available, so short-term patterns are still thin.")
        }

        if let sleepSignal = relationshipObservation(
            points: impactPoints,
            primary: { $0.hasCheckInData ? $0.sheddingScore : nil },
            comparison: { ($0.hasCheckInData && $0.hasHealthData) ? $0.sleepHours : nil },
            whenHigherComparisonSuggestsLowerPrimary: true,
            minimumComparisonValue: 1,
            title: "sleep"
        ) {
            observations.append(sleepSignal)
        } else if healthMetrics.isEmpty {
            dataGaps.append("No Apple Health sleep or exercise data is available yet.")
        }

        if let minoxidilSignal = relationshipObservation(
            points: impactPoints,
            primary: { $0.hasCheckInData ? $0.sheddingScore : nil },
            comparison: { $0.hasCheckInData ? Double($0.minoxidilEntries) : nil },
            whenHigherComparisonSuggestsLowerPrimary: true,
            minimumComparisonValue: 1,
            title: "minoxidil logging"
        ) {
            observations.append(minoxidilSignal)
        }

        if let smokingSignal = relationshipObservation(
            points: impactPoints,
            primary: { $0.hasCheckInData ? $0.sheddingScore : nil },
            comparison: { $0.hasCheckInData ? $0.smokingCount : nil },
            whenHigherComparisonSuggestsLowerPrimary: false,
            minimumComparisonValue: 1,
            title: "smoking"
        ) {
            observations.append(smokingSignal)
        }

        if let exerciseSignal = relationshipObservation(
            points: impactPoints,
            primary: { $0.hasCheckInData ? $0.sheddingScore : nil },
            comparison: { ($0.hasCheckInData && $0.hasHealthData) ? $0.exerciseMinutes : nil },
            whenHigherComparisonSuggestsLowerPrimary: true,
            minimumComparisonValue: 10,
            title: "exercise"
        ) {
            observations.append(exerciseSignal)
        }

        if let proteinSignal = relationshipObservation(
            points: impactPoints,
            primary: { $0.hasCheckInData ? $0.sheddingScore : nil },
            comparison: { ($0.hasCheckInData && $0.hasHealthData && $0.proteinGrams > 0) ? $0.proteinGrams : nil },
            whenHigherComparisonSuggestsLowerPrimary: true,
            minimumComparisonValue: 20,
            title: "protein intake"
        ) {
            observations.append(proteinSignal)
        }

        if let waterSignal = relationshipObservation(
            points: impactPoints,
            primary: { $0.hasCheckInData ? $0.scalpScore : nil },
            comparison: { ($0.hasCheckInData && $0.hasHealthData && $0.waterLiters > 0) ? $0.waterLiters : nil },
            whenHigherComparisonSuggestsLowerPrimary: false,
            minimumComparisonValue: 0.5,
            title: "water intake"
        ) {
            observations.append(waterSignal)
        }

        if medications.isEmpty {
            dataGaps.append("No medication routine is logged, which limits treatment-adherence analysis.")
        } else if medications.contains(where: { $0.name.localizedCaseInsensitiveContains("minoxidil") }) {
            suggestions.append("If minoxidil is part of your plan, keep the log consistent so the AI summary can compare adherence windows over time.")
        }

        if procedureEvents.isEmpty == false {
            suggestions.append("Procedure events are being tracked. Compare them over longer windows like 3 to 6 months instead of same-day changes.")
        }

        if labResults.isEmpty {
            dataGaps.append("No ferritin, thyroid, vitamin D, or other lab results are logged.")
            suggestions.append("If shedding stays persistent, adding clinician-ordered ferritin, thyroid, or vitamin D results can make the analysis more grounded.")
        }

        if healthMetrics.isEmpty == false {
            suggestions.append("Keep sleep and exercise syncing through Apple Health so the Intelligence layer can compare lifestyle consistency against shedding.")
        }

        let reviewFlags = HairClinicalGuidance.alerts(for: entries).map(\.title)
        if !reviewFlags.isEmpty {
            suggestions.append("AI pattern summaries should stay secondary to clinician review when pain, patchy loss, or other red flags are present.")
        }

        let confidenceLabel: String
        switch (activeEntries.count, impactPoints.count) {
        case (8..., 8...):
            confidenceLabel = "Medium"
        case (4..., 4...):
            confidenceLabel = "Low to medium"
        default:
            confidenceLabel = "Low"
        }

        let headline: String
        if !reviewFlags.isEmpty {
            headline = "Intelligence found patterns, but safety review matters first"
        } else if observations.isEmpty {
            headline = "Intelligence has early signals but needs more history"
        } else {
            headline = observations.first ?? "Intelligence generated a pattern summary"
        }

        return IntelligenceReport(
            headline: headline,
            confidenceLabel: confidenceLabel,
            observations: Array(observations.prefix(3)),
            suggestions: Array(suggestions.prefix(3)),
            dataGaps: Array(dataGaps.prefix(3)),
            reviewFlags: Array(reviewFlags.prefix(3))
        )
    }

    private static func relationshipObservation(
        points: [RoutineImpactPoint],
        primary: (RoutineImpactPoint) -> Double?,
        comparison: (RoutineImpactPoint) -> Double?,
        whenHigherComparisonSuggestsLowerPrimary: Bool,
        minimumComparisonValue: Double,
        title: String
    ) -> String? {
        let usablePoints = points.compactMap { point -> (primary: Double, comparison: Double)? in
            guard let primaryValue = primary(point), let comparisonValue = comparison(point) else { return nil }
            return (primaryValue, comparisonValue)
        }

        let active = usablePoints.filter { $0.comparison >= minimumComparisonValue }
        let inactive = usablePoints.filter { $0.comparison < minimumComparisonValue }

        guard active.count >= 2, inactive.count >= 2 else { return nil }

        let activePrimaryAverage = active.map(\.primary).average
        let inactivePrimaryAverage = inactive.map(\.primary).average
        let delta = activePrimaryAverage - inactivePrimaryAverage

        guard abs(delta) >= 5 else { return nil }

        if whenHigherComparisonSuggestsLowerPrimary {
            if delta < 0 {
                return "Higher \(title) days have lined up with lower shedding in your own logs."
            } else {
                return "Higher \(title) days have not yet lined up with lower shedding in your current logs."
            }
        } else {
            if delta > 0 {
                return "Higher \(title) days have lined up with higher shedding in your own logs."
            } else {
                return "Higher \(title) days have not lined up with worse shedding in the current window."
            }
        }
    }
}

/// Sendable snapshot of the SwiftData models that `RoutineImpactCalculator` needs.
/// It is built on the main actor (where the models live) and then handed to
/// `buildPoints`, which can therefore run off the main thread without ever
/// touching SwiftData. Property names mirror the models so the calculator body
/// stays unchanged aside from reading through these value types.
struct RoutineImpactInput: Sendable {
    struct CheckIn: Sendable {
        let date: Date
        let scalpScore: Int
        let hydrationScore: Int
        let sheddingLevel: Int
        let stressLevel: Int
    }

    struct Completion: Sendable {
        let completedAt: Date
    }

    struct Medication: Sendable {
        let id: UUID
        let name: String
        let startedAt: Date
        let isActive: Bool
        let scheduledTimes: String
        let frequencyPerDay: Int
    }

    struct Dose: Sendable {
        let medicationID: UUID?
        let medicationName: String
        let loggedAt: Date
        let wasTaken: Bool
    }

    struct Procedure: Sendable {
        let performedAt: Date
        let title: String
        let procedureDescription: String
    }

    struct Lifestyle: Sendable {
        let category: String
        let loggedAt: Date
        let amount: Double
    }

    struct Trigger: Sendable {
        let startedAt: Date
        let endedAt: Date?
        let category: String
    }

    var entries: [CheckIn] = []
    var completions: [Completion] = []
    var medications: [Medication] = []
    var doses: [Dose] = []
    var procedures: [Procedure] = []
    var lifestyle: [Lifestyle] = []
    var triggers: [Trigger] = []
    var healthMetricsByDay: [Date: HealthDailyMetric] = [:]

    /// Maps the live SwiftData models into Sendable snapshots. Call from the context
    /// that owns the models (e.g. the main actor in the app); only the resulting
    /// Sendable value is handed to `buildPoints`, which may then run off-thread.
    init(
        entries: [CheckInEntry],
        routineCompletions: [RoutineCompletionEntry],
        medications: [MedicationLog],
        medicationEntries: [MedicationDoseEntry],
        procedureEvents: [ProcedureEvent],
        healthMetricsByDay: [Date: HealthDailyMetric] = [:],
        lifestyleEntries: [LifestyleEntry] = [],
        triggerEvents: [HairTriggerEvent] = []
    ) {
        self.entries = entries.map {
            CheckIn(
                date: $0.date,
                scalpScore: $0.scalpScore,
                hydrationScore: $0.hydrationScore,
                sheddingLevel: $0.sheddingLevel,
                stressLevel: $0.stressLevel
            )
        }
        self.completions = routineCompletions.map { Completion(completedAt: $0.completedAt) }
        self.medications = medications.map {
            Medication(
                id: $0.id,
                name: $0.name,
                startedAt: $0.startedAt,
                isActive: $0.isActive,
                scheduledTimes: $0.scheduledTimes,
                frequencyPerDay: $0.frequencyPerDay
            )
        }
        self.doses = medicationEntries.map {
            Dose(
                medicationID: $0.medication?.id,
                medicationName: $0.medication?.name ?? $0.medicationName,
                loggedAt: $0.loggedAt,
                wasTaken: $0.wasTaken
            )
        }
        self.procedures = procedureEvents.map {
            Procedure(performedAt: $0.performedAt, title: $0.title, procedureDescription: $0.procedureDescription)
        }
        self.lifestyle = lifestyleEntries.map {
            Lifestyle(category: $0.category, loggedAt: $0.loggedAt, amount: $0.amount)
        }
        self.triggers = triggerEvents.map {
            Trigger(startedAt: $0.startedAt, endedAt: $0.endedAt, category: $0.category)
        }
        self.healthMetricsByDay = healthMetricsByDay
    }
}

enum RoutineImpactCalculator {
    static func buildPoints(
        _ input: RoutineImpactInput,
        calendar: Calendar = .current
    ) -> [RoutineImpactPoint] {
        let entryByDay = Dictionary(
            grouping: input.entries,
            by: { calendar.startOfDay(for: $0.date) }
        )

        let medicationCoverageDays = input.medications.flatMap { medication -> [Date] in
            let start = calendar.startOfDay(for: medication.startedAt)
            let end: Date
            if medication.isActive {
                end = calendar.startOfDay(for: .now)
            } else if let latestLog = input.doses
                .filter({ ($0.medicationID == medication.id) || ($0.medicationID == nil && $0.medicationName == medication.name) })
                .map(\.loggedAt)
                .max()
            {
                end = calendar.startOfDay(for: latestLog)
            } else {
                end = start
            }

            guard start <= end else { return [start] }
            var days: [Date] = []
            var cursor = start
            while cursor <= end {
                days.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return days
        }

        let allDays = Set(entryByDay.keys)
            .union(input.completions.map { calendar.startOfDay(for: $0.completedAt) })
            .union(medicationCoverageDays)
            .union(input.doses.map { calendar.startOfDay(for: $0.loggedAt) })
            .union(input.procedures.map { calendar.startOfDay(for: $0.performedAt) })
            .union(input.lifestyle.map { calendar.startOfDay(for: $0.loggedAt) })
            .union(input.healthMetricsByDay.keys)
            .union(input.triggers.flatMap { event -> [Date] in
                let start = calendar.startOfDay(for: event.startedAt)
                let end = calendar.startOfDay(for: event.endedAt ?? event.startedAt)
                var days: [Date] = [start]
                var cursor = start
                while cursor < end {
                    guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                    days.append(next)
                    cursor = next
                }
                return days
            })

        return allDays
            .sorted()
            .map { day in
                let dayEntries = entryByDay[day] ?? []
                let averageScalp = dayEntries.isEmpty ? 0 : Double(dayEntries.map(\.scalpScore).reduce(0, +)) / Double(dayEntries.count)
                let averageHydration = dayEntries.isEmpty ? 0 : Double(dayEntries.map(\.hydrationScore).reduce(0, +)) / Double(dayEntries.count)
                let averageShedding = dayEntries.isEmpty ? 0 : Double(dayEntries.map(\.sheddingLevel).reduce(0, +)) / Double(dayEntries.count)
                let averageStress = dayEntries.isEmpty ? 0 : Double(dayEntries.map(\.stressLevel).reduce(0, +)) / Double(dayEntries.count)

                let routineCount = input.completions.filter {
                    calendar.isDate($0.completedAt, inSameDayAs: day)
                }.count
                let medicationCount = input.doses.filter {
                    $0.wasTaken && calendar.isDate($0.loggedAt, inSameDayAs: day)
                }.count
                let minoxidilCount = input.doses.filter {
                    $0.wasTaken &&
                    calendar.isDate($0.loggedAt, inSameDayAs: day) &&
                    isMinoxidilDose($0)
                }.count
                let procedureCount = input.procedures.filter {
                    calendar.isDate($0.performedAt, inSameDayAs: day)
                }.count
                let dutasterideProcedureCount = input.procedures.filter {
                    calendar.isDate($0.performedAt, inSameDayAs: day) &&
                    ($0.title.localizedCaseInsensitiveContains("dutasteride") ||
                     $0.procedureDescription.localizedCaseInsensitiveContains("dutasteride"))
                }.count
                let smokingCount = input.lifestyle
                    .filter {
                        $0.category == LifestyleCategory.smoking.rawValue &&
                        calendar.isDate($0.loggedAt, inSameDayAs: day)
                    }
                    .reduce(0.0) { $0 + $1.amount }
                let supplementCount = input.lifestyle.filter {
                    $0.category == LifestyleCategory.supplement.rawValue &&
                    calendar.isDate($0.loggedAt, inSameDayAs: day)
                }.count
                let dayTriggerEvents = input.triggers.filter {
                    let endDate = $0.endedAt ?? $0.startedAt
                    return calendar.startOfDay(for: $0.startedAt) <= day && calendar.startOfDay(for: endDate) >= day
                }
                let tractionCount = dayTriggerEvents.filter { $0.category == HairTriggerCategory.tractionStyling.rawValue }.count
                let sebDermCount = dayTriggerEvents.filter { $0.category == HairTriggerCategory.sebDerm.rawValue }.count
                let healthMetric = input.healthMetricsByDay[day]
                let expectedMedicationEntries = input.medications.reduce(0) { partial, medication in
                    guard medicationShouldCount(medication, on: day, calendar: calendar) else { return partial }
                    return partial + MedicationScheduleFormatter.normalizedLabels(
                        from: medication.scheduledTimes,
                        fallbackFrequency: medication.frequencyPerDay
                    ).count
                }
                let expectedMinoxidilEntries = input.medications.reduce(0) { partial, medication in
                    guard
                        medicationShouldCount(medication, on: day, calendar: calendar),
                        medication.name.localizedCaseInsensitiveContains("minoxidil")
                    else {
                        return partial
                    }
                    return partial + MedicationScheduleFormatter.normalizedLabels(
                        from: medication.scheduledTimes,
                        fallbackFrequency: medication.frequencyPerDay
                    ).count
                }

                let recentTriggerLoad = lagAwareLoad(
                    for: day,
                    events: input.triggers.map { ($0.startedAt, 1.0) },
                    calendar: calendar
                )
                let recentProcedureLoad = lagAwareLoad(
                    for: day,
                    events: input.procedures.map { ($0.performedAt, 1.0) },
                    calendar: calendar
                )

                return RoutineImpactPoint(
                    date: day,
                    sheddingScore: averageShedding,
                    stressScore: averageStress,
                    scalpScore: averageScalp,
                    hydrationScore: averageHydration,
                    routineActions: routineCount,
                    medicationEntries: medicationCount,
                    minoxidilEntries: minoxidilCount,
                    expectedMedicationEntries: expectedMedicationEntries,
                    expectedMinoxidilEntries: expectedMinoxidilEntries,
                    procedureEvents: procedureCount,
                    dutasterideProcedureEvents: dutasterideProcedureCount,
                    sleepHours: healthMetric?.sleepHours ?? 0,
                    exerciseMinutes: healthMetric?.exerciseMinutes ?? 0,
                    proteinGrams: healthMetric?.proteinGrams ?? 0,
                    waterLiters: healthMetric?.waterLiters ?? 0,
                    smokingCount: smokingCount,
                    supplementEntries: supplementCount,
                    triggerEvents: dayTriggerEvents.count,
                    tractionEvents: tractionCount,
                    sebDermEvents: sebDermCount,
                    recentTriggerLoad: recentTriggerLoad,
                    recentProcedureLoad: recentProcedureLoad,
                    hasCheckInData: !dayEntries.isEmpty,
                    hasHealthData: healthMetric != nil
                )
            }
    }

    private static func lagAwareLoad(
        for day: Date,
        events: [(Date, Double)],
        calendar: Calendar
    ) -> Double {
        events.reduce(0) { partial, event in
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.0), to: day).day ?? 0
            guard days >= 0 else { return partial }

            switch days {
            case 14...42:
                return partial + (event.1 * 1.0)
            case 43...84:
                return partial + (event.1 * 0.55)
            default:
                return partial
            }
        }
    }

    private static func isMinoxidilDose(_ dose: RoutineImpactInput.Dose) -> Bool {
        dose.medicationName.localizedCaseInsensitiveContains("minoxidil")
    }

    private static func medicationShouldCount(_ medication: RoutineImpactInput.Medication, on day: Date, calendar: Calendar) -> Bool {
        let startDay = calendar.startOfDay(for: medication.startedAt)
        guard day >= startDay else { return false }
        return medication.isActive
    }
}

enum PhotoAngle: String, CaseIterable, Identifiable {
    case front = "Front"
    case leftTemple = "Left Temple"
    case rightTemple = "Right Temple"
    case top = "Top"
    case crown = "Crown"
    case back = "Back"

    var id: String { rawValue }

    var capturePrompt: String {
        switch self {
        case .front:
            return "Keep your face centered and hairline visible."
        case .leftTemple:
            return "Turn slightly right so the left temple is clear."
        case .rightTemple:
            return "Turn slightly left so the right temple is clear."
        case .top:
            return "Tilt the camera above the scalp center."
        case .crown:
            return "Show the crown with even overhead lighting."
        case .back:
            return "Capture the back of the scalp and lower crown."
        }
    }
}

struct GuidanceAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let severity: GuidanceSeverity
}

enum GuidanceSeverity: String {
    case routine
    case soon
    case prompt
}

enum HairClinicalGuidance {
    static func alerts(for entries: [CheckInEntry]) -> [GuidanceAlert] {
        guard !entries.isEmpty else { return [] }

        var alerts: [GuidanceAlert] = []
        let recentEntries = Array(entries.prefix(3))

        if recentEntries.contains(where: \.hasPatchyHairLoss) {
            alerts.append(
                GuidanceAlert(
                    id: "patchy-loss",
                    title: "Patchy hair loss needs medical assessment",
                    message: "Patchy loss can point to conditions that need diagnosis rather than cosmetic care alone.",
                    severity: .prompt
                )
            )
        }

        if recentEntries.contains(where: \.hasScalpPain) {
            alerts.append(
                GuidanceAlert(
                    id: "pain-burning",
                    title: "Scalp pain or burning is a red flag",
                    message: "Pain, soreness, or burning can occur with inflammatory scalp conditions and should not be treated as routine dryness.",
                    severity: .prompt
                )
            )
        }

        let persistentFlaking = recentEntries.filter { $0.hasFlaking || $0.hasItch }.count >= 2
        if persistentFlaking {
            alerts.append(
                GuidanceAlert(
                    id: "persistent-flaking",
                    title: "Persistent flaking or itch should be reviewed",
                    message: "If dandruff-style symptoms keep returning or OTC care does not help, a dermatologist can check for seborrheic dermatitis, psoriasis, or other causes.",
                    severity: .soon
                )
            )
        }

        if recentEntries.contains(where: \.hasTightStyleTension) {
            alerts.append(
                GuidanceAlert(
                    id: "traction-risk",
                    title: "Tension styling can drive traction alopecia",
                    message: "Pain or pulling from tight styles is not a harmless cosmetic issue. Repeated tension can contribute to permanent hair loss.",
                    severity: .routine
                )
            )
        }

        return alerts
    }
}

struct ApprovedMedicationInfo: Identifiable {
    let id: String
    let name: String
    let approvalScope: String
    let route: String
    let keyUse: String
    let defaultDosage: String
    let defaultFrequencyPerDay: Int
    let cautions: [String]
}

struct EvidenceBasedSupplementInfo: Identifiable {
    let id: String
    let name: String
    let evidenceLevel: String
    let focus: String
    let defaultRoutineTitle: String
    let defaultRoutineDetail: String
    let keyUse: String
    let cautions: [String]
}

struct EvidenceBasedHairCareInfo: Identifiable {
    let id: String
    let name: String
    let evidenceLevel: String
    let focus: String
    let whyItAddsValue: String
    let defaultRoutineTitle: String
    let defaultRoutineDetail: String
    let defaultFrequencyLabel: String
    let cautions: [String]
}

enum MedicationEvidenceCatalog {
    static let androgeneticAlopecia: [ApprovedMedicationInfo] = [
        ApprovedMedicationInfo(
            id: "minoxidil",
            name: "Minoxidil",
            approvalScope: "FDA-approved topical hair regrowth treatment for patterned scalp hair loss products; labeling differs by product and sex.",
            route: "Topical",
            keyUse: "Used for androgenetic-pattern scalp hair loss.",
            defaultDosage: "1 mL / label amount",
            defaultFrequencyPerDay: 2,
            cautions: [
                "Not a diagnosis tool: sudden or patchy loss needs assessment before self-treatment.",
                "Stop and seek care for chest pain, rapid heartbeat, dizziness, swelling, or significant scalp reaction."
            ]
        ),
        ApprovedMedicationInfo(
            id: "finasteride",
            name: "Finasteride 1 mg",
            approvalScope: "FDA-approved for male pattern hair loss in men.",
            route: "Oral",
            keyUse: "Prescription treatment for androgenetic alopecia in men.",
            defaultDosage: "1 mg",
            defaultFrequencyPerDay: 1,
            cautions: [
                "Requires clinician discussion about sexual side effects, mood changes, and PSA interpretation.",
                "Not an app-directed medication; should be considered with a clinician."
            ]
        )
    ]

    static let alopeciaAreata: [ApprovedMedicationInfo] = [
        ApprovedMedicationInfo(
            id: "baricitinib",
            name: "Baricitinib",
            approvalScope: "FDA-approved for adults with severe alopecia areata.",
            route: "Oral JAK inhibitor",
            keyUse: "Systemic option for severe alopecia areata under specialist care.",
            defaultDosage: "Per prescribing clinician",
            defaultFrequencyPerDay: 1,
            cautions: [
                "Has boxed warnings and lab-monitoring requirements.",
                "Not appropriate for cosmetic-pattern hair loss."
            ]
        ),
        ApprovedMedicationInfo(
            id: "ritlecitinib",
            name: "Ritlecitinib",
            approvalScope: "FDA-approved for people age 12 and older with severe alopecia areata.",
            route: "Oral JAK inhibitor",
            keyUse: "Specialist treatment for severe alopecia areata.",
            defaultDosage: "Per prescribing clinician",
            defaultFrequencyPerDay: 1,
            cautions: [
                "Needs clinician oversight and safety review.",
                "Intended for severe alopecia areata, not routine shedding."
            ]
        ),
        ApprovedMedicationInfo(
            id: "deuruxolitinib",
            name: "Deuruxolitinib",
            approvalScope: "FDA-approved for adults with severe alopecia areata.",
            route: "Oral JAK inhibitor",
            keyUse: "Another specialist systemic option for severe alopecia areata.",
            defaultDosage: "Per prescribing clinician",
            defaultFrequencyPerDay: 2,
            cautions: [
                "Has serious-risk counseling needs similar to other JAK inhibitors.",
                "Use belongs in specialist evaluation and monitoring."
            ]
        )
    ]
}

enum SupplementEvidenceCatalog {
    static let deficiencyDirected: [EvidenceBasedSupplementInfo] = [
        EvidenceBasedSupplementInfo(
            id: "protein-support",
            name: "Protein Support",
            evidenceLevel: "Best supported when overall protein intake is low or recovery intake is inadequate.",
            focus: "Hair shaft support",
            defaultRoutineTitle: "Protein support",
            defaultRoutineDetail: "Use a protein supplement only if daily intake is low; aim to meet needs with food first.",
            keyUse: "Hair is protein-based, so inadequate intake can worsen shedding and weak growth.",
            cautions: [
                "This is a nutrition support tool, not a direct anti-DHT treatment.",
                "Chronic kidney disease or other medical conditions may require clinician advice before higher protein intake."
            ]
        ),
        EvidenceBasedSupplementInfo(
            id: "iron-if-deficient",
            name: "Iron",
            evidenceLevel: "Reasonable evidence when iron deficiency or low ferritin is present; not a default supplement for everyone.",
            focus: "Deficiency correction",
            defaultRoutineTitle: "Iron supplement",
            defaultRoutineDetail: "Take only if deficiency or low ferritin has been identified and dose is appropriate for you.",
            keyUse: "Deficiency correction can matter for shedding and telogen-style hair loss.",
            cautions: [
                "Iron can be harmful if taken unnecessarily or in excess.",
                "Constipation, stomach upset, and medication interactions are common."
            ]
        ),
        EvidenceBasedSupplementInfo(
            id: "vitamin-d-if-deficient",
            name: "Vitamin D",
            evidenceLevel: "Commonly low in hair-loss populations, but supplementation is most defensible when deficiency is confirmed.",
            focus: "Deficiency correction",
            defaultRoutineTitle: "Vitamin D",
            defaultRoutineDetail: "Supplement if blood levels are low or intake/sun exposure is inadequate.",
            keyUse: "Useful when deficiency is present, but not established as a universal hair-growth supplement.",
            cautions: [
                "Avoid megadoses without labs or clinician guidance.",
                "Benefit for hair is less clear when vitamin D status is already normal."
            ]
        ),
        EvidenceBasedSupplementInfo(
            id: "zinc-if-deficient",
            name: "Zinc",
            evidenceLevel: "May help when zinc intake or status is low, but routine long-term use is not well supported.",
            focus: "Deficiency correction",
            defaultRoutineTitle: "Zinc",
            defaultRoutineDetail: "Use short term or deficiency-directed dosing rather than indefinite daily use.",
            keyUse: "Zinc is involved in protein synthesis and follicle biology, but excess can create other deficiencies.",
            cautions: [
                "Long-term or high-dose zinc can lower copper status.",
                "Routine use without a reason is not a strong evidence-based default."
            ]
        )
    ]

    static let limitedAntiDHT: [EvidenceBasedSupplementInfo] = [
        EvidenceBasedSupplementInfo(
            id: "saw-palmetto",
            name: "Saw Palmetto",
            evidenceLevel: "Limited human evidence; much weaker than prescription anti-DHT medicines.",
            focus: "Limited anti-DHT evidence",
            defaultRoutineTitle: "Saw palmetto",
            defaultRoutineDetail: "Use only if you want to track a low-evidence anti-androgen supplement trial.",
            keyUse: "Sometimes used as a botanical anti-androgen, but evidence is modest and inconsistent.",
            cautions: [
                "Do not treat this as a supplement equivalent to finasteride.",
                "Can interact with anticoagulants and may cause stomach upset or headache."
            ]
        ),
        EvidenceBasedSupplementInfo(
            id: "pumpkin-seed-oil",
            name: "Pumpkin Seed Oil",
            evidenceLevel: "Limited early evidence from small trials; promising but not robustly proven.",
            focus: "Limited anti-DHT evidence",
            defaultRoutineTitle: "Pumpkin seed oil",
            defaultRoutineDetail: "Track as an adjunct trial rather than an evidence-established main treatment.",
            keyUse: "Studied as a possible anti-androgen / follicle-support option, but data remain limited.",
            cautions: [
                "Hair evidence is much smaller than for minoxidil or finasteride.",
                "Use this as a personal-tracking experiment, not a proven replacement."
            ]
        )
    ]
}

enum HairCareEvidenceCatalog {
    static let valueAdding: [EvidenceBasedHairCareInfo] = [
        EvidenceBasedHairCareInfo(
            id: "ketoconazole-shampoo",
            name: "Ketoconazole Shampoo",
            evidenceLevel: "High value for dandruff or seborrheic-dermatitis patterns; limited adjunct evidence for androgenetic alopecia.",
            focus: "Flaking, itch, seb derm context",
            whyItAddsValue: "Worth tracking when flakes, itch, oiliness, or seborrheic dermatitis are part of the picture. It is more defensible as scalp-inflammation care than as a primary hair-regrowth treatment.",
            defaultRoutineTitle: "Ketoconazole wash",
            defaultRoutineDetail: "Use ketoconazole shampoo on the scalp as directed on the product or by your clinician, then track flaking, itch, and comfort rather than assuming regrowth.",
            defaultFrequencyLabel: "1-2 times weekly",
            cautions: [
                "Can dry the hair shaft, so overuse may worsen brittleness or feel harsh on textured hair.",
                "Useful adjunct, but not a replacement for evidence-based androgenetic alopecia treatment."
            ]
        ),
        EvidenceBasedHairCareInfo(
            id: "dandruff-active-shampoo",
            name: "Dandruff Active Shampoo",
            evidenceLevel: "High value when dandruff or scalp scaling is present.",
            focus: "Flakes, itch, oil, scalp scale",
            whyItAddsValue: "Shampoos with agents like zinc pyrithione, selenium sulfide, salicylic acid, sulfur, coal tar, or ketoconazole can help when dandruff or seb derm is driving scalp symptoms.",
            defaultRoutineTitle: "Dandruff-control wash",
            defaultRoutineDetail: "Use a dandruff shampoo only on the scalp and track whether flaking, itch, or greasy scale improve over the next few weeks.",
            defaultFrequencyLabel: "1-3 times weekly",
            cautions: [
                "Choose the active ingredient based on tolerance and scalp pattern rather than marketing language.",
                "If pain, broken skin, or persistent inflammation continue, this needs clinician review."
            ]
        ),
        EvidenceBasedHairCareInfo(
            id: "gentle-fragrance-free-shampoo",
            name: "Gentle Fragrance-Free Shampoo",
            evidenceLevel: "High value for sensitive or easily irritated scalp; no direct regrowth claim.",
            focus: "Sensitive scalp support",
            whyItAddsValue: "Reducing irritation can make scalp tracking cleaner and can prevent unnecessary flare-ups from harsh cleansers or fragrance-heavy products.",
            defaultRoutineTitle: "Gentle wash routine",
            defaultRoutineDetail: "Use a gentle, fragrance-free shampoo on wash days and watch whether burning, tightness, or irritation improve.",
            defaultFrequencyLabel: "At planned wash cadence",
            cautions: [
                "Useful for comfort and tolerance, not as an anti-DHT treatment.",
                "If scalp burning or tenderness persists, product-switching alone is not enough."
            ]
        ),
        EvidenceBasedHairCareInfo(
            id: "conditioner-breakage-support",
            name: "Conditioner / Leave-In Support",
            evidenceLevel: "High value for shaft breakage and dryness; does not treat follicle miniaturization.",
            focus: "Breakage reduction",
            whyItAddsValue: "Conditioners and leave-ins can reduce friction and help damaged hair shafts feel better, which matters when the user is mixing up breakage with true shedding.",
            defaultRoutineTitle: "Conditioning support",
            defaultRoutineDetail: "Use conditioner or a leave-in on the hair shaft to reduce friction, dryness, and breakage, then track whether fallout seems like breakage rather than root shedding.",
            defaultFrequencyLabel: "Each wash or as needed",
            cautions: [
                "Helps hair fiber quality and breakage, not androgen-driven follicle loss.",
                "Heavy products on the scalp can aggravate some seb derm-prone users."
            ]
        )
    ]

    static let lowValueClaims: [String] = [
        "Broad anti-DHT shampoo claims are much weaker than prescription finasteride or minoxidil evidence.",
        "Caffeine, rosemary, and similar cosmetic actives may be interesting to track, but they are not high-value defaults for routine creation.",
        "If a product is mainly promising regrowth without matching scalp symptoms or proven treatment context, it usually adds less value than consistent tracking."
    ]
}

struct HairCareRecommendation: Identifiable {
    let item: EvidenceBasedHairCareInfo
    let rationale: String

    var id: String { item.id }
}

enum HairCareRecommendationEngine {
    static func build(
        profile: HairProfile?,
        entries: [CheckInEntry],
        triggerEvents: [HairTriggerEvent],
        existingTasks: [RoutineTask]
    ) -> [HairCareRecommendation] {
        let recentEntries = entries
            .sorted { $0.date > $1.date }
            .prefix(6)

        let flakeCount = recentEntries.filter(\.hasFlaking).count
        let itchCount = recentEntries.filter(\.hasItch).count
        let painCount = recentEntries.filter(\.hasScalpPain).count
        let tensionCount = recentEntries.filter(\.hasTightStyleTension).count
        let lowHydrationCount = recentEntries.filter { $0.hydrationScore <= 45 }.count
        let lowScalpComfortCount = recentEntries.filter { $0.scalpScore <= 55 }.count

        let hasSebDermContext = triggerEvents.contains { $0.category == HairTriggerCategory.sebDerm.rawValue }
        let hasScalpSensitivity = profile?.scalpSensitivity == "Sensitive" || profile?.scalpSensitivity == "Dry"
        let hasFlakyProfile = profile?.scalpSensitivity == "Flaky"

        var recommendations: [HairCareRecommendation] = []

        func alreadyTracked(_ item: EvidenceBasedHairCareInfo) -> Bool {
            existingTasks.contains {
                $0.title.localizedCaseInsensitiveContains(item.defaultRoutineTitle) ||
                $0.detail.localizedCaseInsensitiveContains(item.name)
            }
        }

        func add(_ id: String, rationale: String) {
            guard let item = HairCareEvidenceCatalog.valueAdding.first(where: { $0.id == id }) else { return }
            guard !alreadyTracked(item) else { return }
            recommendations.append(HairCareRecommendation(item: item, rationale: rationale))
        }

        if flakeCount >= 2 || itchCount >= 2 || hasSebDermContext || hasFlakyProfile {
            add(
                "ketoconazole-shampoo",
                rationale: "Recent logs suggest flaking, itch, or seb derm context. Ketoconazole is most useful here as scalp-inflammation control, not as a primary regrowth tool."
            )
            add(
                "dandruff-active-shampoo",
                rationale: "Your logs suggest dandruff-like or scaling symptoms. An active dandruff shampoo is worth tracking when scalp symptoms are part of the problem."
            )
        }

        if hasScalpSensitivity || painCount >= 1 || lowScalpComfortCount >= 2 {
            add(
                "gentle-fragrance-free-shampoo",
                rationale: "Recent logs suggest sensitivity, burning, or low scalp-comfort days. A gentle shampoo can reduce avoidable irritation noise in the routine."
            )
        }

        if lowHydrationCount >= 2 || tensionCount >= 1 || profile?.primaryGoal == "Hydration" || profile?.primaryGoal == "Length retention" {
            add(
                "conditioner-breakage-support",
                rationale: "Recent dryness, tension, or a length-retention goal makes shaft-protection and breakage reduction more valuable to track."
            )
        }

        return recommendations
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
