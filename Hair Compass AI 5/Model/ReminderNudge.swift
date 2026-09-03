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

    static func shouldShow(hasLoggedToday: Bool, eveningReminderOn: Bool, alreadyShown: Bool) -> Bool {
        hasLoggedToday && !eveningReminderOn && !alreadyShown
    }
}
