//
//  TrajectorySummaryTests.swift
//  Hair Compass AI 5Tests
//
//  The wash-day confound: shed hair reads far heavier on wash days than dry ones, so a week
//  with more wash days than the prior week can look like "shedding rose" when nothing changed.
//  TrajectorySummary should hedge that specific claim — and only that claim — with the wash-day
//  counts, never silently fold them into the average.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct TrajectorySummaryTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    @Test func hedgesWhenWashDayCountsDifferAndSheddingRose() {
        let now = Date.now
        var entries: [DailyEntry] = []
        // Previous week (days -13...-7): normal shedding, 1 wash day.
        for offset in -13...(-7) {
            let e = DailyEntry(date: day(offset, from: now), shed: .normal)
            e.washedHair = offset == -13
            entries.append(e)
        }
        // Current week (days -6...0): heavy shedding, 3 wash days.
        for offset in -6...0 {
            let e = DailyEntry(date: day(offset, from: now), shed: .heavy)
            e.washedHair = [-6, -4, -2].contains(offset)
            entries.append(e)
        }

        let summary = TrajectorySummary(entries: entries, now: now, calendar: calendar)
        #expect(summary.headline == "Shedding has been higher this week")
        #expect(summary.currentWashDays == 3)
        #expect(summary.previousWashDays == 1)
        let hedge = try! #require(summary.washDayHedge)
        #expect(hedge.contains("3 wash days"))
        #expect(hedge.contains("1 last week"))
        #expect(summary.detail.contains(hedge))
    }

    @Test func noHedgeWhenWashDayCountsMatch() {
        let now = Date.now
        var entries: [DailyEntry] = []
        for offset in -13...(-7) {
            let e = DailyEntry(date: day(offset, from: now), shed: .normal)
            e.washedHair = offset == -13
            entries.append(e)
        }
        for offset in -6...0 {
            let e = DailyEntry(date: day(offset, from: now), shed: .heavy)
            e.washedHair = offset == -6   // same count (1) as the previous week
            entries.append(e)
        }

        let summary = TrajectorySummary(entries: entries, now: now, calendar: calendar)
        #expect(summary.currentWashDays == 1)
        #expect(summary.previousWashDays == 1)
        #expect(summary.washDayHedge == nil)
        #expect(!summary.detail.contains("wash day"))
    }

    @Test func noHedgeWhenSheddingIsSteadyEvenIfWashDaysDiffer() {
        // The hedge only qualifies an actual delta claim — it never appears for a "steady" week,
        // since there's no false-alarm claim to caveat.
        let now = Date.now
        var entries: [DailyEntry] = []
        for offset in -13...0 {
            let e = DailyEntry(date: day(offset, from: now), shed: .normal)
            e.washedHair = offset >= -6 ? (offset % 2 == 0) : (offset == -13)
            entries.append(e)
        }

        let summary = TrajectorySummary(entries: entries, now: now, calendar: calendar)
        #expect(summary.headline == "Shedding has been steady this week")
        #expect(summary.washDayHedge == nil)
    }

    @Test func noHedgeWithThinData() {
        // Fewer than 2 logs in either window: the "forming baseline" language applies, not a
        // delta claim, so no wash-day caveat is attached.
        let now = Date.now
        let entries = [DailyEntry(date: now, shed: .heavy)]
        let summary = TrajectorySummary(entries: entries, now: now, calendar: calendar)
        #expect(summary.washDayHedge == nil)
        #expect(!summary.detail.contains("wash day"))
    }

    @Test func heroStatShowsSignedDeltaWhenBothWindowsAreComparable() {
        // Round-5 fix: the headline number must be the same quantity the body sentence
        // describes (a band *change*), never a plain average captioned as if it were the delta.
        let now = Date.now
        var entries: [DailyEntry] = []
        for offset in -13...(-7) {
            entries.append(DailyEntry(date: day(offset, from: now), shed: .normal))
        }
        for offset in -6...0 {
            entries.append(DailyEntry(date: day(offset, from: now), shed: .heavy))
        }

        let summary = TrajectorySummary(entries: entries, now: now, calendar: calendar)
        let stat = try! #require(summary.heroStat)
        #expect(stat.isDelta)
        #expect(stat.caption == "BANDS VS LAST WK")
        #expect(stat.value.hasPrefix("+"))
    }

    @Test func heroStatFallsBackToAverageWhileBaselineIsForming() {
        let now = Date.now
        let entries = [DailyEntry(date: now, shed: .heavy)]
        let summary = TrajectorySummary(entries: entries, now: now, calendar: calendar)
        let stat = try! #require(summary.heroStat)
        #expect(!stat.isDelta)
        #expect(stat.caption == "7D AVG")
    }

    @Test func confidenceLabelGivesActionableCountInsteadOfJargon() {
        let now = Date.now
        var entries: [DailyEntry] = []
        for offset in -2...0 {
            entries.append(DailyEntry(date: day(offset, from: now), shed: .normal))
        }
        let summary = TrajectorySummary(entries: entries, now: now, calendar: calendar)
        #expect(summary.currentCount == 3)
        #expect(summary.confidenceLabel == "Log 2 more days to firm this up")
    }
}
