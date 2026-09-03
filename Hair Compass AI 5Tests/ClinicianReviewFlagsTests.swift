//
//  ClinicianReviewFlagsTests.swift
//  Hair Compass AI 5Tests
//
//  Consolidated "worth a clinician review" red-flag surface (Model/ClinicianReviewFlags.swift).
//  Every rule mirrors a piece of guidance the app already teaches elsewhere (the scalp-pain
//  check-in flag, the recommender's 6-month telogen-effluvium note, Care's severity-3 side-effect
//  banner) — this only tests that the deterministic detection is conservative and correct, never
//  that it diagnoses anything.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct ClinicianReviewFlagsTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
    }

    private func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: now)!
    }

    // MARK: - No data, no flags

    @Test func emptyInputsProduceNoFlags() {
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: [], triggers: [], sideEffects: [], now: now, calendar: calendar
        )
        #expect(flags.isEmpty)
    }

    // MARK: - Scalp pain (ProgressCheckIn.scalpPain)

    @Test func scalpPainFromTheLatestReportingCheckInFires() {
        let checkIns = [
            ProgressCheckIn(date: daysAgo(60), scalpPain: false),
            ProgressCheckIn(date: daysAgo(30), scalpPain: true, scalpPainNote: "burning at the crown"),
        ]
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: checkIns, entries: [], triggers: [], sideEffects: [], now: now, calendar: calendar
        )
        let flag = flags.first { $0.id == "scalpPain" }
        #expect(flag != nil)
        #expect(flag?.detail.contains("burning at the crown") == true)
        #expect(flag?.detail.localizedCaseInsensitiveContains("diagnos") == false)
    }

    @Test func noScalpPainMeansNoScalpPainFlag() {
        let checkIns = [ProgressCheckIn(date: daysAgo(10), scalpPain: false)]
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: checkIns, entries: [], triggers: [], sideEffects: [], now: now, calendar: calendar
        )
        #expect(!flags.contains { $0.id == "scalpPain" })
    }

    // MARK: - Heavy shedding, most of the last two weeks

    @Test func sevenOfFourteenHeavyDaysMeetsTheThreshold() {
        var entries: [DailyEntry] = (0..<7).map { DailyEntry(date: daysAgo($0), shed: .heavy) }
        entries += (7..<14).map { DailyEntry(date: daysAgo($0), shed: .normal) }
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: entries, triggers: [], sideEffects: [], now: now, calendar: calendar
        )
        #expect(flags.contains { $0.id == "heavyShed" })
    }

    @Test func sixOfFourteenHeavyDaysStaysUnderTheThreshold() {
        var entries: [DailyEntry] = (0..<6).map { DailyEntry(date: daysAgo($0), shed: .heavy) }
        entries += (6..<14).map { DailyEntry(date: daysAgo($0), shed: .normal) }
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: entries, triggers: [], sideEffects: [], now: now, calendar: calendar
        )
        #expect(!flags.contains { $0.id == "heavyShed" })
    }

    @Test func heavyDaysOutsideTheFourteenDayWindowDoNotCount() {
        // 7 heavy days, but all more than two weeks ago.
        let entries: [DailyEntry] = (20..<27).map { DailyEntry(date: daysAgo($0), shed: .heavy) }
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: entries, triggers: [], sideEffects: [], now: now, calendar: calendar
        )
        #expect(!flags.contains { $0.id == "heavyShed" })
    }

    // MARK: - A stale (>6 month) trigger while shedding is still rising

    @Test func staleTriggerWithRisingShedFires() {
        let trigger = TriggerEvent(type: .illness, date: daysAgo(200)) // ~28.5 weeks
        // A clear rising trend inside the last 60 days: minimal early, heavy late.
        var entries: [DailyEntry] = (30..<45).map { DailyEntry(date: daysAgo($0), shed: .minimal) }
        entries += (0..<15).map { DailyEntry(date: daysAgo($0), shed: .heavy) }
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: entries, triggers: [trigger], sideEffects: [], now: now, calendar: calendar
        )
        let flag = flags.first { $0.id == "staleTrigger" }
        #expect(flag != nil)
        #expect(flag?.detail.contains("Illness") == true)
    }

    @Test func recentTriggerUnderSixMonthsNeverFiresEvenWithRisingShed() {
        let trigger = TriggerEvent(type: .illness, date: daysAgo(56)) // 8 weeks — well inside 6 months
        var entries: [DailyEntry] = (30..<45).map { DailyEntry(date: daysAgo($0), shed: .minimal) }
        entries += (0..<15).map { DailyEntry(date: daysAgo($0), shed: .heavy) }
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: entries, triggers: [trigger], sideEffects: [], now: now, calendar: calendar
        )
        #expect(!flags.contains { $0.id == "staleTrigger" })
    }

    @Test func staleTriggerWithFlatSheddingDoesNotFire() {
        let trigger = TriggerEvent(type: .illness, date: daysAgo(200))
        let entries: [DailyEntry] = (0..<30).map { DailyEntry(date: daysAgo($0), shed: .normal) }
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: entries, triggers: [trigger], sideEffects: [], now: now, calendar: calendar
        )
        #expect(!flags.contains { $0.id == "staleTrigger" })
    }

    // MARK: - Severity-3 side effect (reuses HairAnalytics.hasRecentSevereSideEffect)

    @Test func severeSideEffectInWindowFires() {
        let log = SideEffectLog(type: .scalpIrritation, severity: 3, date: daysAgo(5))
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: [], triggers: [], sideEffects: [log], now: now, calendar: calendar
        )
        #expect(flags.contains { $0.id == "severeSideEffect" })
    }

    @Test func moderateSideEffectNeverFires() {
        let log = SideEffectLog(type: .scalpIrritation, severity: 2, date: daysAgo(2))
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: [], triggers: [], sideEffects: [log], now: now, calendar: calendar
        )
        #expect(!flags.contains { $0.id == "severeSideEffect" })
    }

    @Test func severeSideEffectOutsideTheWindowDoesNotFire() {
        let log = SideEffectLog(type: .scalpIrritation, severity: 3, date: daysAgo(30))
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: [], entries: [], triggers: [], sideEffects: [log], now: now, calendar: calendar
        )
        #expect(!flags.contains { $0.id == "severeSideEffect" })
    }

    // MARK: - Multiple flags combine, never a diagnosis

    @Test func multipleFiredFlagsAllAppearAndNeverNameACondition() {
        let checkIns = [ProgressCheckIn(date: daysAgo(10), scalpPain: true)]
        let sideEffects = [SideEffectLog(type: .headache, severity: 3, date: daysAgo(1))]
        var entries: [DailyEntry] = (0..<7).map { DailyEntry(date: daysAgo($0), shed: .heavy) }
        entries += (7..<14).map { DailyEntry(date: daysAgo($0), shed: .normal) }

        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: checkIns, entries: entries, triggers: [], sideEffects: sideEffects,
            now: now, calendar: calendar
        )

        #expect(flags.count == 3)
        #expect(Set(flags.map(\.id)) == ["scalpPain", "severeSideEffect", "heavyShed"])
        for flag in flags {
            #expect(flag.detail.localizedCaseInsensitiveContains("diagnos") == false)
        }
    }

    // MARK: - forToday (recency)

    @Test func forTodayDropsAYearOldScalpPain() {
        let checkIns = [ProgressCheckIn(date: daysAgo(400), scalpPain: true)]
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: checkIns, entries: [], triggers: [], sideEffects: [], now: now, calendar: calendar
        )
        #expect(flags.contains { $0.id == "scalpPain" })
        let today = ClinicianReviewFlags.forToday(flags, now: now, calendar: calendar)
        #expect(today.isEmpty)
    }

    @Test func forTodayPrefersTheNewestFlag() {
        let checkIns = [ProgressCheckIn(date: daysAgo(20), scalpPain: true)]
        let sideEffects = [SideEffectLog(type: .headache, severity: 3, date: daysAgo(0))]
        let flags = ClinicianReviewFlags.evaluate(
            progressCheckIns: checkIns, entries: [], triggers: [], sideEffects: sideEffects, now: now, calendar: calendar
        )
        let today = ClinicianReviewFlags.forToday(flags, now: now, calendar: calendar)
        #expect(today.first?.id == "severeSideEffect")
    }
}
