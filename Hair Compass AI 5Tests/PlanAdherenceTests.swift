//
//  PlanAdherenceTests.swift
//  Hair Compass AI 5Tests
//
//  The adherence engine's rules, pinned on an in-memory store with a fixed calendar so no test
//  depends on the clock: which occurrences exist, what state each carries, who counts in the
//  denominator, and how today's plan and the week strip fold from them.
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct PlanAdherenceTests {

    // MARK: Fixture

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
        c.firstWeekday = 2 // Monday
        return c
    }

    /// Wednesday 2026-09-09, 09:30 local.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))!
    }

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: base)!
    }

    private func minoxidil(in context: ModelContext, startedDaysAgo: Int = 30) -> Treatment {
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: day(-startedDaysAgo), isActive: true)
        context.insert(t)
        return t
    }

    private func log(_ t: Treatment, dayOffset: Int, slot: String, in context: ModelContext) {
        let hour = PlanAdherence.slotMinutes(slot).map { $0 / 60 } ?? 12
        context.insert(TreatmentDose(treatment: t, loggedAt: day(dayOffset, hour: hour), slot: slot))
    }

    private func fetchAll(_ context: ModelContext) throws -> (doses: [TreatmentDose], missed: [MissedDoseRecord]) {
        (try context.fetch(FetchDescriptor<TreatmentDose>()), try context.fetch(FetchDescriptor<MissedDoseRecord>()))
    }

    // MARK: Occurrences

    @Test func dailyTreatmentYieldsOneOccurrencePerSlotPerDueDay() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: [], missed: [],
                                            from: day(-2), through: day(0), now: now, calendar: calendar)
        #expect(occ.count == 6)
        #expect(occ.map(\.slot) == ["08:00", "21:00", "08:00", "21:00", "08:00", "21:00"])
    }

    @Test func doseMarksCompletedWithItsTimestamp() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        log(t, dayOffset: -1, slot: "08:00", in: context)
        let all = try fetchAll(context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: all.doses, missed: all.missed,
                                            from: day(-1), through: day(-1), now: now, calendar: calendar)
        #expect(occ[0].state == .completed)
        #expect(occ[0].completedAt.map { calendar.component(.hour, from: $0) } == 8)
        #expect(occ[1].state == .missed)
    }

    @Test func todaysSlotsAreDueOnceReachedAndUpcomingBefore() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: [], missed: [],
                                            from: day(0), through: day(0), now: now, calendar: calendar)
        #expect(occ.map(\.state) == [.due, .upcoming]) // 09:30: 08:00 has passed, 21:00 has not
        #expect(occ[0].isOpen && occ[1].isOpen)
    }

    @Test func skipRecordCountsAgainstButClinicianPauseIsNotExpected() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        context.insert(MissedDoseRecord(treatment: t, date: day(-1), slot: "08:00", reason: .travel))
        context.insert(MissedDoseRecord(treatment: t, date: day(-1), slot: "21:00", reason: .clinicianDirectedPause))
        let all = try fetchAll(context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: all.doses, missed: all.missed,
                                            from: day(-1), through: day(-1), now: now, calendar: calendar)
        #expect(occ.map(\.state) == [.skipped, .notExpected])
        let c = try #require(PlanAdherence.consistency(occurrences: occ))
        #expect(c.completed == 0 && c.planned == 1 && c.scored == 1)
    }

    @Test func pausedTreatmentKeepsTheStopDayUpToTheStopTime() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        t.isActive = false
        t.endDate = day(-1, hour: 10)
        let occ = PlanAdherence.occurrences(treatment: t, doses: [], missed: [],
                                            from: day(-3), through: day(0), now: now, calendar: calendar)
        // -3 and -2: both slots. -1 (the stop day, paused at 10:00): only the 08:00 slot, which
        // fell before the stop time. 0: nothing — after the stop day.
        #expect(occ.count == 5)
        #expect(!occ.contains { $0.day == calendar.startOfDay(for: day(0)) })
    }

    @Test func pausedTreatmentKeepsACompletedDoseOnTheStopDay() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        log(t, dayOffset: -1, slot: "08:00", in: context)
        t.isActive = false
        t.endDate = day(-1, hour: 10)
        let all = try fetchAll(context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: all.doses, missed: all.missed,
                                            from: day(-1), through: day(-1), now: now, calendar: calendar)
        #expect(occ.count == 1)
        #expect(occ[0].state == .completed)
    }

    @Test func startDateClampsTheWindow() throws {
        let context = try makeContext()
        let t = minoxidil(in: context, startedDaysAgo: 2)
        log(t, dayOffset: -2, slot: "08:00", in: context)
        log(t, dayOffset: -2, slot: "21:00", in: context)
        log(t, dayOffset: -1, slot: "21:00", in: context)
        let all = try fetchAll(context)
        let c = try #require(PlanAdherence.consistency(treatment: t, doses: all.doses, missed: all.missed,
                                                       windowDays: 30, now: now, calendar: calendar))
        // Three days × two slots, including today's two open slots, which are planned but not
        // yet scored.
        #expect(c.planned == 6)
        #expect(c.scored == 4) // two past days × two slots
        #expect(c.completed == 3)
        #expect(c.percent == 75)
    }

    @Test func consistencyAcrossTreatmentsClampsEachStart() throws {
        let context = try makeContext()
        let minox = minoxidil(in: context) // 30 days ago, two slots
        let fin = Treatment(name: "Finasteride 1mg", treatmentClass: .finasteride, dose: "1 mg",
                            scheduleTimes: "21:00", startDate: day(-2), isActive: true)
        context.insert(fin)
        let c = try #require(PlanAdherence.consistency(
            treatments: [minox, fin], doses: [], missed: [],
            from: day(-6), through: day(0), now: now, calendar: calendar
        ))
        // Minoxidil: seven days (including today) × two slots = 14 planned, of which the six
        // past days' 12 slots are scored. Finasteride started 2 days ago: three days × one slot
        // = 3 planned, of which the two past days' 2 slots are scored. Today's open slots are
        // planned but not scored for either treatment.
        #expect(c.planned == 14 + 3)
        #expect(c.scored == 12 + 2)
        #expect(c.completed == 0)
    }

    @Test func asNeededTreatmentHasNoConsistency() throws {
        let context = try makeContext()
        let prp = Treatment(name: "PRP session", treatmentClass: .prp, dose: "",
                            scheduleTimes: "", startDate: day(-50), isActive: true)
        context.insert(prp)
        #expect(!PlanAdherence.hasSchedule(prp))
        #expect(PlanAdherence.consistency(treatment: prp, doses: [], missed: [],
                                          windowDays: 30, now: now, calendar: calendar) == nil)
    }

    @Test func weekdayDevicesHaveASchedule() throws {
        let context = try makeContext()
        let device = Treatment(name: "Dermaroller", treatmentClass: .microneedling, dose: "",
                               scheduleTimes: "", startDate: day(-30), isActive: true)
        device.scheduledWeekdays = [2, 5] // Monday, Thursday
        context.insert(device)
        #expect(PlanAdherence.hasSchedule(device))
        let occ = PlanAdherence.occurrences(treatment: device, doses: [], missed: [],
                                            from: day(-6), through: day(0), now: now, calendar: calendar)
        // Wed 9 Sep back to Thu 3 Sep: Thu 3 and Mon 7 are scheduled.
        #expect(occ.count == 2)
        #expect(occ.allSatisfy { $0.slot == "" })
    }

    @Test func periodicCareProductCountsOnlyItsWeekdays() throws {
        let context = try makeContext()
        let shampoo = Treatment(name: "Ketoconazole shampoo", treatmentClass: .shampoo, dose: "",
                                scheduleTimes: "", startDate: day(-30), isActive: true)
        shampoo.scheduledWeekdays = [2, 5] // Monday, Thursday
        context.insert(shampoo)
        let occ = PlanAdherence.occurrences(treatment: shampoo, doses: [], missed: [],
                                            from: day(-6), through: day(0), now: now, calendar: calendar)
        // Wed 9 Sep back to Thu 3 Sep: Thu 3 and Mon 7 are scheduled.
        #expect(occ.count == 2)
        #expect(occ.allSatisfy { $0.slot == "" })
        #expect(occ.map(\.state) == [.missed, .missed])
    }

    @Test func todaysOpenOccurrencesArePlannedButNotScored() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        log(t, dayOffset: 0, slot: "08:00", in: context)
        let all = try fetchAll(context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: all.doses, missed: all.missed,
                                            from: day(0), through: day(0), now: now, calendar: calendar)
        let c = try #require(PlanAdherence.consistency(occurrences: occ))
        // 08:00 logged (completed, scored); 21:00 still upcoming — planned, not scored.
        #expect(c.completed == 1 && c.planned == 2 && c.scored == 1)
    }

    @Test func plannedDenominatorIsInvariantAcrossLogging() throws {
        let context = try makeContext()
        let t = minoxidil(in: context, startedDaysAgo: 10)
        var all = try fetchAll(context)
        let before = try #require(PlanAdherence.consistency(treatment: t, doses: all.doses, missed: all.missed,
                                                             windowDays: 7, now: now, calendar: calendar))
        #expect(before.planned == 14)
        #expect(before.completed == 0)
        #expect(before.scored == 12)

        log(t, dayOffset: 0, slot: "08:00", in: context)
        log(t, dayOffset: 0, slot: "21:00", in: context)
        all = try fetchAll(context)
        let after = try #require(PlanAdherence.consistency(treatment: t, doses: all.doses, missed: all.missed,
                                                            windowDays: 7, now: now, calendar: calendar))
        // The denominator today's completions land in never moves.
        #expect(after.planned == 14)
        #expect(after.completed == before.completed + 2)
        #expect(after.scored == before.scored + 2)
    }

    @Test func percentReadsOnlySettledOccurrences() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        log(t, dayOffset: 0, slot: "08:00", in: context)
        let all = try fetchAll(context)
        let c = try #require(PlanAdherence.consistency(treatment: t, doses: all.doses, missed: all.missed,
                                                       windowDays: 1, now: now, calendar: calendar))
        // 08:00 logged; 21:00 has not been reached yet at 09:30 — planned but not scored, so it
        // does not pull the percentage down.
        #expect(c.planned == 2)
        #expect(c.scored == 1)
        #expect(c.completed == 1)
        #expect(c.percent == 100)
    }

    @Test func futureDaysNeverEnterPlanned() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        let clamped = try #require(PlanAdherence.consistency(
            treatments: [t], doses: [], missed: [],
            from: day(0), through: day(0), now: now, calendar: calendar
        ))
        let unclamped = try #require(PlanAdherence.consistency(
            treatments: [t], doses: [], missed: [],
            from: day(0), through: day(3), now: now, calendar: calendar
        ))
        #expect(unclamped == clamped)
    }

    @Test func openOnlyWindowIsPlannedButUnscored() throws {
        let context = try makeContext()
        let t = minoxidil(in: context, startedDaysAgo: 0)
        let c = try #require(PlanAdherence.consistency(treatment: t, doses: [], missed: [],
                                                       windowDays: 1, now: now, calendar: calendar))
        // Started today: 08:00 is due, 21:00 is upcoming, nothing logged — both planned, neither
        // settled yet, so scoring nothing does not read as 0%.
        #expect(c == PlanAdherence.Consistency(completed: 0, planned: 2, scored: 0))
        #expect(c.percent == 0)
    }

    // MARK: Today

    @Test func todayPlanSortsBySlotAndKnowsWhenItIsComplete() throws {
        let context = try makeContext()
        let minox = minoxidil(in: context)
        let fin = Treatment(name: "Finasteride 1mg", treatmentClass: .finasteride, dose: "1 mg",
                            scheduleTimes: "21:00", startDate: day(-30), isActive: true)
        context.insert(fin)
        var plan = PlanAdherence.today(treatments: [fin, minox], doses: [], missed: [], now: now, calendar: calendar)
        #expect(plan.occurrences.map { "\($0.treatment.name)@\($0.slot)" }
                == ["Minoxidil 5%@08:00", "Finasteride 1mg@21:00", "Minoxidil 5%@21:00"])
        #expect(plan.openCount == 3 && !plan.isComplete && !plan.nothingExpected)
        #expect(plan.nextOpen?.slot == "08:00")

        log(minox, dayOffset: 0, slot: "08:00", in: context)
        log(minox, dayOffset: 0, slot: "21:00", in: context)
        context.insert(MissedDoseRecord(treatment: fin, date: day(0), slot: "21:00", reason: .supply))
        let all = try fetchAll(context)
        plan = PlanAdherence.today(treatments: [fin, minox], doses: all.doses, missed: all.missed, now: now, calendar: calendar)
        #expect(plan.isComplete)
        #expect(plan.completedCount == 2 && plan.settledCount == 3 && plan.openCount == 0)
    }

    @Test func todayPlanIsEmptyWhenNothingIsScheduled() throws {
        let context = try makeContext()
        let paused = minoxidil(in: context)
        paused.isActive = false
        paused.endDate = day(-1)
        let plan = PlanAdherence.today(treatments: [paused], doses: [], missed: [], now: now, calendar: calendar)
        #expect(plan.nothingExpected && !plan.isComplete)
    }

    // MARK: Week

    @Test func weekMarksEveryStateWithoutRed() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        // Mon 7: both slots. Tue 8: one slot. Wed 9 (today): none yet. Thu–Sun: future.
        log(t, dayOffset: -2, slot: "08:00", in: context)
        log(t, dayOffset: -2, slot: "21:00", in: context)
        log(t, dayOffset: -1, slot: "08:00", in: context)
        let all = try fetchAll(context)
        let week = PlanAdherence.week(treatments: [t], doses: all.doses, missed: all.missed, now: now, calendar: calendar)
        #expect(week.count == 7)
        #expect(week.map(\.mark) == [.complete, .partial, .today, .upcoming, .upcoming, .upcoming, .upcoming])
        #expect(week[0].completed == 2 && week[0].expected == 2)
        #expect(week[1].completed == 1 && week[1].expected == 2)
    }

    @Test func weekShowsMissedAndNotExpectedDays() throws {
        let context = try makeContext()
        let shampoo = Treatment(name: "Shampoo", treatmentClass: .shampoo, dose: "",
                                scheduleTimes: "", startDate: day(-30), isActive: true)
        shampoo.scheduledWeekdays = [2] // Monday only
        context.insert(shampoo)
        let week = PlanAdherence.week(treatments: [shampoo], doses: [], missed: [], now: now, calendar: calendar)
        // Today (Wed) has nothing scheduled (Monday-only shampoo), but it still gets `.today`,
        // not `.notExpected` — the "you are here" outline never disappears on a quiet day.
        #expect(week.map(\.mark) == [.missed, .notExpected, .today, .upcoming, .upcoming, .upcoming, .upcoming])
    }

    // MARK: Slots

    @Test func slotHelpers() {
        #expect(PlanAdherence.slotMinutes("08:00") == 480)
        #expect(PlanAdherence.slotMinutes("21:15") == 1275)
        #expect(PlanAdherence.slotMinutes("") == nil)
        #expect(PlanAdherence.isReached(slot: "08:00", now: now, calendar: calendar))
        #expect(!PlanAdherence.isReached(slot: "21:00", now: now, calendar: calendar))
        #expect(PlanAdherence.isReached(slot: "", now: now, calendar: calendar))
        let at = PlanAdherence.slotDate("21:00", on: now, calendar: calendar)
        #expect(at.map { calendar.component(.hour, from: $0) } == 21)
    }
}
