//
//  MissedDoseRepositoryTests.swift
//  Hair Compass AI 5Tests
//
//  MissedDoseRepository.delete's natural key: treatment + calendar day + exact slot, the same
//  triple DoseRepository uses. Deleting one treatment's skip record — the Undo of a skip — must
//  never touch another treatment's record for the same day and slot.
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct MissedDoseRepositoryTests {

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

    @Test func deleteRemovesOnlyTheMatchingRecord() throws {
        let context = try makeContext()
        let minox = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil)
        let fin = Treatment(name: "Finasteride 1mg", treatmentClass: .finasteride)
        context.insert(minox)
        context.insert(fin)
        let today = Date.now
        let repository = MissedDoseRepository(context: context, calendar: calendar)
        _ = try repository.record(treatment: minox, day: today, slot: "21:00", reason: .forgot)
        _ = try repository.record(treatment: fin, day: today, slot: "21:00", reason: .forgot)

        let removed = try repository.delete(treatment: minox, day: today, slot: "21:00")

        #expect(removed)
        let remaining = try context.fetch(FetchDescriptor<MissedDoseRecord>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.treatment?.persistentModelID == fin.persistentModelID)
    }

    @Test func deleteReturnsFalseWhenNothingMatches() throws {
        let context = try makeContext()
        let minox = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil)
        context.insert(minox)
        let repository = MissedDoseRepository(context: context, calendar: calendar)

        let removed = try repository.delete(treatment: minox, day: .now, slot: "21:00")

        #expect(!removed)
        #expect(try context.fetch(FetchDescriptor<MissedDoseRecord>()).isEmpty)
    }
}
