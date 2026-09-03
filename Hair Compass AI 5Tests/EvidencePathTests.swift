//
//  EvidencePathTests.swift
//  Hair Compass AI 5Tests
//
//  The evidence path is data from the plan's clock: which milestones exist, which are behind,
//  which is next, and the five things each one states. Strands are the shared adherence engine
//  per treatment, including the honest planned-but-unscored state.
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct EvidencePathTests {
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

    private func phase(daysAgo count: Int) -> EvidencePhase {
        let treatment = Treatment(
            name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "",
            scheduleTimes: "08:00", startDate: daysAgo(count), isActive: true
        )
        return EvidencePhase.current(
            treatments: [treatment], entries: [], now: now, calendar: calendar
        )!
    }

    @Test func fourMilestonesBeforeWeekTwentyFour() {
        let milestones = EvidencePath.milestones(
            phase: phase(daysAgo: 33), photos: [], calendar: calendar
        )

        #expect(milestones.map(\.week) == [0, 4, 12, 24])
        #expect(milestones.map(\.state) == [.reached, .reached, .next, .ahead])
        #expect(milestones[2].title == "Week 12 review")
    }

    @Test func aFifthMilestoneAppearsAfterTwentyFour() {
        let milestones = EvidencePath.milestones(
            phase: phase(daysAgo: 200), photos: [], calendar: calendar
        )

        #expect(milestones.map(\.week) == [0, 4, 12, 24, 36])
        #expect(milestones.map(\.state) == [.reached, .reached, .reached, .reached, .next])
        #expect(milestones[4].title == "Week 36 review")
    }

    @Test func baselineKnowsWhetherAPhotoAnchorsIt() {
        let currentPhase = phase(daysAgo: 10)
        let withPhoto = EvidencePath.milestones(
            phase: currentPhase,
            photos: [PhotoRecord(createdAt: daysAgo(9))],
            calendar: calendar
        )
        let withoutPhoto = EvidencePath.milestones(
            phase: currentPhase, photos: [], calendar: calendar
        )

        #expect(withPhoto[0].nextAction == "Keep logging; the first review is at week four.")
        #expect(withoutPhoto[0].nextAction == "Take a baseline photo in good light when you can.")
    }

    @Test func everyMilestoneStatesFiveThingsWithoutDiagnosisOrPressure() {
        let milestones = EvidencePath.milestones(
            phase: phase(daysAgo: 200), photos: [], calendar: calendar
        )
        let banned = ["diagnos", "cure", "you have", "prescrib", "you should", "you must", "!", "failed", "poor"]

        for milestone in milestones {
            #expect(!milestone.why.isEmpty)
            #expect(!milestone.evidence.isEmpty)
            #expect(!milestone.nextAction.isEmpty)
            for text in [milestone.title, milestone.why, milestone.evidence, milestone.nextAction] {
                for word in banned {
                    #expect(!text.lowercased().contains(word), "\(milestone.title): \(text)")
                }
            }
        }
        #expect(milestones[3].interpretable && milestones[3].needsPhoto)
        #expect(!milestones[1].interpretable && !milestones[1].needsPhoto)
    }

    @Test func milestoneDatesFollowThePlanStart() {
        let currentPhase = phase(daysAgo: 33)
        let weekFour = EvidencePath.date(ofWeek: 4, phase: currentPhase, calendar: calendar)

        #expect(calendar.dateComponents([.day], from: currentPhase.start, to: weekFour).day == 28)
    }

    @Test func strandsCarrySevenAndThirtyDayNumbersAndAnUnscoredState() throws {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
            SideEffectLog.self, MissedDoseRecord.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: schema, configurations: configuration))
        let finasteride = Treatment(
            name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
            scheduleTimes: "21:00", startDate: daysAgo(10), isActive: true
        )
        let asNeeded = Treatment(
            name: "PRP session", treatmentClass: .prp, dose: "", scheduleTimes: "",
            startDate: daysAgo(50), isActive: true
        )
        context.insert(finasteride)
        context.insert(asNeeded)
        var doses: [TreatmentDose] = []
        for offset in 1...9 where offset != 4 {
            let dose = TreatmentDose(
                treatment: finasteride, loggedAt: daysAgo(offset, hour: 21), slot: "21:00"
            )
            context.insert(dose)
            doses.append(dose)
        }

        let strands = PlanStrands.build(
            treatments: [finasteride, asNeeded], doses: doses, missed: [],
            now: now, calendar: calendar
        )
        #expect(strands.count == 2)
        let finasterideStrand = try #require(strands.first { $0.name == "Finasteride" })
        #expect(finasterideStrand.isScheduled)
        #expect(finasterideStrand.thirtyDay == PlanAdherence.Consistency(
            completed: 8, planned: 11, scored: 10
        ))
        let asNeededStrand = try #require(strands.first { $0.name == "PRP session" })
        #expect(!asNeededStrand.isScheduled)
        #expect(asNeededStrand.thirtyDay == nil && asNeededStrand.sevenDay == nil)
        let overall = PlanStrands.overall(
            treatments: [finasteride, asNeeded], doses: doses, missed: [],
            windowDays: 30, now: now, calendar: calendar
        )
        #expect(overall == PlanAdherence.Consistency(completed: 8, planned: 11, scored: 10))

        let fresh = Treatment(
            name: "Started today", treatmentClass: .finasteride, dose: "1 mg",
            scheduleTimes: "21:00", startDate: daysAgo(0, hour: 1), isActive: true
        )
        context.insert(fresh)
        let open = try #require(PlanStrands.build(
            treatments: [fresh], doses: [], missed: [], now: now, calendar: calendar
        ).first)
        #expect(open.thirtyDay == PlanAdherence.Consistency(completed: 0, planned: 1, scored: 0))
        #expect(open.isUnscored)
    }
}
