//
//  ExportServiceConsistencyTests.swift
//  Hair Compass AI 5Tests
//
//  Both exports carry the same per-treatment consistency shown in Plan. The score's denominator
//  is due/scored actions; the stable planned count is included separately so an open action is
//  visible without quietly changing the percentage.
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct ExportServiceConsistencyTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Muscat")!
        value.firstWeekday = 2
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))!
    }

    private func daysAgo(_ count: Int, hour: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: -count, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    private func fixture() throws -> (Treatment, [TreatmentDose]) {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self, SideEffectLog.self,
            MissedDoseRecord.self, LabResult.self, PhotoRecord.self, HealthSnapshot.self,
            TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let treatment = Treatment(
            name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
            scheduleTimes: "21:00", startDate: daysAgo(10), isActive: true
        )
        context.insert(treatment)
        var doses: [TreatmentDose] = []
        for day in 1...9 where day != 4 {
            let dose = TreatmentDose(treatment: treatment, loggedAt: daysAgo(day, hour: 21), slot: "21:00")
            context.insert(dose)
            doses.append(dose)
        }
        return (treatment, doses)
    }

    @Test func clinicianSummaryNamesDueAndPlannedDenominatorsHonestly() throws {
        let (treatment, doses) = try fixture()
        let text = ExportService.clinicianSummary(
            profile: nil, entries: [], treatments: [treatment], doses: doses,
            labs: [], triggers: [], progressCheckIns: [], missedDoses: [],
            now: now, calendar: calendar
        )
        #expect(text.contains("30-day consistency 80% of due actions (8 completed of 10 due; 11 planned through today)"))
        #expect(text.contains("this week 5 completed of 6 due; 7 planned through today"))
        #expect(!text.contains("14-day"))
        #expect(!text.contains("adherence"))
    }

    @Test func jsonCarriesBothConsistencyWindowsPerTreatment() throws {
        let (treatment, doses) = try fixture()
        let data = try #require(ExportService.dataJSON(
            profile: nil, entries: [], treatments: [treatment], doses: doses,
            labs: [], triggers: [], progressCheckIns: [], snapshots: [], missedDoses: [],
            now: now, calendar: calendar
        ))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let treatments = try #require(object["treatments"] as? [[String: Any]])
        let thirty = try #require(treatments[0]["consistency30"] as? [String: Any])
        let seven = try #require(treatments[0]["consistency7"] as? [String: Any])
        #expect(thirty["completed"] as? Int == 8)
        #expect(thirty["planned"] as? Int == 11)
        #expect(thirty["scored"] as? Int == 10)
        #expect(thirty["percent"] as? Int == 80)
        #expect(seven["completed"] as? Int == 5)
        #expect(seven["planned"] as? Int == 7)
        #expect(seven["scored"] as? Int == 6)
        #expect(seven["percent"] as? Int == 83)
        #expect(thirty["expected"] == nil)
    }

    @Test func openOnlyWindowHasNoPercentInEitherExport() throws {
        let treatment = Treatment(
            name: "Started today", treatmentClass: .finasteride, dose: "1 mg",
            scheduleTimes: "21:00", startDate: daysAgo(0, hour: 1), isActive: true
        )
        let text = ExportService.clinicianSummary(
            profile: nil, entries: [], treatments: [treatment], doses: [],
            labs: [], triggers: [], progressCheckIns: [], missedDoses: [],
            now: now, calendar: calendar
        )
        #expect(text.contains("30-day consistency: not enough due actions yet (0 completed; 1 planned through today)"))
        #expect(!text.contains("consistency 0%"))

        let data = try #require(ExportService.dataJSON(
            profile: nil, entries: [], treatments: [treatment], doses: [],
            labs: [], triggers: [], progressCheckIns: [], snapshots: [], missedDoses: [],
            now: now, calendar: calendar
        ))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let treatments = try #require(object["treatments"] as? [[String: Any]])
        let thirty = try #require(treatments[0]["consistency30"] as? [String: Any])
        #expect(thirty["scored"] as? Int == 0)
        #expect(thirty["percent"] == nil)
    }
}
