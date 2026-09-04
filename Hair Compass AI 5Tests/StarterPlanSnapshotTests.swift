//
//  StarterPlanSnapshotTests.swift
//  Hair Compass AI 5Tests
//
//  The finale and the Plan tab must show the same plan. `fresh` (finale) and `make` over an
//  empty record (tab, a moment later) have to agree item for item.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct StarterPlanSnapshotTests {

    private func profile(condition: HairCondition, sex: BiologicalSex, pregnancy: PregnancyStatus = .no) -> Profile {
        let p = Profile()
        p.condition = condition
        p.sex = sex
        p.pregnancyStatus = pregnancy
        return p
    }

    @Test func finaleAndTabAgreeOnAFreshRecord() {
        let p = profile(condition: .androgenetic, sex: .female, pregnancy: .breastfeeding)
        let finale = StarterPlan.Snapshot.fresh(profile: p)
        let tab = StarterPlan.Snapshot.make(
            profile: p, labs: [], treatments: [], photos: [], procedures: [], entries: [],
            remindersEnabled: false, dismissed: []
        )
        // The finale is shown before finish() seeds today's entry, so it counts today as logged;
        // the tab derives it. Everything else must be identical.
        var tabLogged = tab
        tabLogged.loggedToday = true
        #expect(finale == tabLogged)
        #expect(StarterPlan.items(for: finale).map(\.id) == StarterPlan.items(for: tabLogged).map(\.id))
    }

    @Test func makeDerivesDoneFromTheRecord() {
        let p = profile(condition: .telogenEffluvium, sex: .female)
        let lab = LabResult()
        lab.test = .ferritin
        let treatment = Treatment()
        treatment.treatmentClass = .minoxidil
        let entryToday = DailyEntry()
        entryToday.date = Date()
        let s = StarterPlan.Snapshot.make(
            profile: p, labs: [lab], treatments: [treatment], photos: [PhotoRecord()],
            procedures: [], entries: [entryToday], remindersEnabled: true, dismissed: ["lab.zinc"]
        )
        #expect(s.labTests == [.ferritin])
        #expect(s.treatmentClasses == [.minoxidil])
        #expect(s.hasAnyTreatment && s.hasAnyLab && s.hasBaselinePhoto && s.remindersEnabled && s.loggedToday)
        #expect(s.dismissed == ["lab.zinc"])
    }

    @Test func loggedTodayIsCalendarDayNotTwentyFourHours() {
        let p = profile(condition: .unsure, sex: .male)
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 23, minute: 50))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 23, minute: 55))!
        let e = DailyEntry()
        e.date = yesterday
        let s = StarterPlan.Snapshot.make(
            profile: p, labs: [], treatments: [], photos: [], procedures: [], entries: [e],
            remindersEnabled: false, dismissed: [], today: today, calendar: cal
        )
        #expect(s.loggedToday == false)
    }

    @Test func dismissalsRoundTripThroughJSON() {
        let ids: Set<String> = ["lab.zinc", "setup.reminders"]
        let json = StarterPlanDismissals.encode(ids)
        #expect(StarterPlanDismissals.decode(json) == ids)
        #expect(StarterPlanDismissals.decode("").isEmpty)
        #expect(StarterPlanDismissals.decode("not json").isEmpty)
        #expect(StarterPlanDismissals.encode([]) == "[]")
    }

    @Test func consultationCompletionRequiresAttendanceAndAPastDate() {
        let p = profile(condition: .unsure, sex: .male)
        let now = Date()
        let visit = ProcedureAppointment(type: .consultation, date: now.addingTimeInterval(-3600))
        func snapshot() -> StarterPlan.Snapshot {
            .make(profile: p, labs: [], treatments: [], photos: [], procedures: [visit], entries: [],
                  remindersEnabled: false, dismissed: [], today: now)
        }
        #expect(!snapshot().hasCompletedConsultation)
        visit.isCompleted = true
        #expect(snapshot().hasCompletedConsultation)
        visit.date = now.addingTimeInterval(3600)
        #expect(!snapshot().hasCompletedConsultation)
    }
}
