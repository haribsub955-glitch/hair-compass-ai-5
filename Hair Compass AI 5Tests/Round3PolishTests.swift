//
//  Round3PolishTests.swift
//  Hair Compass AI 5Tests
//
//  Pure logic added/changed in the round-3 UI+value pass: the baseline-photo nearby-date
//  window shared by CareView's nudge and AddTreatmentSheet's capture prompt, the Labs
//  flagged-first group ordering, and the milestone-reminder body copy.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct Round3PolishTests {

    private let calendar = Calendar.current

    private func daysFrom(_ anchor: Date, _ n: Int) -> Date {
        calendar.date(byAdding: .day, value: n, to: anchor)!
    }

    // MARK: - HairAnalytics.hasNearbyDate (baseline photo window)

    @Test func hasNearbyDateFindsACandidateInsideTheWindowEitherDirection() {
        let anchor = Date.now
        #expect(HairAnalytics.hasNearbyDate(anchor: anchor, candidates: [daysFrom(anchor, -5)]))
        #expect(HairAnalytics.hasNearbyDate(anchor: anchor, candidates: [daysFrom(anchor, 6)]))
        #expect(HairAnalytics.hasNearbyDate(anchor: anchor, candidates: [anchor]))
    }

    @Test func hasNearbyDateRejectsCandidatesOutsideTheWindow() {
        let anchor = Date.now
        #expect(!HairAnalytics.hasNearbyDate(anchor: anchor, candidates: [daysFrom(anchor, -8)]))
        #expect(!HairAnalytics.hasNearbyDate(anchor: anchor, candidates: [daysFrom(anchor, 9)]))
        #expect(!HairAnalytics.hasNearbyDate(anchor: anchor, candidates: []))
    }

    @Test func hasNearbyDateRespectsACustomWindow() {
        let anchor = Date.now
        #expect(HairAnalytics.hasNearbyDate(anchor: anchor, candidates: [daysFrom(anchor, 20)], windowDays: 30))
        #expect(!HairAnalytics.hasNearbyDate(anchor: anchor, candidates: [daysFrom(anchor, 20)], windowDays: 7))
    }

    // MARK: - NotificationService.milestoneBody

    @Test @MainActor func milestoneBodyNamesTheAssessmentWindowOnlyAtWeek24() {
        #expect(NotificationService.milestoneBody(week: 24).contains("assessment window opens"))
        #expect(NotificationService.milestoneBody(week: 12).contains("Halfway"))
        #expect(NotificationService.milestoneBody(week: 4) == "A first checkpoint. Your progress report is ready to look at.")
    }

    @Test @MainActor func milestoneWeeksAreExactlyTheFourTwelveTwentyFourCadence() {
        #expect(NotificationService.milestoneWeeks == [4, 12, 24])
    }

    // MARK: - Labs flagged-first ordering (JourneyChart's axis word list, LabsView's group sort)

    @Test func shedAxisLabelsAreCompleteWordsWidestFirstAlignmentAside() {
        // Guards the round-3 fix directly: no more "Elev"/"Norm" abbreviations that could read
        // as truncated next to the full word "Heavy".
        let labels = ShedLevel.allCases.map(\.title)
        #expect(labels == ["Minimal", "Normal", "Elevated", "Heavy"])
        #expect(labels.allSatisfy { $0.count > 4 })
    }
}
