//
//  EvidenceRibbonCopyTests.swift
//  Hair Compass AI 5Tests
//
//  The ribbon's copy is a pure function of PlanAdherence.Consistency, PhotoCadence.Status and
//  EvidencePhase. G2-R8 (owner QA, 2026-09-04): an open-only window — planned actions exist but
//  none has settled yet — must never render a percentage, not even "0%".
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct EvidenceRibbonCopyTests {

    // MARK: - monthLine (G2-R8)

    @Test func monthLineShowsNoPercentageWhenNothingScored() {
        let consistency = PlanAdherence.Consistency(completed: 0, planned: 3, scored: 0)
        #expect(EvidenceRibbonCopy.monthLine(consistency) == "Not enough due actions yet")
    }

    @Test func monthLineShowsPercentageWhenSomethingScored() {
        let consistency = PlanAdherence.Consistency(completed: 2, planned: 5, scored: 4)
        #expect(EvidenceRibbonCopy.monthLine(consistency) == "50% · 2 of 5")
    }

    @Test func monthLineFallsBackWhenNoConsistencyAtAll() {
        #expect(EvidenceRibbonCopy.monthLine(nil) == "Not enough planned actions yet")
    }

    // MARK: - weekLine

    @Test func weekLineReadsCompletedOfPlanned() {
        let consistency = PlanAdherence.Consistency(completed: 1, planned: 3, scored: 1)
        #expect(EvidenceRibbonCopy.weekLine(consistency) == "1 of 3 planned actions")
    }

    @Test func weekLineFallsBackWhenNil() {
        #expect(EvidenceRibbonCopy.weekLine(nil) == "No planned actions")
    }

    // MARK: - photoLine

    @Test func photoLineNoBaseline() {
        #expect(EvidenceRibbonCopy.photoLine(.noBaseline) == "Baseline pending")
    }

    @Test func photoLineDueNow() {
        #expect(EvidenceRibbonCopy.photoLine(.due(daysOverdue: 2)) == "Due now")
    }

    @Test func photoLineUpcomingTomorrow() {
        #expect(EvidenceRibbonCopy.photoLine(.upcoming(daysUntil: 1)) == "Tomorrow")
    }

    @Test func photoLineUpcomingInDays() {
        #expect(EvidenceRibbonCopy.photoLine(.upcoming(daysUntil: 5)) == "In 5 days")
    }

    // MARK: - reviewLine

    @Test func reviewLineNilPhase() {
        #expect(EvidenceRibbonCopy.reviewLine(nil) == "—")
    }

    @Test func reviewLineToday() {
        let phase = EvidencePhase(
            anchor: .record, start: .now, dayNumber: 1, week: 0,
            label: "Building the baseline", nextReviewWeek: 4, nextReviewDate: .now, daysToReview: 0
        )
        #expect(EvidenceRibbonCopy.reviewLine(phase) == "Today")
    }

    @Test func reviewLineInDays() {
        let phase = EvidencePhase(
            anchor: .record, start: .now, dayNumber: 1, week: 0,
            label: "Building the baseline", nextReviewWeek: 4, nextReviewDate: .now, daysToReview: 3
        )
        #expect(EvidenceRibbonCopy.reviewLine(phase) == "In 3 days")
    }
}
