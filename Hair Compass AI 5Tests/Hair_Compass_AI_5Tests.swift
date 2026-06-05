//
//  Hair_Compass_AI_5Tests.swift
//  Hair Compass AI 5Tests
//
//  Created by Harib Azri on 25/03/2026.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct Hair_Compass_AI_5Tests {

    @Test func calculatesInsightMetrics() async throws {
        let entries = [
            CheckInEntry(date: .now, scalpScore: 80, hydrationScore: 70, sheddingLevel: 30, stressLevel: 20, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: ""),
            CheckInEntry(date: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now, scalpScore: 90, hydrationScore: 80, sheddingLevel: 25, stressLevel: 35, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: "")
        ]

        let tasks = [
            RoutineTask(title: "Task A", detail: "", timeLabel: "08:00", weekday: 2, category: "Scalp", isCompleted: true),
            RoutineTask(title: "Task B", detail: "", timeLabel: "21:00", weekday: 3, category: "Protection", isCompleted: false)
        ]

        #expect(HairInsightCalculator.averageScore(for: entries, keyPath: \.scalpScore) == 85)
        #expect(HairInsightCalculator.averageScore(for: entries, keyPath: \.hydrationScore) == 75)
        #expect(HairInsightCalculator.completionRate(for: tasks) == 50)
    }

    @Test func computesCurrentStreakAcrossConsecutiveDays() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.startOfDay(for: .now)
        let entries = [
            CheckInEntry(date: baseDate, scalpScore: 80, hydrationScore: 70, sheddingLevel: 20, stressLevel: 20, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: ""),
            CheckInEntry(date: calendar.date(byAdding: .day, value: -1, to: baseDate) ?? baseDate, scalpScore: 85, hydrationScore: 75, sheddingLevel: 21, stressLevel: 25, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: ""),
            CheckInEntry(date: calendar.date(byAdding: .day, value: -2, to: baseDate) ?? baseDate, scalpScore: 88, hydrationScore: 78, sheddingLevel: 22, stressLevel: 18, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: "")
        ]

        #expect(HairInsightCalculator.currentStreak(for: entries, calendar: calendar) == 3)
    }

    @MainActor
    @Test func flagsRedAlertSymptoms() async throws {
        let entries = [
            CheckInEntry(date: .now, scalpScore: 62, hydrationScore: 50, sheddingLevel: 40, stressLevel: 44, hasItch: true, hasFlaking: true, hasScalpPain: true, hasPatchyHairLoss: true, hasTightStyleTension: false, note: "")
        ]

        let alerts = HairClinicalGuidance.alerts(for: entries)

        #expect(alerts.contains(where: { $0.id == "patchy-loss" }))
        #expect(alerts.contains(where: { $0.id == "pain-burning" }))
    }

    @Test func medicationCatalogContainsCurrentApprovedCategories() async throws {
        #expect(MedicationEvidenceCatalog.androgeneticAlopecia.contains(where: { $0.id == "minoxidil" }))
        #expect(MedicationEvidenceCatalog.androgeneticAlopecia.contains(where: { $0.id == "finasteride" }))
        #expect(MedicationEvidenceCatalog.alopeciaAreata.contains(where: { $0.id == "baricitinib" }))
        #expect(MedicationEvidenceCatalog.alopeciaAreata.contains(where: { $0.id == "ritlecitinib" }))
        #expect(MedicationEvidenceCatalog.alopeciaAreata.contains(where: { $0.id == "deuruxolitinib" }))
    }

    @Test func supplementCatalogSeparatesBetterSupportedAndLimitedEvidenceOptions() async throws {
        #expect(SupplementEvidenceCatalog.deficiencyDirected.contains(where: { $0.id == "protein-support" }))
        #expect(SupplementEvidenceCatalog.deficiencyDirected.contains(where: { $0.id == "iron-if-deficient" }))
        #expect(SupplementEvidenceCatalog.deficiencyDirected.contains(where: { $0.id == "vitamin-d-if-deficient" }))
        #expect(SupplementEvidenceCatalog.deficiencyDirected.contains(where: { $0.id == "zinc-if-deficient" }))
        #expect(SupplementEvidenceCatalog.limitedAntiDHT.contains(where: { $0.id == "saw-palmetto" }))
        #expect(SupplementEvidenceCatalog.limitedAntiDHT.contains(where: { $0.id == "pumpkin-seed-oil" }))
    }

    @Test func hairCareCatalogPrioritizesValueAddingScalpCare() async throws {
        #expect(HairCareEvidenceCatalog.valueAdding.contains(where: { $0.id == "ketoconazole-shampoo" }))
        #expect(HairCareEvidenceCatalog.valueAdding.contains(where: { $0.id == "dandruff-active-shampoo" }))
        #expect(HairCareEvidenceCatalog.valueAdding.contains(where: { $0.id == "gentle-fragrance-free-shampoo" }))
        #expect(HairCareEvidenceCatalog.lowValueClaims.isEmpty == false)
    }

    @MainActor
    @Test func hairCareRecommendationEngineUsesSymptomsAndContext() async throws {
        let profile = HairProfile(
            name: "Test",
            texture: "Wavy 2C / 3A",
            primaryGoal: "Hydration",
            washFrequencyDays: 4,
            preferredWashHour: 19,
            scalpSensitivity: "Flaky",
            hairLossFocus: HairLossFocus.androgeneticAlopecia.rawValue,
            patternDistribution: "",
            familyHistorySummary: "",
            notes: ""
        )
        let entries = [
            CheckInEntry(date: .now, scalpScore: 40, hydrationScore: 38, sheddingLevel: 42, stressLevel: 30, hasItch: true, hasFlaking: true, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: ""),
            CheckInEntry(date: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now, scalpScore: 48, hydrationScore: 42, sheddingLevel: 40, stressLevel: 34, hasItch: true, hasFlaking: true, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: true, note: "")
        ]
        let triggers = [
            HairTriggerEvent(category: HairTriggerCategory.sebDerm.rawValue, title: "Seb derm flare", details: "", startedAt: .now)
        ]

        let recommendations = HairCareRecommendationEngine.build(
            profile: profile,
            entries: entries,
            triggerEvents: triggers,
            existingTasks: []
        )

        #expect(recommendations.contains(where: { $0.item.id == "ketoconazole-shampoo" }))
        #expect(recommendations.contains(where: { $0.item.id == "dandruff-active-shampoo" }))
        #expect(recommendations.contains(where: { $0.item.id == "conditioner-breakage-support" }))
    }

    @Test func hairLabCatalogContainsCoreDeficiencyAndMedicalContextTests() async throws {
        #expect(HairLabCatalog.core.contains(where: { $0.id == "ferritin" }))
        #expect(HairLabCatalog.core.contains(where: { $0.id == "cbc-hemoglobin" }))
        #expect(HairLabCatalog.core.contains(where: { $0.id == "tsh" }))
        #expect(HairLabCatalog.selective.contains(where: { $0.id == "vitamin-d" }))
        #expect(HairLabCatalog.selective.contains(where: { $0.id == "b12" }))
        #expect(HairLabCatalog.selective.contains(where: { $0.id == "folate" }))
        #expect(HairLabCatalog.selective.contains(where: { $0.id == "zinc" }))
        #expect(HairLabCatalog.selective.contains(where: { $0.id == "total-testosterone" }))
        #expect(HairLabCatalog.selective.contains(where: { $0.id == "dhea-s" }))
    }

    @Test func medicationDoseEntryStoresAdherenceEvent() async throws {
        let entry = MedicationDoseEntry(
            medicationName: "Topical minoxidil",
            form: "Topical",
            loggedAt: .now,
            scheduledTimeLabel: "21:00",
            wasTaken: true,
            note: "Night application"
        )

        #expect(entry.medicationName == "Topical minoxidil")
        #expect(entry.scheduledTimeLabel == "21:00")
        #expect(entry.wasTaken)
        #expect(entry.note == "Night application")
    }

    @MainActor
    @Test func medicationScheduleFormatterUsesExplicitTimesWhenAvailable() async throws {
        let explicit = MedicationScheduleFormatter.normalizedLabels(from: "21:00, 09:00", fallbackFrequency: 2)
        let fallback = MedicationScheduleFormatter.normalizedLabels(from: "", fallbackFrequency: 2)

        #expect(explicit == ["09:00", "21:00"])
        #expect(fallback == ["09:00", "21:00"])
    }

    @Test func routineTaskStoresAiUsefulnessMetadata() async throws {
        let task = RoutineTask(
            title: "Ketoconazole shampoo",
            itemType: RoutineItemType.product.rawValue,
            detail: "Use on wash day.",
            timeLabel: "20:00",
            weekday: 2,
            category: "Wash",
            productImagePath: "/tmp/product.jpg",
            intelligenceScore: 78,
            intelligenceSummary: "Likely useful when dandruff or scalp inflammation is part of the picture."
        )

        #expect(task.itemType == "Product")
        #expect(task.productImagePath == "/tmp/product.jpg")
        #expect(task.intelligenceScore == 78)
        #expect(task.intelligenceSummary.contains("Likely useful"))
    }

    @MainActor
    @Test func routineImpactBuildsFromCheckInsAndAdherenceEntries() async throws {
        let checkInDate = Date()
        let entries = [
            CheckInEntry(
                date: checkInDate,
                scalpScore: 82,
                hydrationScore: 75,
                sheddingLevel: 22,
                stressLevel: 30,
                hasItch: false,
                hasFlaking: false,
                hasScalpPain: false,
                hasPatchyHairLoss: false,
                hasTightStyleTension: false,
                note: ""
            )
        ]

        let completions = [
            RoutineCompletionEntry(taskTitle: "Scalp serum massage", category: "Scalp", completedAt: checkInDate)
        ]

        let medEntries = [
            MedicationDoseEntry(medicationName: "Topical minoxidil", form: "Topical", loggedAt: checkInDate, wasTaken: true, note: "")
        ]
        let procedureEvents = [
            ProcedureEvent(
                title: "Injectable dutasteride",
                category: "Injection",
                performedAt: checkInDate,
                procedureDescription: "Logged for comparison."
            )
        ]

        let points = RoutineImpactCalculator.buildPoints(
            RoutineImpactInput(
                entries: entries,
                routineCompletions: completions,
                medications: [],
                medicationEntries: medEntries,
                procedureEvents: procedureEvents
            ),
            calendar: .current
        )

        #expect(points.count == 1)
        #expect(points.first?.routineActions == 1)
        #expect(points.first?.medicationEntries == 1)
        #expect(points.first?.minoxidilEntries == 1)
        #expect(points.first?.procedureEvents == 1)
        #expect(points.first?.dutasterideProcedureEvents == 1)
    }

    @MainActor
    @Test func routineImpactIncludesHealthAndLifestyleSignals() async throws {
        let calendar = Calendar.current
        let checkInDate = calendar.startOfDay(for: Date())
        let entries = [
            CheckInEntry(
                date: checkInDate,
                scalpScore: 78,
                hydrationScore: 72,
                sheddingLevel: 31,
                stressLevel: 44,
                hasItch: false,
                hasFlaking: false,
                hasScalpPain: false,
                hasPatchyHairLoss: false,
                hasTightStyleTension: false,
                note: ""
            )
        ]

        let healthMetricsByDay = [
            checkInDate: HealthDailyMetric(
                date: checkInDate,
                sleepHours: 7.4,
                exerciseMinutes: 38,
                proteinGrams: 92,
                waterLiters: 2.1
            )
        ]
        let lifestyleEntries = [
            LifestyleEntry(
                category: LifestyleCategory.smoking.rawValue,
                title: "Cigarette",
                amount: 3,
                unit: "count",
                loggedAt: checkInDate
            ),
            LifestyleEntry(
                category: LifestyleCategory.supplement.rawValue,
                title: "Protein shake",
                amount: 1,
                unit: "serving",
                loggedAt: checkInDate
            )
        ]

        let points = RoutineImpactCalculator.buildPoints(
            RoutineImpactInput(
                entries: entries,
                routineCompletions: [],
                medications: [],
                medicationEntries: [],
                procedureEvents: [],
                healthMetricsByDay: healthMetricsByDay,
                lifestyleEntries: lifestyleEntries
            ),
            calendar: calendar
        )

        #expect(points.count == 1)
        #expect(points.first?.sleepHours == 7.4)
        #expect(points.first?.exerciseMinutes == 38)
        #expect(points.first?.proteinGrams == 92)
        #expect(points.first?.waterLiters == 2.1)
        #expect(points.first?.smokingCount == 3)
        #expect(points.first?.supplementEntries == 1)
    }

    @Test func triggerCategoryCatalogContainsHighYieldTriggerHistory() async throws {
        #expect(HairTriggerCategory.allCases.contains(.recentIllness))
        #expect(HairTriggerCategory.allCases.contains(.surgery))
        #expect(HairTriggerCategory.allCases.contains(.postpartum))
        #expect(HairTriggerCategory.allCases.contains(.weightLoss))
        #expect(HairTriggerCategory.allCases.contains(.newMedication))
        #expect(HairTriggerCategory.allCases.contains(.tractionStyling))
        #expect(HairTriggerCategory.allCases.contains(.sebDerm))
    }

    @MainActor
    @Test func routineImpactBuildsLagAwareTriggerSignals() async throws {
        let calendar = Calendar.current
        let triggerDate = calendar.date(byAdding: .day, value: -21, to: calendar.startOfDay(for: .now)) ?? .now
        let entryDate = calendar.startOfDay(for: .now)

        let points = RoutineImpactCalculator.buildPoints(
            RoutineImpactInput(
                entries: [
                    CheckInEntry(date: entryDate, scalpScore: 60, hydrationScore: 62, sheddingLevel: 45, stressLevel: 30, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: "")
                ],
                routineCompletions: [],
                medications: [],
                medicationEntries: [],
                procedureEvents: [],
                healthMetricsByDay: [:],
                lifestyleEntries: [],
                triggerEvents: [
                    HairTriggerEvent(category: HairTriggerCategory.recentIllness.rawValue, title: "Fever", details: "High fever", startedAt: triggerDate, severity: "High")
                ]
            ),
            calendar: calendar
        )

        #expect(points.count == 2)
        let todayPoint = points.last
        #expect(todayPoint?.recentTriggerLoad ?? 0 > 0)
        #expect(todayPoint?.triggerEvents == 0)
    }

    @MainActor
    @Test func intelligenceComposerBuildsConservativePatternSummary() async throws {
        let today = Calendar.current.startOfDay(for: .now)
        let entries = [
            CheckInEntry(date: today, scalpScore: 68, hydrationScore: 63, sheddingLevel: 52, stressLevel: 66, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: "Stressful week"),
            CheckInEntry(date: Calendar.current.date(byAdding: .day, value: -3, to: today) ?? today, scalpScore: 71, hydrationScore: 65, sheddingLevel: 48, stressLevel: 62, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: "Routine slipped"),
            CheckInEntry(date: Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today, scalpScore: 74, hydrationScore: 68, sheddingLevel: 28, stressLevel: 30, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: "Slept better"),
            CheckInEntry(date: Calendar.current.date(byAdding: .day, value: -10, to: today) ?? today, scalpScore: 76, hydrationScore: 70, sheddingLevel: 24, stressLevel: 26, hasItch: false, hasFlaking: false, hasScalpPain: false, hasPatchyHairLoss: false, hasTightStyleTension: false, note: "More consistent")
        ]

        let impactPoints = [
            RoutineImpactPoint(date: today, sheddingScore: 52, stressScore: 66, scalpScore: 68, hydrationScore: 63, routineActions: 0, medicationEntries: 0, minoxidilEntries: 0, expectedMedicationEntries: 0, expectedMinoxidilEntries: 0, procedureEvents: 0, dutasterideProcedureEvents: 0, sleepHours: 5.2, exerciseMinutes: 10, proteinGrams: 55, waterLiters: 1.3, smokingCount: 2, supplementEntries: 0, triggerEvents: 0, tractionEvents: 0, sebDermEvents: 0, recentTriggerLoad: 1.2, recentProcedureLoad: 0),
            RoutineImpactPoint(date: Calendar.current.date(byAdding: .day, value: -3, to: today) ?? today, sheddingScore: 48, stressScore: 62, scalpScore: 71, hydrationScore: 65, routineActions: 1, medicationEntries: 0, minoxidilEntries: 0, expectedMedicationEntries: 0, expectedMinoxidilEntries: 0, procedureEvents: 0, dutasterideProcedureEvents: 0, sleepHours: 5.8, exerciseMinutes: 20, proteinGrams: 70, waterLiters: 1.8, smokingCount: 1, supplementEntries: 0, triggerEvents: 0, tractionEvents: 0, sebDermEvents: 0, recentTriggerLoad: 0.9, recentProcedureLoad: 0),
            RoutineImpactPoint(date: Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today, sheddingScore: 28, stressScore: 30, scalpScore: 74, hydrationScore: 68, routineActions: 2, medicationEntries: 1, minoxidilEntries: 1, expectedMedicationEntries: 1, expectedMinoxidilEntries: 1, procedureEvents: 0, dutasterideProcedureEvents: 0, sleepHours: 7.8, exerciseMinutes: 35, proteinGrams: 90, waterLiters: 2.2, smokingCount: 0, supplementEntries: 1, triggerEvents: 0, tractionEvents: 0, sebDermEvents: 0, recentTriggerLoad: 0.2, recentProcedureLoad: 0),
            RoutineImpactPoint(date: Calendar.current.date(byAdding: .day, value: -10, to: today) ?? today, sheddingScore: 24, stressScore: 26, scalpScore: 76, hydrationScore: 70, routineActions: 2, medicationEntries: 1, minoxidilEntries: 1, expectedMedicationEntries: 1, expectedMinoxidilEntries: 1, procedureEvents: 0, dutasterideProcedureEvents: 0, sleepHours: 8.0, exerciseMinutes: 40, proteinGrams: 96, waterLiters: 2.3, smokingCount: 0, supplementEntries: 1, triggerEvents: 0, tractionEvents: 0, sebDermEvents: 0, recentTriggerLoad: 0, recentProcedureLoad: 0)
        ]

        let report = IntelligenceComposer.build(
            entries: entries,
            impactPoints: impactPoints,
            labResults: [],
            healthMetrics: [
                HealthDailyMetric(date: today, sleepHours: 5.2, exerciseMinutes: 10, proteinGrams: 55, waterLiters: 1.3)
            ],
            medications: [
                MedicationLog(name: "Topical minoxidil", indication: "Pattern hair loss", form: "Topical", dosage: "1 mL", frequencyPerDay: 2, schedule: "Twice daily", prescribedByClinician: false)
            ],
            procedureEvents: []
        )

        #expect(report.headline.isEmpty == false)
        #expect(report.observations.count >= 2)
        #expect(report.observations.contains(where: { $0.localizedCaseInsensitiveContains("smoking") }))
        #expect(report.dataGaps.contains(where: { $0.localizedCaseInsensitiveContains("lab") }))
        #expect(report.suggestions.contains(where: { $0.localizedCaseInsensitiveContains("minoxidil") }))
    }

}
