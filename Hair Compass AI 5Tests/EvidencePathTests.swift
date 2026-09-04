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

    @Test func evidenceLensesAlwaysUseTheirOwnFixedOrderAndRules() throws {
        let values = EvidenceSignals.build(
            entries: [], treatments: [], doses: [], missed: [], sideEffects: [],
            photos: [], labs: [], triggers: [], now: now, calendar: calendar
        )

        #expect(values.map(\.kind) == [.treatment, .shedding, .scalp, .photos, .labs, .events])
        #expect(values.allSatisfy { !$0.rule.isEmpty && !$0.nextAction.isEmpty })
        #expect(values.map(\.action) == [
            .addTreatment, .logToday, .logToday, .captureBaseline, .addLab, .addEvent,
        ])
        #expect(try #require(values.first { $0.kind == .treatment }).rule.contains("week 24"))
        #expect(try #require(values.first { $0.kind == .shedding }).rule.contains("wash days separate"))
        #expect(try #require(values.first { $0.kind == .photos }).rule.contains("at least 28 days"))
        #expect(try #require(values.first { $0.kind == .labs }).rule.contains("each test"))
        #expect(try #require(values.first { $0.kind == .events }).rule.contains("8–12 week lag"))
    }

    @Test func sheddingNeedsFiveLikeForLikeSamplesSpreadAcrossTwoWeeks() throws {
        let tooClose = (0..<5).map { offset in
            DailyEntry(date: daysAgo(offset), shed: .elevated, washedHair: true)
        }
        let building = try #require(signal(.shedding, entries: tooClose))
        #expect(building.state == .building)
        #expect(building.summary.contains("more days of separation"))

        let spread = [14, 11, 8, 5, 1].map {
            DailyEntry(date: daysAgo($0), shed: .elevated, washedHair: true)
        } + [13, 10, 7, 4, 0].map {
            DailyEntry(date: daysAgo($0), shed: .normal, washedHair: false)
        }
        let readable = try #require(signal(.shedding, entries: spread))
        #expect(readable.state == .readable)
        #expect(readable.status == "Both wash contexts are readable")
        #expect(readable.summary.contains("5 wash-day and 5 non-wash"))
    }

    @Test func sheddingDeDuplicatesImportedEntriesFromTheSameDay() throws {
        let entries = [13, 10, 7, 4].flatMap { offset in
            [
                DailyEntry(date: daysAgo(offset, hour: 9), shed: .normal),
                DailyEntry(date: daysAgo(offset, hour: 18), shed: .heavy),
            ]
        }
        let result = try #require(signal(.shedding, entries: entries))

        #expect(result.state == .building)
        #expect(result.summary.contains("4 non-wash observations"))
    }

    @Test func sheddingTimeSpanMustBelongToTheSameWashContext() throws {
        let compressedWashSeries = (0..<5).map { offset in
            DailyEntry(date: daysAgo(offset), shed: .elevated, washedHair: true)
        }
        // This older non-wash row stretches the combined record beyond 14 days, but it must not
        // make the five tightly-clustered wash observations readable.
        let unrelatedContext = DailyEntry(date: daysAgo(14), shed: .normal, washedHair: false)
        let result = try #require(signal(
            .shedding, entries: compressedWashSeries + [unrelatedContext]
        ))

        #expect(result.state == .building)
        #expect(result.status == "Context-matched baseline building")
        #expect(result.summary.contains("days of separation"))
    }

    @Test func scalpUsesTheAdaptedScoreAndASeparateFourteenDayWindow() throws {
        let compressed = (0..<7).map { offset in
            DailyEntry(date: daysAgo(offset), flaking: 3, erythema: 2, itch: 2)
        }
        #expect(try #require(signal(.scalp, entries: compressed)).state == .building)

        let spread = [14, 12, 10].map {
            DailyEntry(date: daysAgo($0), flaking: 3, erythema: 0, itch: 0)
        } + [8].map {
            DailyEntry(date: daysAgo($0), flaking: 1, erythema: 1, itch: 1)
        } + [6, 3, 0].map {
            DailyEntry(date: daysAgo($0), flaking: 0, erythema: 0, itch: 0)
        }
        let readable = try #require(signal(.scalp, entries: spread))
        #expect(readable.state == .readable)
        #expect(readable.status == "Symptoms are easing in this window")
        #expect(readable.summary.contains("latest score is 0/16 (mild)"))
    }

    @Test func photosRequireSameSeriesConditionsAndTwentyEightDays() throws {
        let baseline = PhotoRecord(
            region: .vertex, createdAt: daysAgo(40), lighting: "Window",
            distance: "Arm's length", parting: "Center", isWet: false
        )
        let mismatched = PhotoRecord(
            region: .vertex, createdAt: daysAgo(0), lighting: "Window",
            distance: "Close", parting: "Center", isWet: false
        )
        let mismatchResult = try #require(signal(.photos, photos: [baseline, mismatched]))
        #expect(mismatchResult.state == .building)
        #expect(mismatchResult.status == "Follow-up conditions do not match")
        #expect(PhotosView.compareMismatchCaption(baseline, mismatched)?.contains("distance") == true)

        let earlyMatch = PhotoRecord(
            region: .vertex, createdAt: daysAgo(20), lighting: "window",
            distance: " arm's length ", parting: "center", isWet: false
        )
        let earlyResult = try #require(signal(.photos, photos: [baseline, earlyMatch]))
        #expect(earlyResult.state == .building)
        #expect(earlyResult.status == "Matched pair is still too close")

        let matureMatch = PhotoRecord(
            region: .vertex, createdAt: daysAgo(0), lighting: "window",
            distance: " arm's length ", parting: "center", isWet: false
        )
        let matureResult = try #require(signal(.photos, photos: [baseline, matureMatch]))
        #expect(matureResult.state == .readable)
        #expect(matureResult.status == "1 comparable series ready")
        #expect(matureResult.action == .reviewPhotos)
    }

    @Test func photosWithUnknownSetupNeverMasqueradeAsMatchedEvidence() throws {
        let legacyBaseline = PhotoRecord(region: .frontal, createdAt: daysAgo(40))
        let legacyFollowUp = PhotoRecord(region: .frontal, createdAt: daysAgo(0))
        let result = try #require(signal(.photos, photos: [legacyBaseline, legacyFollowUp]))

        #expect(PhotoComparability.mismatchCaption(legacyBaseline, legacyFollowUp) == nil)
        #expect(!PhotoComparability.isEvidenceGradePair(legacyBaseline, legacyFollowUp))
        #expect(PhotosView.compareMismatchCaption(legacyBaseline, legacyFollowUp)?.contains("incomplete") == true)
        #expect(result.state == .building)
        #expect(result.status == "Photo setup details are incomplete")
        #expect(result.action == .capturePhoto)
    }

    @Test func labsCompareOnlyLikeTestsAndPrioritizeTheLatestFlag() throws {
        let improvingFerritin = [
            LabResult(test: .ferritin, value: 18, collectedAt: daysAgo(60)),
            LabResult(test: .ferritin, value: 42, collectedAt: daysAgo(2)),
        ]
        let readable = try #require(signal(.labs, labs: improvingFerritin))
        #expect(readable.state == .readable)
        #expect(readable.status == "Same-test history is readable")
        #expect(readable.summary.contains("1 moved toward its range"))

        let customRangeFlag = LabResult(
            test: .vitaminD, value: 35, collectedAt: daysAgo(1), refLow: 40, refHigh: 100
        )
        let discuss = try #require(signal(.labs, labs: improvingFerritin + [customRangeFlag]))
        #expect(discuss.state == .discuss)
        #expect(discuss.status == "1 latest result outside range")
        #expect(discuss.action == .reviewLabs)
    }

    @Test func lifeEventsUseTheLagWindowWithoutClaimingCause() throws {
        let early = TriggerEvent(type: .illness, date: daysAgo(21))
        let earlySignal = try #require(signal(.events, triggers: [early]))
        #expect(earlySignal.state == .building)
        #expect(earlySignal.status == "Context window opens in 5 weeks")

        let timely = TriggerEvent(type: .crashDiet, date: daysAgo(70))
        let timelySignal = try #require(signal(.events, triggers: [early, timely]))
        #expect(timelySignal.state == .readable)
        #expect(timelySignal.status == "Inside the 8–12 week context window")
        #expect(timelySignal.rule.contains("cannot prove"))
    }

    @Test func treatmentLensDoesNotScoreFutureActionsAndPrioritizesTolerability() throws {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
            SideEffectLog.self, MissedDoseRecord.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: schema, configurations: configuration))
        let treatment = Treatment(
            name: "Evening treatment", treatmentClass: .finasteride, dose: "1 mg",
            scheduleTimes: "21:00", startDate: daysAgo(0, hour: 1), isActive: true
        )
        context.insert(treatment)

        let waiting = try #require(signal(.treatment, treatments: [treatment]))
        #expect(waiting.state == .building)
        #expect(waiting.status == "Waiting for due actions")

        let twiceDaily = Treatment(
            name: "Short twice-daily plan", treatmentClass: .minoxidil, dose: "1 mL",
            scheduleTimes: "08:00,09:00", startDate: daysAgo(3, hour: 1), isActive: true
        )
        context.insert(twiceDaily)
        let shortWindow = try #require(signal(.treatment, treatments: [twiceDaily]))
        #expect(shortWindow.state == .building)
        #expect(shortWindow.status == "First week is still building")

        let effect = SideEffectLog(
            treatment: treatment, type: .dizziness, severity: 3, date: daysAgo(1)
        )
        context.insert(effect)
        let discuss = try #require(signal(
            .treatment, treatments: [treatment], sideEffects: [effect]
        ))
        #expect(discuss.state == .discuss)
        #expect(discuss.status == "Recent severe side effect")
        #expect(discuss.summary.contains("tolerability signal"))
    }

    private func signal(
        _ kind: EvidenceSignal.Kind,
        entries: [DailyEntry] = [],
        treatments: [Treatment] = [],
        doses: [TreatmentDose] = [],
        missed: [MissedDoseRecord] = [],
        sideEffects: [SideEffectLog] = [],
        photos: [PhotoRecord] = [],
        labs: [LabResult] = [],
        triggers: [TriggerEvent] = []
    ) -> EvidenceSignal? {
        EvidenceSignals.build(
            entries: entries, treatments: treatments, doses: doses, missed: missed,
            sideEffects: sideEffects, photos: photos, labs: labs, triggers: triggers,
            now: now, calendar: calendar
        ).first { $0.kind == kind }
    }
}
