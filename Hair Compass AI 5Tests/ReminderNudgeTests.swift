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
        #expect(ReminderNudge.shouldShow(hasLoggedToday: true, isDayOneSeed: false, eveningReminderOn: false, alreadyShown: false))
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: false, isDayOneSeed: false, eveningReminderOn: false, alreadyShown: false))
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: true, isDayOneSeed: false, eveningReminderOn: true, alreadyShown: false))
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: true, isDayOneSeed: false, eveningReminderOn: false, alreadyShown: true))
    }

    /// Onboarding seeds today's entry on finish, so `hasLoggedToday` is true on the very first
    /// Today screen — a log the person never tapped. The nudge must not count that as "the first
    /// saved log".
    @Test func seededDayOneDoesNotCount() {
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: true, isDayOneSeed: true, eveningReminderOn: false, alreadyShown: false))
    }

    @Test func storageKeyIsStable() {
        #expect(ReminderNudge.shownKey == "reminders.nudgeShown")
    }
}
