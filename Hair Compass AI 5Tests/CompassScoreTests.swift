//
//  CompassScoreTests.swift
//  Hair Compass AI 5Tests
//
//  The Compass Rings daily effort score — pure and deterministic, built only from
//  controllable inputs (log/care/lens). Shedding/scalp severity never touch it.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct CompassScoreTests {

    // MARK: - Boundary scores

    @Test func allRingsClosedScoresOneHundred() {
        let score = CompassScore(hasLoggedToday: true, medsDone: 2, medsTotal: 2, hasPhotoThisWeek: true)
        #expect(score.score == 100)
        #expect(score.allClosed)
    }

    @Test func nothingLoggedScoresZero() {
        let score = CompassScore(hasLoggedToday: false, medsDone: 0, medsTotal: 0, hasPhotoThisWeek: false)
        #expect(score.score == 0)
        #expect(!score.allClosed)
    }

    /// No care schedule: Log(50) + Lens(20) is the whole 70-point pie. Log-only closes 50 of
    /// those 70 points → round(50/70 × 100) = 71.
    @Test func logOnlyWithNoScheduleRedistributesCareWeight() {
        let score = CompassScore(hasLoggedToday: true, medsDone: 0, medsTotal: 0, hasPhotoThisWeek: false)
        #expect(score.care == nil)
        #expect(score.score == 71)
    }

    // MARK: - Care availability

    @Test func careIsNilWhenNothingIsScheduledTodayAndFractionalOtherwise() {
        let noSchedule = CompassScore(hasLoggedToday: false, medsDone: 0, medsTotal: 0, hasPhotoThisWeek: false)
        #expect(noSchedule.care == nil)

        let partialSchedule = CompassScore(hasLoggedToday: false, medsDone: 1, medsTotal: 2, hasPhotoThisWeek: false)
        #expect(partialSchedule.care == 0.5)
    }

    @Test func medsDoneOverMedsTotalClampsCareToOne() {
        let score = CompassScore(hasLoggedToday: false, medsDone: 5, medsTotal: 2, hasPhotoThisWeek: false)
        #expect(score.care == 1.0)
    }

    // MARK: - allClosed

    @Test func allClosedIsTrueOnlyWhenEveryAvailableRingIsComplete() {
        // Every ring present and complete.
        let complete = CompassScore(hasLoggedToday: true, medsDone: 1, medsTotal: 1, hasPhotoThisWeek: true)
        #expect(complete.allClosed)

        // Care partially done — not closed.
        let partialCare = CompassScore(hasLoggedToday: true, medsDone: 1, medsTotal: 2, hasPhotoThisWeek: true)
        #expect(!partialCare.allClosed)

        // No care scheduled (excluded from the score) but log + lens both closed — closed.
        let noScheduleClosed = CompassScore(hasLoggedToday: true, medsDone: 0, medsTotal: 0, hasPhotoThisWeek: true)
        #expect(noScheduleClosed.allClosed)

        // Lens still open — not closed even though log is done.
        let lensOpen = CompassScore(hasLoggedToday: true, medsDone: 0, medsTotal: 0, hasPhotoThisWeek: false)
        #expect(!lensOpen.allClosed)
    }
}
