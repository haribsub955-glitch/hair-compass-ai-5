//
//  GroundingCardsTests.swift
//  Hair Compass AI 5Tests
//
//  The card is a pure function of the record: the hierarchy (safety first, quiet last), the one
//  action, the closure, the reason — and the copy rule every card must pass.
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct GroundingCardsTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Muscat")!
        c.firstWeekday = 2
        return c
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))! }
    private func daysAgo(_ n: Int, hour: Int = 12) -> Date {
        let d = calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: d)!
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

    private func plan(open: Bool, in context: ModelContext) -> (PlanAdherence.TodayPlan, Treatment) {
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: daysAgo(33), isActive: true)
        context.insert(t)
        var doses: [TreatmentDose] = []
        if !open {
            doses = [TreatmentDose(treatment: t, loggedAt: daysAgo(0, hour: 8), slot: "08:00"),
                     TreatmentDose(treatment: t, loggedAt: daysAgo(0, hour: 9), slot: "21:00")]
            doses.forEach { context.insert($0) }
        }
        return (PlanAdherence.today(treatments: [t], doses: doses, missed: [], now: now, calendar: calendar), t)
    }

    private func phase(daysAgo n: Int) -> EvidencePhase {
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "", scheduleTimes: "08:00",
                          startDate: daysAgo(n), isActive: true)
        return EvidencePhase.current(treatments: [t], entries: [], now: now, calendar: calendar)!
    }

    private func input(
        flags: [ClinicianReviewFlag] = [],
        plan: PlanAdherence.TodayPlan,
        missedYesterday: Int = 0,
        phase: EvidencePhase? = nil,
        photo: PhotoCadence.Status = .upcoming(daysUntil: 12),
        photoWithinTwoWeeks: Bool = true,
        consistency30: PlanAdherence.Consistency? = PlanAdherence.Consistency(completed: 26, expected: 30),
        sheddingAboveUsual: Bool = false,
        loggedToday: Bool = true
    ) -> GroundingInput {
        GroundingInput(flags: flags, plan: plan, missedYesterday: missedYesterday, phase: phase ?? self.phase(daysAgo: 33),
                       photo: photo, photoWithinTwoWeeks: photoWithinTwoWeeks, consistency30: consistency30,
                       sheddingAboveUsual: sheddingAboveUsual, loggedToday: loggedToday)
    }

    private func isCompletionCTA(_ action: GroundingCard.Action) -> Bool {
        if case .completePlanItem = action { return true }
        return false
    }

    // MARK: Hierarchy

    @Test func safetyOutranksEverything() throws {
        let context = try makeContext()
        let (open, _) = plan(open: true, in: context)
        let flag = ClinicianReviewFlag(id: "scalpPain", title: "Scalp pain reported", detail: "Scalp pain was reported in a monthly check-in — persistent pain can be a sign of scarring alopecia, worth a prompt review.")
        let card = GroundingCards.select(input(flags: [flag], plan: open, sheddingAboveUsual: true))
        #expect(card.kind == .safety)
        #expect(card.headline == "Scalp pain reported")
        #expect(card.body == flag.detail)
        #expect(card.primary == .prepareVisit)
        #expect(card.closure.contains("prescriber"))
    }

    @Test func higherSheddingGroundsBeforeTheDueAction() throws {
        let context = try makeContext()
        let (open, t) = plan(open: true, in: context)
        let card = GroundingCards.select(input(plan: open, sheddingAboveUsual: true))
        #expect(card.kind == .grounding)
        #expect(card.headline == "One observation is not a trend")
        if case .completePlanItem(let id, let label) = card.primary {
            #expect(id == open.occurrences[0].id)
            #expect(label.contains(t.name))
        } else {
            Issue.record("the due action stays the one thing to do")
        }
    }

    @Test func dueActionBecomesContinuation() throws {
        let context = try makeContext()
        let (open, _) = plan(open: true, in: context)
        let card = GroundingCards.select(input(plan: open))
        #expect(card.kind == .continuation)
        if case .completePlanItem = card.primary {} else { Issue.record("continuation carries the due item") }
        #expect(card.evidenceAnchor == "Next review in 51 days")
        #expect(card.closure == "No photo is needed today.")
    }

    @Test func photoDueNowIsPreparation() throws {
        let context = try makeContext()
        let (done, _) = plan(open: false, in: context)
        let card = GroundingCards.select(input(plan: done, photo: .due(daysOverdue: 3)))
        #expect(card.kind == .preparation)
        #expect(card.primary == .openPhotos)
        #expect(card.headline == "A comparable photo is due")
    }

    @Test func missingBaselineIsAnInvitationNotAnOverdueTask() throws {
        let context = try makeContext()
        let (done, _) = plan(open: false, in: context)
        let card = GroundingCards.select(input(plan: done, photo: .noBaseline))
        #expect(card.kind == .preparation)
        #expect(card.headline == "A baseline photo anchors everything")
        #expect(card.closure == "Whenever you are ready — it does not have to be today.")
    }

    @Test func reviewWithinAWeekIsPreparation() throws {
        let context = try makeContext()
        let (done, _) = plan(open: false, in: context)
        let card = GroundingCards.select(input(plan: done, phase: phase(daysAgo: 80), photoWithinTwoWeeks: false))
        #expect(card.kind == .preparation)
        #expect(card.headline == "Your week 12 review is approaching")
        #expect(card.primary == .openPhotos)
    }

    @Test func completedPlanClosesTheDay() throws {
        let context = try makeContext()
        let (done, _) = plan(open: false, in: context)
        let card = GroundingCards.select(input(plan: done))
        #expect(card.kind == .closure)
        #expect(card.headline == "Your plan is complete for today")
        #expect(card.primary == .none)
        #expect(card.closure == "Nothing else needs to be checked today.")
    }

    @Test func allSkippedDayIsRecordedNotCelebrated() throws {
        let context = try makeContext()
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: daysAgo(33), isActive: true)
        context.insert(t)
        let skips = [MissedDoseRecord(treatment: t, date: daysAgo(0), slot: "08:00", reason: .forgot),
                     MissedDoseRecord(treatment: t, date: daysAgo(0), slot: "21:00", reason: .forgot)]
        skips.forEach { context.insert($0) }
        let allSkipped = PlanAdherence.today(treatments: [t], doses: [], missed: skips, now: now, calendar: calendar)
        let card = GroundingCards.select(input(plan: allSkipped))
        #expect(card.kind == .settled)
        #expect(card.headline == "Today's plan is recorded")
        #expect(!card.body.contains("showed up"))
        #expect(card.primary == .none)
    }

    @Test func missedYesterdayWithNothingDueYetIsRecovery() throws {
        let context = try makeContext()
        let evening = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                scheduleTimes: "21:00", startDate: daysAgo(33), isActive: true)
        context.insert(evening)
        let upcomingOnly = PlanAdherence.today(treatments: [evening], doses: [], missed: [], now: now, calendar: calendar)
        let card = GroundingCards.select(input(plan: upcomingOnly, missedYesterday: 1))
        #expect(card.kind == .recovery)
        #expect(card.headline == "Today is a clean place to restart")
        #expect(card.body.contains("26 of 30"))
        #expect(!card.body.lowercased().contains("double"))
        #expect(!isCompletionCTA(card.primary))
    }

    @Test func upcomingOnlyNeverBecomesACompletionCTA() throws {
        let context = try makeContext()
        let evening = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                scheduleTimes: "21:00", startDate: daysAgo(33), isActive: true)
        context.insert(evening)
        let upcomingOnly = PlanAdherence.today(treatments: [evening], doses: [], missed: [], now: now, calendar: calendar)
        for loggedToday in [true, false] {
            let grounding = GroundingCards.select(input(plan: upcomingOnly, sheddingAboveUsual: true, loggedToday: loggedToday))
            let recovery = GroundingCards.select(input(plan: upcomingOnly, missedYesterday: 2, loggedToday: loggedToday))
            let education = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 8), loggedToday: loggedToday))
            let quiet = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 60), loggedToday: loggedToday))
            for card in [grounding, recovery, education, quiet] {
                #expect(!isCompletionCTA(card.primary), "\(card.kind.rawValue) loggedToday=\(loggedToday)")
            }
        }
    }

    @Test func milestoneWeekIsRecognisedOnItsFirstTwoDays() throws {
        let context = try makeContext()
        let evening = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                scheduleTimes: "21:00", startDate: daysAgo(29), isActive: true)
        context.insert(evening)
        let upcomingOnly = PlanAdherence.today(treatments: [evening], doses: [], missed: [], now: now, calendar: calendar)
        let card = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 29)))
        #expect(card.kind == .celebration)
        #expect(card.headline == "Four weeks of evidence, stored")
        let later = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 31)))
        #expect(later.kind != .celebration)
    }

    @Test func earlyWeeksTeachTheHorizon() throws {
        let context = try makeContext()
        let evening = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                scheduleTimes: "21:00", startDate: daysAgo(8), isActive: true)
        context.insert(evening)
        let upcomingOnly = PlanAdherence.today(treatments: [evening], doses: [], missed: [], now: now, calendar: calendar)
        let card = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 8), loggedToday: false))
        #expect(card.kind == .education)
        #expect(card.headline == "You are building the baseline")
        #expect(card.primary == .logCheckIn)
    }

    @Test func quietDayGivesPermissionToClose() throws {
        let context = try makeContext()
        let evening = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                scheduleTimes: "21:00", startDate: daysAgo(60), isActive: true)
        context.insert(evening)
        let upcomingOnly = PlanAdherence.today(treatments: [evening], doses: [], missed: [], now: now, calendar: calendar)
        let card = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 60)))
        #expect(card.kind == .quiet)
        #expect(card.primary == .none)
        #expect(card.closure == "You can close the app.")
        let unlogged = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 60), loggedToday: false))
        #expect(unlogged.primary == .logCheckIn)
    }

    // MARK: Copy rule

    @Test func everyCardKeepsTheFramingRule() throws {
        let context = try makeContext()
        let (open, _) = plan(open: true, in: context)
        let (done, _) = plan(open: false, in: context)
        let flag = ClinicianReviewFlag(id: "heavyShed", title: "Heavy shedding most days", detail: "Shedding was logged Heavy on 8 of the last 14 days.")
        let allSkippedTreatment = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                                            scheduleTimes: "08:00,21:00", startDate: daysAgo(33), isActive: true)
        context.insert(allSkippedTreatment)
        let skips = [MissedDoseRecord(treatment: allSkippedTreatment, date: daysAgo(0), slot: "08:00", reason: .forgot),
                     MissedDoseRecord(treatment: allSkippedTreatment, date: daysAgo(0), slot: "21:00", reason: .forgot)]
        skips.forEach { context.insert($0) }
        let allSkipped = PlanAdherence.today(treatments: [allSkippedTreatment], doses: [], missed: skips, now: now, calendar: calendar)
        let cards = [
            GroundingCards.select(input(flags: [flag], plan: open)),
            GroundingCards.select(input(plan: open, sheddingAboveUsual: true)),
            GroundingCards.select(input(plan: open)),
            GroundingCards.select(input(plan: done, photo: .due(daysOverdue: 0))),
            GroundingCards.select(input(plan: done, photo: .noBaseline)),
            GroundingCards.select(input(plan: done, phase: phase(daysAgo: 80), photoWithinTwoWeeks: false)),
            GroundingCards.select(input(plan: done)),
            GroundingCards.select(input(plan: open, missedYesterday: 2)),
            GroundingCards.select(input(plan: done, phase: phase(daysAgo: 28))),
            GroundingCards.select(input(plan: done, phase: phase(daysAgo: 5), loggedToday: false)),
            GroundingCards.select(input(plan: done, phase: phase(daysAgo: 60))),
            GroundingCards.select(input(plan: allSkipped))
        ]
        let banned = ["diagnos", "cure", "you have", "prescrib", "you should", "you must", "start taking",
                      "anxious", "worried about", "failed", "poor", "getting worse", "!"]
        for card in cards {
            #expect(card.headline.split(separator: " ").count <= 10, "\(card.headline)")
            #expect(card.body.split(separator: " ").count <= 55, "\(card.body)")
            #expect(!card.closure.isEmpty && !card.reason.isEmpty, "\(card.headline)")
            for text in [card.headline, card.body, card.closure, card.reason, card.evidenceAnchor ?? ""] {
                let lower = text.lowercased()
                for word in banned where !(word == "prescrib" && lower.contains("prescriber")) {
                    #expect(!lower.contains(word), "\(card.kind): \(text) contains \(word)")
                }
            }
        }
    }

    @Test func daysWordReadsNaturally() {
        #expect(GroundingCards.daysWord(0) == "today")
        #expect(GroundingCards.daysWord(1) == "tomorrow")
        #expect(GroundingCards.daysWord(8) == "in 8 days")
    }

    // MARK: Signals

    @Test func sheddingAboveUsualNeedsARangeToBeAbove() {
        var entries: [DailyEntry] = []
        for n in 2...7 {
            let e = DailyEntry()
            e.date = daysAgo(n)
            e.shed = .normal
            entries.append(e)
        }
        let yesterday = DailyEntry()
        yesterday.date = daysAgo(1)
        yesterday.shed = .heavy
        #expect(GroundingSignals.sheddingAboveUsual(entries: entries + [yesterday], now: now, calendar: calendar))
        yesterday.shed = .normal
        #expect(!GroundingSignals.sheddingAboveUsual(entries: entries + [yesterday], now: now, calendar: calendar))
        #expect(!GroundingSignals.sheddingAboveUsual(entries: [yesterday], now: now, calendar: calendar))
    }

    @Test func missedYesterdayCountsMissedAndSkipped() throws {
        let context = try makeContext()
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: daysAgo(33), isActive: true)
        context.insert(t)
        let skip = MissedDoseRecord(treatment: t, date: daysAgo(1), slot: "08:00", reason: .forgot)
        context.insert(skip)
        #expect(GroundingSignals.missedYesterday(treatments: [t], doses: [], missed: [skip], now: now, calendar: calendar) == 2)
        let dose = TreatmentDose(treatment: t, loggedAt: daysAgo(1, hour: 21), slot: "21:00")
        context.insert(dose)
        #expect(GroundingSignals.missedYesterday(treatments: [t], doses: [dose], missed: [skip], now: now, calendar: calendar) == 1)
    }
}
