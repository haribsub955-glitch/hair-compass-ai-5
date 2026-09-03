//
//  MotionSpecTests.swift
//  Hair Compass AI 5Tests
//
//  The owner's motion budgets, pinned: durations sit inside the range the amendment specifies,
//  and Close the Day's total never drifts past the 1.6 s ceiling.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct MotionSpecTests {

    @Test func horizonDrawWithinBudget() {
        #expect((0.9...1.2).contains(MotionSpec.horizon.draw))
    }

    @Test func noteRiseIsSixPoints() {
        #expect(MotionSpec.note.rise == 6)
    }

    @Test func noteActionDelayIsEightyMilliseconds() {
        #expect(MotionSpec.note.actionDelay == 0.08)
    }

    @Test func horizonMarkerAndReviewDotFadesWithinBudget() {
        #expect((0.1...0.4).contains(MotionSpec.horizon.markerFade))
        #expect((0.1...0.4).contains(MotionSpec.horizon.reviewDotFade))
    }

    @Test func closeTheDayTotalWithinBudget() {
        #expect((1.2...1.6).contains(MotionSpec.closeTheDay.total))
    }

    @Test func completionWashUnderOneSecond() {
        #expect(MotionSpec.completion.washDuration < 1)
    }

    @Test func evidencePathIsAQuietOneShot() {
        #expect((0.7...1.2).contains(MotionSpec.evidencePath.draw))
        #expect(MotionSpec.evidencePath.nodeStep < 0.1)
        #expect(MotionSpec.evidencePath.total <= 1.2)
    }
}
