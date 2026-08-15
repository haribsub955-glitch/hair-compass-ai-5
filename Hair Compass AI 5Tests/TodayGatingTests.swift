//
//  TodayGatingTests.swift
//  Hair Compass AI 5Tests
//
//  Today is free by design — the one surface a lapsed subscriber keeps — but `.treatments` and
//  `.photos` are hard-gated on CareView/PhotosView. A lapsed subscriber's treatments/photos are
//  still sitting in SwiftData, so TodayGating.visible must strip treatment names and
//  photo-completion detail out of EVERYTHING Today builds from them — the rings/ledger, AND the
//  daily-insight paragraph and status caption, which read treatments/doses through a second path
//  (`InsightContext.build`) that the first pass at this fix missed. Same read-path pattern
//  WidgetSnapshotBuilder already uses for the Home Screen widget (see WidgetSnapshotTests.swift's
//  "Entitlement-aware suppression" section).
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
            treatments: [minoxidil], doses: [],
            entitlements: Entitlements(tier: .free)
        )

        #expect(visible.dailySlots.isEmpty)
        #expect(visible.medsDone == 0)
        // Zero, not filtered-and-recounted — this is what makes CompassScore's
        // `care = medsTotal > 0 ? … : nil` branch fall back to "no plan today" instead of a new
        // locked state.
        #expect(visible.medsTotal == 0)
        #expect(visible.treatments.isEmpty)
    }

    @Test func freeTierWithdrawsPhotoSignal() {
        let visible = TodayGating.visible(
            dailySlots: [], medsDone: 0, hasPhotoThisWeek: true,
            treatments: [], doses: [],
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
            treatments: [minoxidil], doses: [],
            entitlements: Entitlements(tier: .free)
        )
        let score = CompassScore(
            hasLoggedToday: true, medsDone: visible.medsDone, medsTotal: visible.medsTotal,
            hasPhotoThisWeek: visible.hasPhotoThisWeek
        )
        #expect(score.care == nil)
    }

    /// Fix-round 1: `TodayView.buildContext()` used to feed the raw, unfiltered `treatments`
    /// query into `InsightContext.build`, and `RuleBasedInsight.paragraph` names any active
    /// under-24-week treatment unconditionally ("Judge Minoxidil at 6 months, not sooner…") — a
    /// leak independent of, and missed by, the rings/ledger suppression above. This is the test
    /// that would have caught it: a free tier with an active under-24-week treatment must
    /// produce insight input containing no treatment name, in both the facts fed to the model and
    /// the deterministic fallback paragraph actually shown.
    @Test @MainActor func freeTierProducesInsightInputWithNoTreatmentName() {
        let minoxidil = Treatment(
            name: "Minoxidil", treatmentClass: .minoxidil,
            scheduleTimes: "08:00", startDate: now, isActive: true
        )
        let entries = (0..<5).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: now).map {
                DailyEntry(date: $0, shed: .elevated, flaking: 1, erythema: 1, itch: 1)
            }
        }
        let visible = TodayGating.visible(
            dailySlots: [(minoxidil, "08:00")], medsDone: 0, hasPhotoThisWeek: false,
            treatments: [minoxidil], doses: [],
            entitlements: Entitlements(tier: .free)
        )

        let context = InsightContext.build(
            entries: entries, treatments: visible.treatments, doses: visible.doses,
            snapshots: [], triggers: [], labs: [], profile: nil
        )

        #expect(context.treatments.isEmpty)
        #expect(context.recentStop == nil)
        let facts = RuleBasedInsight.facts(context)
        let paragraph = RuleBasedInsight.paragraph(context)
        #expect(!facts.contains("Minoxidil"))
        #expect(!paragraph.contains("Minoxidil"))
        // Degrades gracefully, not to an empty or broken sentence — the same voice used for
        // someone genuinely on no plan (entryCount >= 3 here, so it's the trend sentence, not
        // the "keep logging" one).
        #expect(!paragraph.isEmpty)
        #expect(paragraph.contains("Shedding"))
    }

    /// Sanity check in the other direction: an entitled tier's insight still names the treatment
    /// — this is a real feature for someone actually paying, not something to suppress globally.
    @Test @MainActor func proTierProducesInsightInputWithTreatmentName() {
        let minoxidil = Treatment(
            name: "Minoxidil", treatmentClass: .minoxidil,
            scheduleTimes: "08:00", startDate: now, isActive: true
        )
        let visible = TodayGating.visible(
            dailySlots: [(minoxidil, "08:00")], medsDone: 0, hasPhotoThisWeek: false,
            treatments: [minoxidil], doses: [],
            entitlements: Entitlements(tier: .pro)
        )

        let context = InsightContext.build(
            entries: [], treatments: visible.treatments, doses: visible.doses,
            snapshots: [], triggers: [], labs: [], profile: nil
        )

        #expect(context.treatments.contains { $0.name == "Minoxidil" })
        #expect(RuleBasedInsight.paragraph(context).contains("Minoxidil"))
    }

    // MARK: - Taster/Pro: everything passes through unfiltered

    @Test func proTierSeesEverything() {
        let minoxidil = Treatment(
            name: "Minoxidil", treatmentClass: .minoxidil,
            scheduleTimes: "08:00,21:00", startDate: now, isActive: true
        )
        let dose = TreatmentDose(treatment: minoxidil, loggedAt: now, slot: "08:00")
        let dailySlots = [(minoxidil, "08:00"), (minoxidil, "21:00")]

        let visible = TodayGating.visible(
            dailySlots: dailySlots, medsDone: 1, hasPhotoThisWeek: true,
            treatments: [minoxidil], doses: [dose],
            entitlements: Entitlements(tier: .pro)
        )

        #expect(visible.dailySlots.count == 2)
        #expect(visible.dailySlots.map(\.0.name) == ["Minoxidil", "Minoxidil"])
        #expect(visible.medsDone == 1)
        #expect(visible.medsTotal == 2)
        #expect(visible.hasPhotoThisWeek == true)
        #expect(visible.treatments.map(\.name) == ["Minoxidil"])
        #expect(visible.doses.count == 1)
    }

    @Test func tasterTierSeesEverything() {
        let finasteride = Treatment(
            name: "Finasteride", treatmentClass: .finasteride,
            scheduleTimes: "21:00", startDate: now, isActive: true
        )
        let dose = TreatmentDose(treatment: finasteride, loggedAt: now, slot: "21:00")
        let visible = TodayGating.visible(
            dailySlots: [(finasteride, "21:00")], medsDone: 1, hasPhotoThisWeek: true,
            treatments: [finasteride], doses: [dose],
            entitlements: Entitlements(tier: .taster)
        )
        #expect(visible.dailySlots.count == 1)
        #expect(visible.dailySlots.map(\.0.name) == ["Finasteride"])
        #expect(visible.medsTotal == 1)
        #expect(visible.hasPhotoThisWeek == true)
        #expect(visible.treatments.map(\.name) == ["Finasteride"])
        #expect(visible.doses.count == 1)
    }

    // MARK: - No plan at all, regardless of tier

    @Test func nothingScheduledStaysEmptyForEveryTier() {
        for tier in [EntitlementTier.free, .taster, .pro] {
            let visible = TodayGating.visible(
                dailySlots: [], medsDone: 0, hasPhotoThisWeek: false,
                treatments: [], doses: [],
                entitlements: Entitlements(tier: tier)
            )
            #expect(visible.dailySlots.isEmpty)
            #expect(visible.medsTotal == 0)
            #expect(visible.treatments.isEmpty)
            #expect(visible.doses.isEmpty)
        }
    }
}
