//
//  Hair_Compass_AI_5Tests.swift
//  Hair Compass AI 5Tests
//
//  Tests the evidence-based analytics core (see docs/TrackingSpec.md).
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct Hair_Compass_AI_5Tests {

    // MARK: - Seborrheic-dermatitis 16-point scale (Zhang 2023)

    @Test func scalpTotalMapsFlakingBandOntoValidatedScale() {
        // Flaking band 0..3 → 0/3/6/10; plus erythema + itch (0..3 each), total /16.
        #expect(HairAnalytics.scalpTotal(flaking: 0, erythema: 0, itch: 0) == 0)
        #expect(HairAnalytics.scalpTotal(flaking: 3, erythema: 3, itch: 3) == 16)
        #expect(HairAnalytics.scalpTotal(flaking: 1, erythema: 1, itch: 1) == 5) // 3+1+1
        #expect(HairAnalytics.scalpTotal(flaking: 2, erythema: 0, itch: 1) == 7) // 6+0+1
    }

    @Test func scalpBandsUsePublishedThresholds() {
        #expect(HairAnalytics.scalpBand(total: 0) == .mild)
        #expect(HairAnalytics.scalpBand(total: 5) == .mild)
        #expect(HairAnalytics.scalpBand(total: 6) == .moderate)
        #expect(HairAnalytics.scalpBand(total: 9) == .moderate)
        #expect(HairAnalytics.scalpBand(total: 10) == .severe)
        #expect(HairAnalytics.scalpBand(total: 16) == .severe)
    }

    // MARK: - Labs

    @Test func labFlagsAgainstReferenceRanges() {
        #expect(HairAnalytics.flag(for: 10, test: .ferritin) == .low)   // < 30
        #expect(HairAnalytics.flag(for: 80, test: .ferritin) == .normal)
        #expect(HairAnalytics.flag(for: 20, test: .vitaminD) == .low)   // < 30
        #expect(HairAnalytics.flag(for: 5.0, test: .tsh) == .high)      // > 4.0
    }

    // MARK: - 24-week outcome gate

    @Test func outcomeGateOpensAtTwentyFourWeeks() {
        #expect(HairAnalytics.outcomeReady(weeksElapsed: 23) == false)
        #expect(HairAnalytics.outcomeReady(weeksElapsed: 24) == true)
        #expect(HairAnalytics.outcomeProgress(weeksElapsed: 12) == 0.5)
        #expect(HairAnalytics.outcomeProgress(weeksElapsed: 48) == 1.0) // capped
    }

    @Test func weeksElapsedCountsWholeWeeks() {
        let start = Calendar.current.date(byAdding: .day, value: -21, to: .now)!
        #expect(HairAnalytics.weeksElapsed(since: start) == 3)
    }

    // MARK: - Adherence

    @Test func adherenceIsLoggedOverExpectedInWindow() throws {
        let cal = Calendar.current
        let now = Date.now
        // 2x/day expected over 14 days = 28 expected. Log 14 (one per day) = 50%.
        var dates: [Date] = []
        for d in 0..<14 {
            if let day = cal.date(byAdding: .day, value: -d, to: now) { dates.append(day) }
        }
        let pct = try #require(HairAnalytics.adherence(doseDates: dates, expectedPerDay: 2, windowDays: 14, now: now))
        #expect(abs(pct - 0.5) < 0.001)
    }

    @Test func adherenceIsNilForPeriodicTreatments() {
        #expect(HairAnalytics.adherence(doseDates: [], expectedPerDay: 0) == nil)
    }

    // MARK: - Trends

    @Test func directionDetectsRiseAndFall() {
        #expect(HairAnalytics.direction([1, 1, 1, 5, 5, 5]) > 0)   // rising
        #expect(HairAnalytics.direction([5, 5, 5, 1, 1, 1]) < 0)   // falling
    }

    @Test func rollingAverageSmoothsSeries() {
        let smoothed = HairAnalytics.rollingAverage([0, 10, 0, 10], window: 2)
        #expect(smoothed[0] == 0)
        #expect(smoothed[1] == 5)
        #expect(smoothed[3] == 5)
    }

    // MARK: - Streak

    @Test func loggingStreakCountsConsecutiveDays() {
        let cal = Calendar.current
        let now = Date.now
        let dates = (0..<3).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
        #expect(HairAnalytics.loggingStreak(entryDates: dates, now: now) == 3)
    }

    @Test func loggingStreakBreaksOnGap() {
        let cal = Calendar.current
        let now = Date.now
        let today = now
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: now)!
        #expect(HairAnalytics.loggingStreak(entryDates: [today, threeDaysAgo], now: now) == 1)
    }

    // MARK: - Model bridging

    @Test func dailyEntryComputesScalpBandFromItems() {
        let entry = DailyEntry(flaking: 3, erythema: 3, itch: 3)
        #expect(entry.scalpTotal == 16)
        #expect(entry.scalpBand == .severe)
    }

    @Test func treatmentFallsBackToDefaultSlots() {
        let minox = Treatment(treatmentClass: .minoxidil)
        #expect(minox.slots == ["08:00", "21:00"])
        let prp = Treatment(treatmentClass: .prp)
        #expect(prp.slots.isEmpty)
    }
}
