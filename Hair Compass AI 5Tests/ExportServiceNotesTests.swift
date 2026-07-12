//
//  ExportServiceNotesTests.swift
//  Hair Compass AI 5Tests
//
//  Round 5: daily notes were write-only — stored on every DailyEntry but never surfaced
//  anywhere except reopening that exact day's log sheet. `clinicianSummary` now lists dated
//  notes from the last 90 days, newest first, capped, and only the non-empty ones.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct ExportServiceNotesTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    @Test func summaryListsRecentNotesNewestFirst() {
        let now = Date.now
        let older = DailyEntry(date: day(-10, from: now), shed: .normal)
        older.note = "Switched shampoo"
        let newer = DailyEntry(date: day(-1, from: now), shed: .normal)
        newer.note = "Started a new supplement"
        let blank = DailyEntry(date: day(-2, from: now), shed: .normal)
        blank.note = "   " // whitespace-only — must not appear

        let summary = ExportService.clinicianSummary(
            profile: nil, entries: [older, newer, blank], treatments: [], doses: [],
            labs: [], triggers: [], progressCheckIns: [], now: now
        )

        #expect(summary.contains("NOTES (last 90 days)"))
        let newerIndex = summary.range(of: "Started a new supplement")!.lowerBound
        let olderIndex = summary.range(of: "Switched shampoo")!.lowerBound
        #expect(newerIndex < olderIndex)
        #expect(!summary.contains("•  \n") ) // no blank-note bullet line
    }

    @Test func summaryOmitsNotesOlderThan90Days() {
        let now = Date.now
        let stale = DailyEntry(date: day(-120, from: now), shed: .normal)
        stale.note = "Ancient note"

        let summary = ExportService.clinicianSummary(
            profile: nil, entries: [stale], treatments: [], doses: [],
            labs: [], triggers: [], progressCheckIns: [], now: now
        )

        #expect(!summary.contains("NOTES (last 90 days)"))
        #expect(!summary.contains("Ancient note"))
    }

    @Test func summaryOmitsNotesSectionWhenNoneAreLogged() {
        let now = Date.now
        let plain = DailyEntry(date: day(-1, from: now), shed: .normal)

        let summary = ExportService.clinicianSummary(
            profile: nil, entries: [plain], treatments: [], doses: [],
            labs: [], triggers: [], progressCheckIns: [], now: now
        )

        #expect(!summary.contains("NOTES (last 90 days)"))
    }
}
