//
//  CheckInRewardTests.swift
//  Hair Compass AI 5Tests
//
//  The check-in reward moment: a pure before/after diff of the gamification engine.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct CheckInRewardTests {

    // MARK: - First log

    @Test func firstCheckInEarnsTenXPDayOneStreakAndTheFirstSeedBadge() {
        let now = Date.now
        let before = CheckInReward.Snapshot()
        let after = CheckInReward.Snapshot(entries: [DailyEntry(date: now)])
        let reward = CheckInReward.build(before: before, after: after, now: now)

        #expect(reward.xpGained == 10)          // XP.dailyLog, no streak bonus on day 1
        #expect(reward.totalXP == 10)
        #expect(reward.streak == 1)
        #expect(reward.level.name == "Seed")
        #expect(!reward.leveledUp)
        #expect(reward.newBadges == [.firstLog])
        #expect(reward.progressToNext.next?.name == "Seedling")
        #expect(reward.progressToNext.remaining == 140)
        #expect(reward.isWorthCelebrating)
    }

    // MARK: - Level-up crossing

    @Test func crossingTheSeedlingThresholdLevelsUp() {
        // 7 labs (7 × 20 = 140) + 1 trigger (5) = 145 XP before. The check-in adds +10,
        // landing at 155 — across the Seedling threshold at 150.
        let cal = Calendar.current
        let now = Date.now
        let labs = (0..<7).map { i in
            LabResult(test: .ferritin, value: 40,
                      collectedAt: cal.date(byAdding: .day, value: -i - 1, to: now)!)
        }
        let triggers = [TriggerEvent(type: .illness, date: cal.date(byAdding: .day, value: -30, to: now)!)]

        let before = CheckInReward.Snapshot(labs: labs, triggers: triggers)
        let after = CheckInReward.Snapshot(entries: [DailyEntry(date: now)], labs: labs, triggers: triggers)
        let reward = CheckInReward.build(before: before, after: after, now: now)

        #expect(reward.xpGained == 10)
        #expect(reward.totalXP == 155)
        #expect(reward.leveledUp)
        #expect(reward.level.name == "Seedling")
        #expect(reward.level.index == 2)
        #expect(reward.progressToNext.next?.name == "Sprout")
        #expect(reward.progressToNext.remaining == 245)     // 400 − 155
        // firstLab was already earned before the save — only firstLog is new.
        #expect(reward.newBadges == [.firstLog])
    }

    // MARK: - Badge diff

    @Test func seventhConsecutiveDayUnlocksOnlyTheStreakBadge() {
        // Six consecutive days already logged (firstLog long since earned); today's
        // check-in completes the run of seven → exactly streak7 appears in the diff.
        let cal = Calendar.current
        let now = Date.now
        let previous = (1...6).map { offset in
            DailyEntry(date: cal.date(byAdding: .day, value: -offset, to: now)!)
        }
        let before = CheckInReward.Snapshot(entries: previous)
        let after = CheckInReward.Snapshot(entries: previous + [DailyEntry(date: now)])
        let reward = CheckInReward.build(before: before, after: after, now: now)

        #expect(reward.streak == 7)
        #expect(reward.newBadges == [.streak7])
        // Day 7 of an unbroken run: +10 log + streak bonus 2 × (7 − 1) = +12 → 22.
        #expect(reward.xpGained == 22)
        #expect(reward.isWorthCelebrating)
    }

    // MARK: - Clamp and the no-celebrate-on-pure-edit rule

    @Test func xpGainedIsNeverNegative() {
        // Contrived shrinking record (can't happen in the save path, but the clamp holds).
        let now = Date.now
        let before = CheckInReward.Snapshot(entries: [DailyEntry(date: now)])
        let after = CheckInReward.Snapshot()
        let reward = CheckInReward.build(before: before, after: after, now: now)
        #expect(reward.xpGained == 0)
    }

    @Test func pureEditOfAnExistingEntryIsNotWorthCelebrating() {
        // Editing an already-logged day: identical record before and after — zero XP delta,
        // no new badges, so the celebration must stay quiet.
        let now = Date.now
        let entries = [DailyEntry(date: now)]
        let snapshot = CheckInReward.Snapshot(entries: entries)
        let reward = CheckInReward.build(before: snapshot, after: snapshot, now: now)
        #expect(reward.xpGained == 0)
        #expect(reward.newBadges.isEmpty)
        #expect(!reward.leveledUp)
        #expect(!reward.isWorthCelebrating)
    }
}
