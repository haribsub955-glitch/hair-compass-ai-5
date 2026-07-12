//
//  LabTrendTests.swift
//  Hair Compass AI 5Tests
//
//  HairAnalytics.labImproving(previous:latest:range:) answers "is a repeat draw correcting?" —
//  the honest signal LabsView's grouped cards surface. It must only call a draw improving when
//  the earlier value was out of range AND the new value moved toward that range; an
//  already-in-range draw, a flat repeat, or a worsening repeat must never read as improving.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct LabTrendTests {

    private let ferritinRange = LabTest.ferritin.referenceRange   // 30...300

    @Test func lowDrawMovingUpTowardRangeIsImproving() {
        #expect(HairAnalytics.labImproving(previous: 18, latest: 42, range: ferritinRange))
    }

    @Test func lowDrawReachingIntoRangeIsImproving() {
        #expect(HairAnalytics.labImproving(previous: 18, latest: 35, range: ferritinRange))
    }

    @Test func lowDrawStayingFlatIsNotImproving() {
        #expect(!HairAnalytics.labImproving(previous: 18, latest: 18, range: ferritinRange))
    }

    @Test func lowDrawDroppingFurtherIsNotImproving() {
        #expect(!HairAnalytics.labImproving(previous: 18, latest: 10, range: ferritinRange))
    }

    @Test func highDrawMovingDownTowardRangeIsImproving() {
        let tshRange = LabTest.tsh.referenceRange   // 0.4...4.0
        #expect(HairAnalytics.labImproving(previous: 6.0, latest: 4.5, range: tshRange))
    }

    @Test func highDrawRisingFurtherIsNotImproving() {
        let tshRange = LabTest.tsh.referenceRange
        #expect(!HairAnalytics.labImproving(previous: 6.0, latest: 7.0, range: tshRange))
    }

    @Test func alreadyInRangePreviousDrawIsNeverImprovingRegardlessOfLatest() {
        #expect(!HairAnalytics.labImproving(previous: 80, latest: 90, range: ferritinRange))
        #expect(!HairAnalytics.labImproving(previous: 80, latest: 40, range: ferritinRange))
    }
}
