//
//  BodySignalsTests.swift
//  Hair Compass AI 5Tests
//
//  Pure math behind the Body-signals dashboard: windowed series extraction (nil-skipping),
//  adjacent-window deltas, the desirability tinting rule, and the rapid-loss chip condition.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct BodySignalsTests {

    private let calendar = Calendar.current

    private func daysAgo(_ n: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: -n, to: now)!
    }

    // MARK: - Windowed series extraction

    @Test func windowedSeriesSkipsNilsAndOutOfWindowSamples() {
        let now = Date.now
        let samples: [(date: Date, value: Double?)] = [
            (daysAgo(100, from: now), 9.9),   // outside the 30-day window
            (daysAgo(5, from: now), 7.5),     // out of order on purpose — must come back sorted
            (daysAgo(20, from: now), 7.0),
            (daysAgo(10, from: now), nil),    // "not available" is skipped, never a zero
            (daysAgo(1, from: now), 6.5),
        ]
        let series = BodySignalsMath.windowedSeries(samples, windowDays: 30, now: now)
        #expect(series.map(\.value) == [7.0, 7.5, 6.5])
        #expect(series.first?.date == daysAgo(20, from: now))
    }

    // MARK: - Delta vs the previous same-length window

    @Test func deltaComparesAdjacentSameLengthWindows() {
        let now = Date.now
        // Previous 30-day window averages 7.0; the current window averages 7.4.
        let samples: [(date: Date, value: Double?)] = [
            (daysAgo(55, from: now), 6.8),
            (daysAgo(50, from: now), 7.0),
            (daysAgo(40, from: now), 7.2),
            (daysAgo(45, from: now), nil),    // nils never drag a mean toward zero
            (daysAgo(25, from: now), 7.3),
            (daysAgo(15, from: now), 7.4),
            (daysAgo(5, from: now), 7.5),
        ]
        let delta = BodySignalsMath.delta(samples, windowDays: 30, now: now)
        #expect(delta != nil)
        #expect(abs(delta! - 0.4) < 0.0001)

        // No previous-window readings → no delta, not a fake zero.
        let currentOnly: [(date: Date, value: Double?)] = [
            (daysAgo(15, from: now), 7.3),
            (daysAgo(5, from: now), 7.5),
        ]
        #expect(BodySignalsMath.delta(currentOnly, windowDays: 30, now: now) == nil)
    }

    // MARK: - Desirability tinting rule

    @Test func desirabilityToneFollowsEachSignalsDirection() {
        // More sleep / HRV / protein is favorable; less is unfavorable.
        #expect(BodySignalsMath.tone(for: .sleep, delta: 0.4) == .favorable)
        #expect(BodySignalsMath.tone(for: .hrv, delta: -3) == .unfavorable)
        #expect(BodySignalsMath.tone(for: .protein, delta: 12) == .favorable)
        // A rising resting HR is the unfavorable direction.
        #expect(BodySignalsMath.tone(for: .restingHR, delta: 2) == .unfavorable)
        #expect(BodySignalsMath.tone(for: .restingHR, delta: -2) == .favorable)
        // Weight stays neutral — no diet-culture judgment — unless rapid loss fires.
        #expect(BodySignalsMath.tone(for: .weight, delta: -0.8) == .neutral)
        #expect(BodySignalsMath.tone(for: .weight, delta: -0.8, rapidLossActive: true) == .unfavorable)
        // Sub-display-precision wiggle reads as no change.
        #expect(BodySignalsMath.tone(for: .sleep, delta: 0.01) == .neutral)
    }

    // MARK: - Rapid-loss chip condition

    @Test func rapidLossChipFiresOnlyPastTheFivePercentThreshold() {
        let now = Date.now
        let rapid: [(date: Date, massKg: Double)] = [
            (daysAgo(80, from: now), 80.0),
            (daysAgo(40, from: now), 77.0),
            (daysAgo(2, from: now), 74.0),    // −7.5% from the window peak → rounds to 8
        ]
        #expect(BodySignalsMath.rapidLossChip(massSamples: rapid, now: now) == "−8% in 90d — TE watch")

        let gentle: [(date: Date, massKg: Double)] = [
            (daysAgo(80, from: now), 80.0),
            (daysAgo(2, from: now), 78.5),    // −1.9% — under the 5% threshold
        ]
        #expect(BodySignalsMath.rapidLossChip(massSamples: gentle, now: now) == nil)
    }
}
