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

    @Test func treatmentSummaryUsesPlanConsistencyNumbers() {
        var fixed = Calendar(identifier: .gregorian)
        fixed.timeZone = TimeZone(identifier: "Asia/Muscat")!
        let now = fixed.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))!
        let start = fixed.date(byAdding: .day, value: -1, to: fixed.startOfDay(for: now))!
        let treatment = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                                  scheduleTimes: "08:00", startDate: start, isActive: true)
        let yesterday = fixed.date(bySettingHour: 8, minute: 0, second: 0, of: start)!
        let today = fixed.date(bySettingHour: 8, minute: 0, second: 0, of: now)!
        let doses = [
            TreatmentDose(treatment: treatment, loggedAt: yesterday, slot: "08:00"),
            TreatmentDose(treatment: treatment, loggedAt: today, slot: "08:00")
        ]

        let summary = ExportService.clinicianSummary(
            profile: nil, entries: [], treatments: [treatment], doses: doses,
            labs: [], triggers: [], progressCheckIns: [], now: now, calendar: fixed
        )

        #expect(summary.contains("30-day consistency 100% of due actions (2 completed of 2 due; 2 planned through today)"))
        #expect(summary.contains("this week 2 completed of 2 due; 2 planned through today"))
        #expect(!summary.contains("% adherence"))
    }

    @Test func treatmentSummaryDoesNotGradeAnOpenOnlyWindow() {
        var fixed = Calendar(identifier: .gregorian)
        fixed.timeZone = TimeZone(identifier: "Asia/Muscat")!
        let now = fixed.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))!
        let treatment = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                  scheduleTimes: "21:00", startDate: fixed.startOfDay(for: now), isActive: true)

        let summary = ExportService.clinicianSummary(
            profile: nil, entries: [], treatments: [treatment], doses: [],
            labs: [], triggers: [], progressCheckIns: [], now: now, calendar: fixed
        )

        #expect(summary.contains("30-day consistency: not enough due actions yet (0 completed; 1 planned through today)"))
        #expect(!summary.contains("0%"))
    }
}
