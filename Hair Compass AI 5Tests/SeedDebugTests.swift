//
//  SeedDebugTests.swift
//  Hair Compass AI 5Tests
//
//  The DEBUG-only QA seed helpers in Model/Seed.swift. Pinned so HC_PLANOPEN's dose-clearing
//  stays scoped to today only — a demo reset must never touch a day it wasn't asked to touch.
//

#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct SeedDebugTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
            SideEffectLog.self, MissedDoseRecord.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Muscat")!
        return c
    }

    @Test func ensureNoDosesTodayLeavesYesterdayAlone() throws {
        let context = try makeContext()
        let treatment = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil)
        context.insert(treatment)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        context.insert(TreatmentDose(treatment: treatment, loggedAt: now, slot: "08:00"))
        context.insert(TreatmentDose(treatment: treatment, loggedAt: yesterday, slot: "08:00"))

        Seed.ensureNoDosesToday(context: context, calendar: calendar, now: now)

        let remaining = try context.fetch(FetchDescriptor<TreatmentDose>())
        #expect(remaining.count == 1)
        #expect(calendar.isDate(remaining.first!.loggedAt, inSameDayAs: yesterday))
    }
}
#endif
