//
//  TodayGatingTests.swift
//  Hair Compass AI 5Tests
//
//  Today is free by design — the one surface a lapsed subscriber keeps — but `.treatments` and
//  `.photos` are hard-gated on CareView/PhotosView. A lapsed subscriber's treatments/photos are
//  still sitting in SwiftData, so TodayGating.visible must strip treatment names and
//  photo-completion detail out of what Today builds its rings/ledger from, the same read-path
//  pattern WidgetSnapshotBuilder already uses for the Home Screen widget (see
//  WidgetSnapshotTests.swift's "Entitlement-aware suppression" section).
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct TodayGatingTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - Free tier: no treatment name exposed, rings read as "no plan" / "no photo"

    @Test func freeTierWithdrawsTreatmentDetailAndCollapsesTheRoutine() {
        let minoxidil = Treatment(
            name: "Minoxidil", treatmentClass: .minoxidil,
            scheduleTimes: "08:00,21:00", startDate: now, isActive: true
        )
        let dailySlots = [(minoxidil, "08:00"), (minoxidil, "21:00")]

        let visible = TodayGating.visible(
            dailySlots: dailySlots, medsDone: 1, hasPhotoThisWeek: true,
            entitlements: Entitlements(tier: .free)
        )

        #expect(visible.dailySlots.isEmpty)
        #expect(visible.medsDone == 0)
        // Zero, not filtered-and-recounted — this is what makes CompassScore's
        // `care = medsTotal > 0 ? … : nil` branch fall back to "no plan today" instead of a new
        // locked state.
        #expect(visible.medsTotal == 0)
    }

    @Test func freeTierWithdrawsPhotoSignal() {
        let visible = TodayGating.visible(
            dailySlots: [], medsDone: 0, hasPhotoThisWeek: true,
            entitlements: Entitlements(tier: .free)
        )
        #expect(visible.hasPhotoThisWeek == false)
    }

    /// The realistic case this task exists for: a lapsed subscriber whose plan is still in
    /// SwiftData. The Care ring must fall back to CompassScore's existing nil ("no plan today")
    /// state, not a partial/locked fraction of a plan the free tier can't act on.
    @Test func lapsedSubscriberSeesCareRingAsNoPlanEvenWithStoredTreatments() {
        let minoxidil = Treatment(
            name: "Minoxidil", treatmentClass: .minoxidil,
            scheduleTimes: "08:00", startDate: now, isActive: true
        )
        let visible = TodayGating.visible(
            dailySlots: [(minoxidil, "08:00")], medsDone: 0, hasPhotoThisWeek: false,
            entitlements: Entitlements(tier: .free)
        )
        let score = CompassScore(
            hasLoggedToday: true, medsDone: visible.medsDone, medsTotal: visible.medsTotal,
            hasPhotoThisWeek: visible.hasPhotoThisWeek
        )
        #expect(score.care == nil)
    }

    // MARK: - Taster/Pro: everything passes through unfiltered

    @Test func proTierSeesEverything() {
        let minoxidil = Treatment(
            name: "Minoxidil", treatmentClass: .minoxidil,
            scheduleTimes: "08:00,21:00", startDate: now, isActive: true
        )
        let dailySlots = [(minoxidil, "08:00"), (minoxidil, "21:00")]

        let visible = TodayGating.visible(
            dailySlots: dailySlots, medsDone: 1, hasPhotoThisWeek: true,
            entitlements: Entitlements(tier: .pro)
        )

        #expect(visible.dailySlots.count == 2)
        #expect(visible.dailySlots.map(\.0.name) == ["Minoxidil", "Minoxidil"])
        #expect(visible.medsDone == 1)
        #expect(visible.medsTotal == 2)
        #expect(visible.hasPhotoThisWeek == true)
    }

    @Test func tasterTierSeesEverything() {
        let minoxidil = Treatment(
            name: "Finasteride", treatmentClass: .finasteride,
            scheduleTimes: "21:00", startDate: now, isActive: true
        )
        let visible = TodayGating.visible(
            dailySlots: [(minoxidil, "21:00")], medsDone: 1, hasPhotoThisWeek: true,
            entitlements: Entitlements(tier: .taster)
        )
        #expect(visible.dailySlots.count == 1)
        #expect(visible.medsTotal == 1)
        #expect(visible.hasPhotoThisWeek == true)
    }

    // MARK: - No plan at all, regardless of tier

    @Test func nothingScheduledStaysEmptyForEveryTier() {
        for tier in [EntitlementTier.free, .taster, .pro] {
            let visible = TodayGating.visible(
                dailySlots: [], medsDone: 0, hasPhotoThisWeek: false,
                entitlements: Entitlements(tier: tier)
            )
            #expect(visible.dailySlots.isEmpty)
            #expect(visible.medsTotal == 0)
        }
    }
}
