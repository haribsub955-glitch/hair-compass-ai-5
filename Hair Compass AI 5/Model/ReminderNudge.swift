//
//  ReminderNudge.swift
//  Hair Compass AI 5
//
//  Reminders default to off, and a tracking app lives or dies in its first week. This is the
//  one moment the app asks: right after the first saved log, once, with a real "not now".
//

import Foundation

enum ReminderNudge {
    static let shownKey = "reminders.nudgeShown"

    /// `isDayOneSeed` excludes onboarding's day-one seeded entry from counting as "the first
    /// saved log" — that entry was never tapped by the person, so the nudge waits for a real one.
    static func shouldShow(hasLoggedToday: Bool, isDayOneSeed: Bool, eveningReminderOn: Bool, alreadyShown: Bool) -> Bool {
        hasLoggedToday && !isDayOneSeed && !eveningReminderOn && !alreadyShown
    }
}
