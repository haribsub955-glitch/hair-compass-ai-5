//
//  YesterdayCopyTests.swift
//  Hair Compass AI 5Tests
//
//  "Same as yesterday" is a full log made in one tap. It copies every self-reported value and
//  nothing personal, offers itself only when it can be honest (yesterday exists, today doesn't),
//  and finds "yesterday" by calendar day, not by the newest entry.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct YesterdayCopyTests {

    private func entry(daysAgo: Int, calendar: Calendar = .current, now: Date = .now) -> DailyEntry {
        let e = DailyEntry()
        e.date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return e
    }

    @Test func offersOnlyWhenTodayIsEmptyAndYesterdayExists() {
        #expect(YesterdayCopy.canOffer(todayLogged: false, yesterday: entry(daysAgo: 1)))
        #expect(!YesterdayCopy.canOffer(todayLogged: true, yesterday: entry(daysAgo: 1)))
        #expect(!YesterdayCopy.canOffer(todayLogged: false, yesterday: nil))
    }

    @Test func copiesEverySelfReportedValueAndNoNote() {
        let y = DailyEntry()
        y.shedRaw = ShedLevel.elevated.rawValue
        y.flaking = 2; y.erythema = 1; y.itch = 3
        y.sleepQuality = 4; y.stress = 2
        y.cigarettes = 3; y.alcoholDrinks = 1; y.oiliness = 2
        y.washedHair = true
        y.note = "private"
        let t = DailyEntry()
        YesterdayCopy.apply(from: y, to: t)
        #expect(t.shedRaw == ShedLevel.elevated.rawValue)
        #expect(t.flaking == 2 && t.erythema == 1 && t.itch == 3)
        #expect(t.sleepQuality == 4 && t.stress == 2)
        #expect(t.cigarettes == 3 && t.alcoholDrinks == 1 && t.oiliness == 2)
        #expect(t.washedHair == true)
        #expect(t.note.isEmpty, "a note is personal and never copied")
    }

    @Test func yesterdayIsFoundByCalendarDayNotRecency() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 9))!
        let twoDaysAgo = entry(daysAgo: 2, calendar: cal, now: now)
        let yesterday = entry(daysAgo: 1, calendar: cal, now: now)
        // Newest first, as TodayView's query delivers them; today absent.
        #expect(YesterdayCopy.yesterdayEntry(in: [yesterday, twoDaysAgo], now: now, calendar: cal) === yesterday)
        #expect(YesterdayCopy.yesterdayEntry(in: [twoDaysAgo], now: now, calendar: cal) == nil)
        #expect(YesterdayCopy.yesterdayEntry(in: [], now: now, calendar: cal) == nil)
    }
}
