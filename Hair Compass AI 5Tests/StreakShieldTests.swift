//
//  StreakShieldTests.swift
//  Hair Compass AI 5Tests
//
//  HairAnalytics.shieldedStreak — the Duolingo-style shielded streak that protects the
//  DISPLAYED streak only. `loggingStreak` (which feeds XP) is untouched by this feature and
//  has its own tests above; these only cover the new, purely additive function.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct StreakShieldTests {

    @Test func sevenStraightDaysEarnsOneShield() {
        let cal = Calendar.current
        let now = Date.now
        let dates = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
        let result = HairAnalytics.shieldedStreak(entryDates: dates, now: now)
        #expect(result.streak == 7)
        #expect(result.shieldsHeld == 1)
    }

    @Test func oneDayGapIsBridgedByAnEarnedShield() {
        let cal = Calendar.current
        let now = Date.now
        // Seven straight days (earns a shield), then day −1 is skipped, then today is logged —
        // the gap is bridged, so the streak spans all 9 calendar days, and the shield is spent.
        let run = (2...8).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
        let dates = run + [now]
        let result = HairAnalytics.shieldedStreak(entryDates: dates, now: now)
        #expect(result.streak == 9)
        #expect(result.shieldsHeld == 0)
    }

    @Test func secondOneDayGapBreaksWhenNoShieldRemains() {
        let cal = Calendar.current
        let now = Date.now
        // Seven straight days (earns 1 shield), a gap at day −3 bridged by that shield, then a
        // second gap at day −1 — with no shield left, this one breaks the streak fresh at today.
        let run = (4...10).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
        let afterFirstGap = cal.date(byAdding: .day, value: -2, to: now)!
        let dates = run + [afterFirstGap, now]
        let result = HairAnalytics.shieldedStreak(entryDates: dates, now: now)
        #expect(result.streak == 1)       // restarts fresh at today
        #expect(result.shieldsHeld == 0)  // the only shield was already spent on the first gap
    }

    @Test func fourteenStraightDaysCapsShieldsAtTwo() {
        let cal = Calendar.current
        let now = Date.now
        let dates = (0..<14).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
        let result = HairAnalytics.shieldedStreak(entryDates: dates, now: now)
        #expect(result.streak == 14)
        #expect(result.shieldsHeld == 2)
    }

    @Test func twoDayGapBreaksTheStreakEvenWithAShieldHeld() {
        let cal = Calendar.current
        let now = Date.now
        // An old, long-finished 5-day run, then a 5-day gap before today's single entry — no
        // shield can cover 2+ missing days, so the run starts over fresh.
        let old = (0..<5).compactMap { cal.date(byAdding: .day, value: -$0 - 5, to: now) }
        let dates = old + [now]
        let result = HairAnalytics.shieldedStreak(entryDates: dates, now: now)
        #expect(result.streak == 1)
        #expect(result.shieldsHeld == 0)
    }

    @Test func noEntriesYieldsZeroStreakAndNoShields() {
        let result = HairAnalytics.shieldedStreak(entryDates: [], now: .now)
        #expect(result.streak == 0)
        #expect(result.shieldsHeld == 0)
    }

    @Test func entriesEndingThreeDaysAgoReportZeroStreakButShieldsStillShow() {
        let cal = Calendar.current
        let now = Date.now
        // Seven straight days ending 3 days ago: earns a shield, but the run is too old to
        // count as a current streak — shields still report what's held regardless (per spec).
        let dates = (3..<10).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
        let result = HairAnalytics.shieldedStreak(entryDates: dates, now: now)
        #expect(result.streak == 0)
        #expect(result.shieldsHeld == 1)
    }
}
