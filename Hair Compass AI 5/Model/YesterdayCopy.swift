//
//  YesterdayCopy.swift
//  Hair Compass AI 5
//
//  One tap on a quiet day: today's log becomes a copy of yesterday's self-reported values.
//  Pure rules here — what may be offered, what is copied, which entry counts as yesterday — so
//  TodayView only performs the write.
//

import Foundation

enum YesterdayCopy {
    /// Offer the chip only when it is honest: nothing logged today, and a real yesterday to copy.
    static func canOffer(todayLogged: Bool, yesterday: DailyEntry?) -> Bool {
        !todayLogged && yesterday != nil
    }

    /// Every self-reported value; never the note, never the date.
    static func apply(from yesterday: DailyEntry, to today: DailyEntry) {
        today.shedRaw = yesterday.shedRaw
        today.flaking = yesterday.flaking
        today.erythema = yesterday.erythema
        today.itch = yesterday.itch
        today.sleepQuality = yesterday.sleepQuality
        today.stress = yesterday.stress
        today.cigarettes = yesterday.cigarettes
        today.alcoholDrinks = yesterday.alcoholDrinks
        today.oiliness = yesterday.oiliness
        today.washedHair = yesterday.washedHair
    }

    /// The entry dated on the calendar day before `now`, whatever order the list arrives in.
    static func yesterdayEntry(in entries: [DailyEntry], now: Date = .now, calendar: Calendar = .current) -> DailyEntry? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        return entries.first { calendar.isDate($0.date, inSameDayAs: yesterday) }
    }
}
