//
//  HistoryAccessTests.swift
//  Hair Compass AI 5Tests
//
//  Free users log forever and see only today. The locked count is the
//  commercial mechanic — it grows every day they stay free — so it is
//  asserted as carefully as the visibility rule itself.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct HistoryAccessTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// Today plus `past` earlier days, newest first — the order `@Query` returns.
    private func entries(past: Int) -> [DailyEntry] {
        let calendar = Calendar.current
        return (0...past).map { offset in
            DailyEntry(date: calendar.date(byAdding: .day, value: -offset, to: now)!)
        }
    }

    @Test func freeSeesOnlyToday() {
        let visible = HistoryAccess.visible(entries(past: 22),
                                            entitlements: Entitlements(tier: .free),
                                            now: now)
        #expect(visible.count == 1)
        #expect(Calendar.current.isDate(visible[0].date, inSameDayAs: now))
    }

    @Test func proSeesEverything() {
        let all = entries(past: 22)
        let visible = HistoryAccess.visible(all, entitlements: Entitlements(tier: .pro), now: now)
        #expect(visible.count == all.count)
    }

    @Test func lockedCountExcludesTodayAndCountsTheRest() {
        #expect(HistoryAccess.lockedCount(entries(past: 22),
                                          entitlements: Entitlements(tier: .free),
                                          now: now) == 22)
    }

    /// Nothing is locked for someone who can see it all, so the card never renders for them.
    @Test func lockedCountIsZeroForPro() {
        #expect(HistoryAccess.lockedCount(entries(past: 22),
                                          entitlements: Entitlements(tier: .pro),
                                          now: now) == 0)
    }

    @Test func aBrandNewUserHasNothingLocked() {
        #expect(HistoryAccess.lockedCount(entries(past: 0),
                                          entitlements: Entitlements(tier: .free),
                                          now: now) == 0)
    }

    /// The card must not render at zero — a brand-new free user should see an empty Today, not
    /// "0 days recorded", which reads as a broken feature rather than an offer.
    @Test func cardVisibilityFollowsTheLockedCount() {
        #expect(LockedHistoryCard.shouldShow(lockedCount: 0) == false)
        #expect(LockedHistoryCard.shouldShow(lockedCount: 1))
        #expect(LockedHistoryCard.shouldShow(lockedCount: 22))
    }

    @Test func cardCopyIsSingularOnTheFirstLockedDay() {
        #expect(LockedHistoryCard.headline(lockedCount: 1) == "1 day recorded")
        #expect(LockedHistoryCard.headline(lockedCount: 22) == "22 days recorded")
    }

    /// The App Group snapshot is a second read path. Whatever the free tier may not see in-app,
    /// it must not see on the Home Screen either — otherwise the wall leaks through a widget.
    @Test func widgetSnapshotCarriesNoHistoryForFreeUsers() {
        let fed = HistoryAccess.snapshotEntries(entries(past: 22),
                                                entitlements: Entitlements(tier: .free),
                                                now: now)
        #expect(fed.count == 1)
    }

    @Test func widgetSnapshotIsCompleteForPro() {
        let fed = HistoryAccess.snapshotEntries(entries(past: 22),
                                                entitlements: Entitlements(tier: .pro),
                                                now: now)
        #expect(fed.count == 23)
    }
}
