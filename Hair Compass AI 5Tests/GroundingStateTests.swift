//
//  GroundingStateTests.swift
//  Hair Compass AI 5Tests
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct GroundingStateTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Muscat")!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9))!
    }

    private func input(consistency: PlanAdherence.Consistency) throws -> GroundingInput {
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
            name: "Minoxidil 5%", treatmentClass: .minoxidil,
            scheduleTimes: "21:00", startDate: now, isActive: true
        )
        context.insert(treatment)
        return GroundingInput(
            flags: [],
            plan: PlanAdherence.today(
                treatments: [treatment], doses: [], missed: [], now: now, calendar: calendar
            ),
            missedYesterday: 0,
            phase: EvidencePhase.current(treatments: [treatment], entries: [], now: now, calendar: calendar),
            photo: .upcoming(daysUntil: 8),
            photoWithinTwoWeeks: true,
            consistency30: consistency,
            sheddingAboveUsual: false,
            loggedToday: false
        )
    }

    @Test func payloadCarriesPlannedScoredAndConditionalPercent() throws {
        let scored = GroundingState.payload(try input(consistency: .init(completed: 8, planned: 11, scored: 10)))
        let scoredConsistency = try #require(scored["consistency_30d"] as? [String: Any])
        #expect(scoredConsistency["completed"] as? Int == 8)
        #expect(scoredConsistency["planned"] as? Int == 11)
        #expect(scoredConsistency["scored"] as? Int == 10)
        #expect(scoredConsistency["percent"] as? Int == 80)
        #expect(scoredConsistency["expected"] == nil)

        let open = GroundingState.payload(try input(consistency: .init(completed: 0, planned: 1, scored: 0)))
        let openConsistency = try #require(open["consistency_30d"] as? [String: Any])
        #expect(openConsistency["planned"] as? Int == 1)
        #expect(openConsistency["scored"] as? Int == 0)
        #expect(openConsistency["percent"] == nil)
    }

    @Test func everyPayloadNumberCanBeValidatedButUnscoredZeroPercentCannot() throws {
        let value = try input(consistency: .init(completed: 0, planned: 1, scored: 0))
        let allowed = GroundingState.allowedNumbers(value)
        #expect(allowed.contains("5"))
        #expect(allowed.contains("21"))
        #expect(!((value.consistency30?.scored ?? 0) > 0))
    }

    @Test func fingerprintChangesWhenOnlyTheScoredDenominatorChanges() throws {
        let first = try input(consistency: .init(completed: 8, planned: 11, scored: 10))
        let second = try input(consistency: .init(completed: 8, planned: 11, scored: 9))
        #expect(GroundingState.fingerprint(first) != GroundingState.fingerprint(second))
    }
}
