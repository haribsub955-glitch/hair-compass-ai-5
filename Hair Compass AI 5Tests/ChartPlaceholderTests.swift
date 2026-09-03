//
//  ChartPlaceholderTests.swift
//  Hair Compass AI 5Tests
//
//  The one line every "not yet" chart shows must say the section's own rule, honestly and in
//  the same words everywhere: "Opens after N <unit>" and "k of N".
//

import Testing
@testable import Hair_Compass_AI_5

struct ChartPlaceholderTests {

    @Test func dailyLogsCopy() {
        let c = ChartPlaceholderCopy.label(required: 2, have: 1, unit: .dailyLogs)
        #expect(c.primary == "Opens after 2 daily logs")
        #expect(c.progress == "1 of 2")
    }

    @Test func daysCopy() {
        let c = ChartPlaceholderCopy.label(required: 7, have: 2, unit: .days)
        #expect(c.primary == "Opens after 7 days")
        #expect(c.progress == "2 of 7")
    }

    @Test func pairedDaysCopy() {
        let c = ChartPlaceholderCopy.label(required: 8, have: 0, unit: .pairedDays)
        #expect(c.primary == "Opens after 8 paired days")
        #expect(c.progress == "0 of 8")
    }

    @Test func readingsCopy() {
        let c = ChartPlaceholderCopy.label(required: 2, have: 1, unit: .readings)
        #expect(c.primary == "Opens after 2 readings")
        #expect(c.progress == "1 of 2")
    }

    /// Progress can never read "3 of 2" — a site that passes more than it needs is clamped,
    /// and a negative count is treated as zero.
    @Test func progressIsClamped() {
        #expect(ChartPlaceholderCopy.label(required: 2, have: 5, unit: .dailyLogs).progress == "2 of 2")
        #expect(ChartPlaceholderCopy.label(required: 2, have: -1, unit: .dailyLogs).progress == "0 of 2")
    }

    /// Not used by any site today, but the function must never print "1 daily logs".
    @Test func singularUnits() {
        #expect(ChartPlaceholderCopy.label(required: 1, have: 0, unit: .dailyLogs).primary == "Opens after 1 daily log")
        #expect(ChartPlaceholderCopy.label(required: 1, have: 0, unit: .days).primary == "Opens after 1 day")
        #expect(ChartPlaceholderCopy.label(required: 1, have: 0, unit: .pairedDays).primary == "Opens after 1 paired day")
        #expect(ChartPlaceholderCopy.label(required: 1, have: 0, unit: .readings).primary == "Opens after 1 reading")
    }
}
