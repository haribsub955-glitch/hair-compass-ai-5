//
//  GroundingKeysTests.swift
//  Hair Compass AI 5Tests
//
//  The pure key functions Today's grounding surface keys its entrance animation and its
//  provider `.task` on (Model/GroundingKeys.swift): the entrance identity changes on a day
//  rollover or a meaningful card change and never on a reopen; the fingerprint changes when the
//  record actually changes and never when it does not.
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct GroundingKeysTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Muscat")!
        c.firstWeekday = 2 // Monday
        return c
    }
    /// Wednesday 2026-09-09, 09:30 local.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))!
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
            SideEffectLog.self, MissedDoseRecord.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeCard(kind: GroundingCard.Kind = .quiet, headline: String = "You are allowed to have a normal day") -> GroundingCard {
        GroundingCard(
            kind: kind, eyebrow: "Today's grounding", headline: headline,
            body: "No unusual pattern or plan action needs your attention right now.",
            evidenceAnchor: nil, primary: .none, closure: "The check-in is the whole day.",
            reason: "Nothing in the record met an earlier rule today."
        )
    }

    private func input(
        plan: PlanAdherence.TodayPlan,
        loggedToday: Bool = false,
        consistency30: PlanAdherence.Consistency? = nil
    ) -> GroundingInput {
        GroundingInput(
            flags: [], plan: plan, missedYesterday: 0, phase: nil,
            photo: .upcoming(daysUntil: 12), photoWithinTwoWeeks: true,
            consistency30: consistency30, sheddingAboveUsual: false, loggedToday: loggedToday
        )
    }

    // MARK: entranceKey

    @Test func dayRolloverChangesTheEntranceKey() {
        let card = makeCard()
        let today = GroundingKeys.dayKey(now, calendar: calendar)
        let tomorrow = GroundingKeys.dayKey(calendar.date(byAdding: .day, value: 1, to: now)!, calendar: calendar)
        #expect(GroundingKeys.entranceKey(dayKey: today, card: card) != GroundingKeys.entranceKey(dayKey: tomorrow, card: card))
    }

    @Test func aNewKindOrHeadlineChangesTheEntranceKey() {
        let dayKey = GroundingKeys.dayKey(now, calendar: calendar)
        let base = makeCard()
        let newKind = makeCard(kind: .education)
        let newHeadline = makeCard(headline: "A different headline entirely")
        let baseKey = GroundingKeys.entranceKey(dayKey: dayKey, card: base)
        #expect(baseKey != GroundingKeys.entranceKey(dayKey: dayKey, card: newKind))
        #expect(baseKey != GroundingKeys.entranceKey(dayKey: dayKey, card: newHeadline))
    }

    @Test func theSameCardTwiceProducesTheSameEntranceKey() {
        let dayKey = GroundingKeys.dayKey(now, calendar: calendar)
        let card = makeCard()
        #expect(GroundingKeys.entranceKey(dayKey: dayKey, card: card) == GroundingKeys.entranceKey(dayKey: dayKey, card: card))
    }

    @Test func aPersistedEntranceDoesNotReplayOnReopen() {
        let key = GroundingKeys.entranceKey(dayKey: GroundingKeys.dayKey(now, calendar: calendar), card: makeCard())
        #expect(GroundingKeys.shouldAnimateEntrance(persistedKey: "", currentKey: key))
        #expect(!GroundingKeys.shouldAnimateEntrance(persistedKey: key, currentKey: key))
    }

    @Test func closeTheDayIncludesAnInitiallyCompleteColdLaunchOnlyOnce() {
        let day = GroundingKeys.dayKey(now, calendar: calendar)
        #expect(GroundingKeys.shouldCelebrate(
            isComplete: true, completedCount: 2, celebratedDay: "", dayKey: day
        ))
        #expect(!GroundingKeys.shouldCelebrate(
            isComplete: true, completedCount: 2, celebratedDay: day, dayKey: day
        ))
        #expect(!GroundingKeys.shouldCelebrate(
            isComplete: true, completedCount: 0, celebratedDay: "", dayKey: day
        ))
    }

    // MARK: fingerprint

    @Test func fingerprintIsStableWhenNothingChanged() throws {
        let context = try makeContext()
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: calendar.date(byAdding: .day, value: -33, to: now)!, isActive: true)
        context.insert(t)
        let plan = PlanAdherence.today(treatments: [t], doses: [], missed: [], now: now, calendar: calendar)
        let dayKey = GroundingKeys.dayKey(now, calendar: calendar)
        let a = GroundingKeys.fingerprint(input(plan: plan), dayKey: dayKey)
        let b = GroundingKeys.fingerprint(input(plan: plan), dayKey: dayKey)
        #expect(a == b)
    }

    @Test func fingerprintChangesWhenAnOccurrenceStateChanges() throws {
        let context = try makeContext()
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: calendar.date(byAdding: .day, value: -33, to: now)!, isActive: true)
        context.insert(t)
        let dayKey = GroundingKeys.dayKey(now, calendar: calendar)
        let openPlan = PlanAdherence.today(treatments: [t], doses: [], missed: [], now: now, calendar: calendar)
        let dose = TreatmentDose(treatment: t, loggedAt: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now)!, slot: "08:00")
        context.insert(dose)
        let partlyDonePlan = PlanAdherence.today(treatments: [t], doses: [dose], missed: [], now: now, calendar: calendar)
        let before = GroundingKeys.fingerprint(input(plan: openPlan), dayKey: dayKey)
        let after = GroundingKeys.fingerprint(input(plan: partlyDonePlan), dayKey: dayKey)
        #expect(before != after)
    }

    @Test func fingerprintChangesWhenLoggedTodayFlips() throws {
        let context = try makeContext()
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: calendar.date(byAdding: .day, value: -33, to: now)!, isActive: true)
        context.insert(t)
        let plan = PlanAdherence.today(treatments: [t], doses: [], missed: [], now: now, calendar: calendar)
        let dayKey = GroundingKeys.dayKey(now, calendar: calendar)
        let notLogged = GroundingKeys.fingerprint(input(plan: plan, loggedToday: false), dayKey: dayKey)
        let logged = GroundingKeys.fingerprint(input(plan: plan, loggedToday: true), dayKey: dayKey)
        #expect(notLogged != logged)
    }

    @Test func fingerprintChangesWhenOnlyTheScoredDenominatorChanges() throws {
        let context = try makeContext()
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: calendar.date(byAdding: .day, value: -33, to: now)!, isActive: true)
        context.insert(t)
        let plan = PlanAdherence.today(treatments: [t], doses: [], missed: [], now: now, calendar: calendar)
        let dayKey = GroundingKeys.dayKey(now, calendar: calendar)
        let openWindow = PlanAdherence.Consistency(completed: 8, planned: 11, scored: 10)
        let settledWindow = PlanAdherence.Consistency(completed: 8, planned: 11, scored: 11)

        let before = GroundingKeys.fingerprint(input(plan: plan, consistency30: openWindow), dayKey: dayKey)
        let after = GroundingKeys.fingerprint(input(plan: plan, consistency30: settledWindow), dayKey: dayKey)
        #expect(before != after)
    }
}
