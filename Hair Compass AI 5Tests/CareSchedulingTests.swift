//
//  CareSchedulingTests.swift
//  Hair Compass AI 5Tests
//
//  Day-of-week scheduling for care products (Model/Models.swift: Treatment.scheduledWeekdays /
//  isDueToday). A shampoo set to Mon/Thu only joins the day's routine on those days; medications
//  (empty schedule) run every day.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct CareSchedulingTests {

    private let cal = Calendar.current

    @Test func emptyScheduleIsAlwaysDue() {
        let minox = Treatment(name: "Minoxidil", treatmentClass: .minoxidil)
        for weekday in 1...7 {
            #expect(minox.isDueToday(now: dateWithWeekday(weekday), calendar: cal))
        }
    }

    @Test func aScheduledCareProductIsDueOnlyOnItsDays() {
        // Ketoconazole shampoo scheduled Monday (2) and Thursday (5).
        let shampoo = Treatment(name: "Ketoconazole", treatmentClass: .shampoo, scheduledWeekdays: [2, 5])
        #expect(shampoo.isDueToday(now: dateWithWeekday(2), calendar: cal))    // Monday — due
        #expect(shampoo.isDueToday(now: dateWithWeekday(5), calendar: cal))    // Thursday — due
        #expect(!shampoo.isDueToday(now: dateWithWeekday(3), calendar: cal))   // Tuesday — not
        #expect(!shampoo.isDueToday(now: dateWithWeekday(1), calendar: cal))   // Sunday — not
    }

    @Test func weekdaysRoundTripThroughTheStoredRawString() {
        let oil = Treatment(treatmentClass: .oil, scheduledWeekdays: [1, 4, 7])
        #expect(oil.scheduledWeekdays == [1, 4, 7])
        #expect(oil.scheduledWeekdaysRaw == "1,4,7")     // sorted, comma-joined
        oil.scheduledWeekdays = [3]                       // mutate via the computed setter
        #expect(oil.scheduledWeekdaysRaw == "3")
        oil.scheduledWeekdays = []
        #expect(oil.scheduledWeekdaysRaw.isEmpty)
        #expect(oil.isDueToday(now: dateWithWeekday(6), calendar: cal))   // empty → every day
    }

    @Test func treatmentTimesEncodeInClockOrder() {
        let morning = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 8))!
        let evening = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 21))!
        #expect(TreatmentSchedule.encode([evening, morning], calendar: cal) == "08:00,21:00")
    }

    /// A date whose `Calendar.weekday` component equals `weekday` (1=Sun…7=Sat). 2026-07-12 is a
    /// Sunday (weekday 1); adding `weekday-1` days lands on the target weekday.
    private func dateWithWeekday(_ weekday: Int) -> Date {
        let sunday = cal.date(from: DateComponents(year: 2026, month: 7, day: 12))!
        return cal.date(byAdding: .day, value: weekday - 1, to: sunday)!
    }
}
