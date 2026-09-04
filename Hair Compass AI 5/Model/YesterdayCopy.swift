//
//  YesterdayCopy.swift
//  Hair Compass AI 5
//
//  One tap on a quiet day: today's log becomes a copy of yesterday's ratings. Pure rules here —
//  what may be offered, what is copied, which entry counts as yesterday — so TodayView only
//  performs the write. Only the seven self-reported ratings copy (shedRaw, flaking, erythema,
//  itch, sleepQuality, stress, oiliness); the three event fields (cigarettes, alcoholDrinks,
//  washedHair) never do, because they are counts of things that may not have happened today —
//  and washedHair also feeds the clinician export, the research payload, and Wren's grounding
//  facts.
//

import Foundation

enum YesterdayCopy {
    /// Offer the chip only when it is honest: nothing logged today, and a real yesterday to copy.
    static func canOffer(todayLogged: Bool, yesterday: DailyEntry?) -> Bool {
        !todayLogged && yesterday != nil
    }

    /// The seven self-reported ratings; never the three event fields (cigarettes, alcoholDrinks,
    /// washedHair — left at today's own defaults, since they're counts of things that may not
    /// have happened today and washedHair also feeds the clinician export, the research payload,
    /// and Wren's grounding facts), never the note, never the date.
    static func apply(from yesterday: DailyEntry, to today: DailyEntry) {
        today.shedRaw = yesterday.shedRaw
        today.flaking = yesterday.flaking
        today.erythema = yesterday.erythema
        today.itch = yesterday.itch
        today.sleepQuality = yesterday.sleepQuality
        today.stress = yesterday.stress
        today.oiliness = yesterday.oiliness
        let copyable: Set<DailySignal> = [
            .shedding, .flaking, .erythema, .itch, .sleepQuality, .stress, .oiliness
        ]
        today.recordedSignals = yesterday.recordedSignals.intersection(copyable)
    }

    /// The entry dated on the calendar day before `now`, whatever order the list arrives in.
    static func yesterdayEntry(in entries: [DailyEntry], now: Date = .now, calendar: Calendar = .current) -> DailyEntry? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        return entries.first { calendar.isDate($0.date, inSameDayAs: yesterday) }
    }
}
