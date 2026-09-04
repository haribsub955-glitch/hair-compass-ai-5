//
//  PendingCompletionsTests.swift
//  Hair Compass AI 5Tests
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct PendingCompletionsTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Muscat")!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 22))!
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self, SideEffectLog.self,
            MissedDoseRecord.self, LabResult.self, PhotoRecord.self, HealthSnapshot.self,
            TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ))
    }

    @Test func storeRoundTripsDeduplicatesAndClears() {
        let defaults = UserDefaults(suiteName: "PendingCompletionsTests.\(UUID().uuidString)")!
        let item = PendingCompletion(treatmentName: "Minoxidil 5%", slot: "21:00", requestedAt: now)
        PendingCompletionStore.append(item, defaults: defaults)
        PendingCompletionStore.append(item, defaults: defaults)
        #expect(PendingCompletionStore.load(defaults: defaults) == [item])
        PendingCompletionStore.clear(defaults: defaults)
        #expect(PendingCompletionStore.load(defaults: defaults).isEmpty)
    }

    @Test func applierLogsOnceAndDropsUnknownOrUnexpectedRequests() throws {
        let context = try makeContext()
        let defaults = UserDefaults(suiteName: "PendingCompletionsTests.\(UUID().uuidString)")!
        let treatment = Treatment(
            name: "Minoxidil 5%", treatmentClass: .minoxidil,
            scheduleTimes: "08:00,21:00",
            startDate: calendar.date(byAdding: .day, value: -30, to: now)!, isActive: true
        )
        context.insert(treatment)
        PendingCompletionStore.append(
            .init(treatmentName: "Minoxidil 5%", slot: "21:00", requestedAt: now), defaults: defaults
        )
        PendingCompletionStore.append(
            .init(treatmentName: "Minoxidil 5%", slot: "12:00", requestedAt: now), defaults: defaults
        )
        PendingCompletionStore.append(
            .init(treatmentName: "Ghost", slot: "21:00", requestedAt: now), defaults: defaults
        )

        #expect(try PendingCompletionApplier.apply(
            context: context, treatments: [treatment], now: now, calendar: calendar, defaults: defaults
        ) == 1)
        let doses = try context.fetch(FetchDescriptor<TreatmentDose>())
        #expect(doses.count == 1 && doses[0].slot == "21:00")
        #expect(PendingCompletionStore.load(defaults: defaults).isEmpty)

        PendingCompletionStore.append(
            .init(treatmentName: "Minoxidil 5%", slot: "21:00", requestedAt: now), defaults: defaults
        )
        _ = try PendingCompletionApplier.apply(
            context: context, treatments: [treatment], now: now, calendar: calendar, defaults: defaults
        )
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).count == 1)
    }

    @Test func yesterdayAppliesButOlderRequestsAreDropped() throws {
        let context = try makeContext()
        let defaults = UserDefaults(suiteName: "PendingCompletionsTests.\(UUID().uuidString)")!
        let treatment = Treatment(
            name: "Minoxidil 5%", treatmentClass: .minoxidil, scheduleTimes: "21:00",
            startDate: calendar.date(byAdding: .day, value: -30, to: now)!, isActive: true
        )
        context.insert(treatment)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let old = calendar.date(byAdding: .day, value: -3, to: now)!
        PendingCompletionStore.append(
            .init(treatmentName: "Minoxidil 5%", slot: "21:00", requestedAt: yesterday),
            defaults: defaults
        )
        PendingCompletionStore.append(
            .init(treatmentName: "Old", slot: "21:00", requestedAt: old),
            defaults: defaults
        )

        #expect(try PendingCompletionApplier.apply(
            context: context, treatments: [treatment], now: now, calendar: calendar, defaults: defaults
        ) == 1)
        let doses = try context.fetch(FetchDescriptor<TreatmentDose>())
        #expect(doses.count == 1 && calendar.isDate(doses[0].loggedAt, inSameDayAs: yesterday))
        #expect(PendingCompletionStore.load(defaults: defaults).isEmpty)

        PendingCompletionStore.append(
            .init(treatmentName: "Minoxidil 5%", slot: "21:00", requestedAt: old),
            defaults: defaults
        )
        #expect(try PendingCompletionApplier.apply(
            context: context, treatments: [treatment], now: now, calendar: calendar, defaults: defaults
        ) == 0)
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).count == 1)
        #expect(PendingCompletionStore.load(defaults: defaults).isEmpty)
    }
}
