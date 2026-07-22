//
//  NotificationAuthorizationTests.swift
//  Hair Compass AI 5Tests
//
//  `NotificationService.authorization` starts `.notDetermined` on every cold launch and used to
//  only be re-derived from `CareView`'s `.task` — so `RootView`'s launch/foreground replan of the
//  evening check-in reminder (the surface that exists specifically to keep the 3-day horizon
//  alive for a user who lives on Today and never opens Plan) removed the three pending
//  `eveningCheckIn.*` requests and then failed the authorization guard, scheduling nothing back
//  in. `canSchedule` is the pure guard every `plan*`/`performReschedule` call now runs — this
//  exercises it directly for the exact "granted in a prior session, stale on this cold launch"
//  scenario (see the 2026-07-21 audit).
//

import Foundation
import Testing
import UserNotifications
@testable import Hair_Compass_AI_5

struct NotificationAuthorizationTests {

    @Test func staleNotDeterminedBlocksSchedulingEvenWhenEnabled() {
        // The exact cold-launch bug: reminders are ON (the user granted permission and turned
        // the toggle on in a prior session), but `authorization` hasn't been refreshed yet on
        // this launch and still reads its `.notDetermined` initializer value.
        #expect(NotificationService.canSchedule(enabled: true, authorization: .notDetermined) == false)
    }

    @Test func refreshedAuthorizedOrProvisionalAllowsSchedulingAfterRelaunch() {
        // Once `refreshAuthorization()` re-derives the real, previously granted state, the same
        // "reminders enabled" flag now schedules again — the fix.
        #expect(NotificationService.canSchedule(enabled: true, authorization: .authorized))
        #expect(NotificationService.canSchedule(enabled: true, authorization: .provisional))
    }

    @Test func deniedNeverSchedulesRegardlessOfTheEnabledFlag() {
        #expect(NotificationService.canSchedule(enabled: true, authorization: .denied) == false)
    }

    @Test func disabledNeverSchedulesRegardlessOfAuthorization() {
        // The reminder's own toggle still wins even once permission is genuinely granted.
        #expect(NotificationService.canSchedule(enabled: false, authorization: .authorized) == false)
        #expect(NotificationService.canSchedule(enabled: false, authorization: .provisional) == false)
    }
}
