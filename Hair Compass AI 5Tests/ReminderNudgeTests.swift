//
//  ReminderNudgeTests.swift
//  Hair Compass AI 5Tests
//
//  One card, once, at the moment it matters: after the first saved log, while reminders are off.
//

import Testing
@testable import Hair_Compass_AI_5

struct ReminderNudgeTests {
    @Test func showsOnlyAfterALogWhileRemindersAreOffAndNeverTwice() {
        #expect(ReminderNudge.shouldShow(hasLoggedToday: true, eveningReminderOn: false, alreadyShown: false))
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: false, eveningReminderOn: false, alreadyShown: false))
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: true, eveningReminderOn: true, alreadyShown: false))
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: true, eveningReminderOn: false, alreadyShown: true))
    }

    @Test func storageKeyIsStable() {
        #expect(ReminderNudge.shownKey == "reminders.nudgeShown")
    }
}
