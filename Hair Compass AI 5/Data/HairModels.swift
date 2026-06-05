//
//  Item.swift
//  Hair Compass AI 5
//
//  Created by Harib Azri on 25/03/2026.
//

import Foundation
import SwiftData

@Model
final class HairProfile {
    var name: String
    var texture: String
    var primaryGoal: String
    var washFrequencyDays: Int
    var preferredWashHour: Int
    var scalpSensitivity: String
    var hairLossFocus: String
    var patternDistribution: String
    var familyHistorySummary: String
    var hasCompletedOnboarding: Bool
    var notes: String
    var createdAt: Date
    var ageRange: String
    var biologicalSex: String
    var hairLossDuration: String

    init(
        name: String,
        texture: String,
        primaryGoal: String,
        washFrequencyDays: Int,
        preferredWashHour: Int,
        scalpSensitivity: String,
        hairLossFocus: String,
        patternDistribution: String,
        familyHistorySummary: String,
        hasCompletedOnboarding: Bool = false,
        notes: String,
        createdAt: Date = .now,
        ageRange: String = "",
        biologicalSex: String = "",
        hairLossDuration: String = ""
    ) {
        self.name = name
        self.texture = texture
        self.primaryGoal = primaryGoal
        self.washFrequencyDays = washFrequencyDays
        self.preferredWashHour = preferredWashHour
        self.scalpSensitivity = scalpSensitivity
        self.hairLossFocus = hairLossFocus
        self.patternDistribution = patternDistribution
        self.familyHistorySummary = familyHistorySummary
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.notes = notes
        self.createdAt = createdAt
        self.ageRange = ageRange
        self.biologicalSex = biologicalSex
        self.hairLossDuration = hairLossDuration
    }
}

@Model
final class CheckInEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var scalpScore: Int
    var hydrationScore: Int
    var sheddingLevel: Int
    var stressLevel: Int
    var hasItch: Bool
    var hasFlaking: Bool
    var hasScalpPain: Bool
    var hasPatchyHairLoss: Bool
    var hasTightStyleTension: Bool
    // Property-level default is required for SwiftData lightweight migration:
    // existing rows from a schema without this attribute migrate to `false`
    // instead of failing with "missing attribute values on mandatory destination attribute".
    var isWashDay: Bool = false
    var note: String
    @Relationship(deleteRule: .nullify) var dailyObservation: DailyObservation?

    init(
        id: UUID = UUID(),
        date: Date,
        scalpScore: Int,
        hydrationScore: Int,
        sheddingLevel: Int,
        stressLevel: Int,
        hasItch: Bool,
        hasFlaking: Bool,
        hasScalpPain: Bool,
        hasPatchyHairLoss: Bool,
        hasTightStyleTension: Bool,
        isWashDay: Bool = false,
        note: String,
        dailyObservation: DailyObservation? = nil
    ) {
        self.id = id
        self.date = date
        self.scalpScore = scalpScore
        self.hydrationScore = hydrationScore
        self.sheddingLevel = sheddingLevel
        self.stressLevel = stressLevel
        self.hasItch = hasItch
        self.hasFlaking = hasFlaking
        self.hasScalpPain = hasScalpPain
        self.hasPatchyHairLoss = hasPatchyHairLoss
        self.hasTightStyleTension = hasTightStyleTension
        self.isWashDay = isWashDay
        self.note = note
        self.dailyObservation = dailyObservation
    }
}

@Model
final class DailyObservation {
    @Attribute(.unique) var id: UUID
    var date: Date
    var summary: String

    init(
        id: UUID = UUID(),
        date: Date,
        summary: String = ""
    ) {
        self.id = id
        self.date = date
        self.summary = summary
    }
}

@Model
final class RoutineTask {
    var title: String
    var itemType: String
    var detail: String
    var timeLabel: String
    var weekday: Int
    var category: String
    var productImagePath: String
    var intelligenceScore: Int
    var intelligenceSummary: String
    var isCompleted: Bool
    var recurrenceType: String
    var recurrenceInterval: Int
    var recurrenceWeekdays: String
    var startDate: Date
    var endDate: Date?
    var updatedAt: Date
    @Relationship(deleteRule: .nullify, inverse: \RoutineCompletionEntry.task) var completions: [RoutineCompletionEntry]?

    init(
        title: String,
        itemType: String = "Habit",
        detail: String,
        timeLabel: String,
        weekday: Int,
        category: String,
        productImagePath: String = "",
        intelligenceScore: Int = 0,
        intelligenceSummary: String = "",
        isCompleted: Bool = false,
        recurrenceType: String = RoutineRecurrenceType.weekly.rawValue,
        recurrenceInterval: Int = 1,
        recurrenceWeekdays: String = "",
        startDate: Date = .now,
        endDate: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.title = title
        self.itemType = itemType
        self.detail = detail
        self.timeLabel = timeLabel
        self.weekday = weekday
        self.category = category
        self.productImagePath = productImagePath
        self.intelligenceScore = intelligenceScore
        self.intelligenceSummary = intelligenceSummary
        self.isCompleted = isCompleted
        self.recurrenceType = recurrenceType
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceWeekdays = recurrenceWeekdays
        self.startDate = startDate
        self.endDate = endDate
        self.updatedAt = updatedAt
    }
}

enum RoutineItemType: String, CaseIterable, Identifiable {
    case product = "Product"
    case habit = "Habit"
    case technique = "Technique"
    case device = "Device"
    case supplement = "Supplement"

    var id: String { rawValue }
}

enum RoutineRecurrenceType: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case everyNDays = "Every N Days"
    case monthly = "Monthly"

    var id: String { rawValue }
}

@Model
final class PhotoRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var sessionTitle: String
    var angle: String
    var imagePath: String
    var notes: String
    var analysisSummary: String
    var analysisUpdatedAt: Date?
    @Relationship(deleteRule: .nullify) var checkIn: CheckInEntry?
    @Relationship(deleteRule: .nullify) var dailyObservation: DailyObservation?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sessionTitle: String,
        angle: String,
        imagePath: String,
        notes: String = "",
        analysisSummary: String = "",
        analysisUpdatedAt: Date? = nil,
        checkIn: CheckInEntry? = nil,
        dailyObservation: DailyObservation? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sessionTitle = sessionTitle
        self.angle = angle
        self.imagePath = imagePath
        self.notes = notes
        self.analysisSummary = analysisSummary
        self.analysisUpdatedAt = analysisUpdatedAt
        self.checkIn = checkIn
        self.dailyObservation = dailyObservation
    }
}

@Model
final class MedicationLog {
    @Attribute(.unique) var id: UUID
    var name: String
    var indication: String
    var form: String
    var dosage: String
    var frequencyPerDay: Int
    var schedule: String
    var scheduledTimes: String
    var startedAt: Date
    var prescribedByClinician: Bool
    var isActive: Bool
    var notes: String
    @Relationship(deleteRule: .nullify, inverse: \MedicationDoseEntry.medication) var doseEntries: [MedicationDoseEntry]?

    init(
        id: UUID = UUID(),
        name: String,
        indication: String,
        form: String,
        dosage: String,
        frequencyPerDay: Int,
        schedule: String,
        scheduledTimes: String = "",
        startedAt: Date = .now,
        prescribedByClinician: Bool,
        isActive: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.indication = indication
        self.form = form
        self.dosage = dosage
        self.frequencyPerDay = frequencyPerDay
        self.schedule = schedule
        self.scheduledTimes = scheduledTimes
        self.startedAt = startedAt
        self.prescribedByClinician = prescribedByClinician
        self.isActive = isActive
        self.notes = notes
    }
}

@Model
final class MedicationDoseEntry {
    var medication: MedicationLog?
    var medicationName: String
    var form: String
    var loggedAt: Date
    var scheduledTimeLabel: String
    var wasTaken: Bool
    var note: String

    init(
        medication: MedicationLog? = nil,
        medicationName: String,
        form: String,
        loggedAt: Date = .now,
        scheduledTimeLabel: String = "",
        wasTaken: Bool = true,
        note: String = ""
    ) {
        self.medication = medication
        self.medicationName = medicationName
        self.form = form
        self.loggedAt = loggedAt
        self.scheduledTimeLabel = scheduledTimeLabel
        self.wasTaken = wasTaken
        self.note = note
    }
}

@Model
final class RoutineCompletionEntry {
    var task: RoutineTask?
    var taskTitle: String
    var category: String
    var completedAt: Date

    init(
        task: RoutineTask? = nil,
        taskTitle: String,
        category: String,
        completedAt: Date = .now
    ) {
        self.task = task
        self.taskTitle = taskTitle
        self.category = category
        self.completedAt = completedAt
    }
}

@Model
final class ProcedureEvent {
    var title: String
    var category: String
    var performedAt: Date
    var procedureDescription: String
    var clinicianName: String
    var notes: String

    init(
        title: String,
        category: String,
        performedAt: Date = .now,
        procedureDescription: String,
        clinicianName: String = "",
        notes: String = ""
    ) {
        self.title = title
        self.category = category
        self.performedAt = performedAt
        self.procedureDescription = procedureDescription
        self.clinicianName = clinicianName
        self.notes = notes
    }
}

@Model
final class LifestyleEntry {
    var category: String
    var title: String
    var amount: Double
    var unit: String
    var loggedAt: Date
    var notes: String

    init(
        category: String,
        title: String,
        amount: Double,
        unit: String,
        loggedAt: Date = .now,
        notes: String = ""
    ) {
        self.category = category
        self.title = title
        self.amount = amount
        self.unit = unit
        self.loggedAt = loggedAt
        self.notes = notes
    }
}

@Model
final class LabResultEntry {
    var testID: String
    var testName: String
    var valueText: String
    var unit: String
    var status: String
    var collectedAt: Date
    var notes: String

    init(
        testID: String,
        testName: String,
        valueText: String,
        unit: String,
        status: String,
        collectedAt: Date = .now,
        notes: String = ""
    ) {
        self.testID = testID
        self.testName = testName
        self.valueText = valueText
        self.unit = unit
        self.status = status
        self.collectedAt = collectedAt
        self.notes = notes
    }
}

@Model
final class HairTriggerEvent {
    var category: String
    var title: String
    var details: String
    var startedAt: Date
    var endedAt: Date?
    var severity: String
    var affectsSheddingRisk: Bool

    init(
        category: String,
        title: String,
        details: String,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        severity: String = "Moderate",
        affectsSheddingRisk: Bool = true
    ) {
        self.category = category
        self.title = title
        self.details = details
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.severity = severity
        self.affectsSheddingRisk = affectsSheddingRisk
    }
}
