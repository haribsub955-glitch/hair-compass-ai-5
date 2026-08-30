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

    // MARK: - The whole insight input, per tier (TodayGating.insightContext)
    //
    // The regression above could only test the mapping by re-wiring TodayGating.visible into
    // InsightContext.build by hand, because `TodayView.buildContext()` is `private` and
    // unreachable even via @testable — which is exactly why a 439-test suite never saw that four
    // of the six inputs were still raw @Querys. `TodayGating.insightContext` closes that: it
    // takes the RAW queries and owns every entitlement decision, so this file now asserts what
    // the insight engine actually receives rather than what a test happened to assemble.

    /// One record with something gated in every corner: labs, HealthKit, a clinician-review
    /// pattern from progress check-ins and from side-effect logs, an active treatment, and
    /// twenty days of history with a direction in it.
    private struct LeakyRecord {
        let now = Date.now
        let entries: [DailyEntry]
        let treatments: [Treatment]
        let snapshots: [HealthSnapshot]
        let labs: [LabResult]
        let progressCheckIns: [ProgressCheckIn]
        let sideEffects: [SideEffectLog]

        init() {
            let calendar = Calendar.current
            let now = Date.now
            // Twenty consecutive logged days, shedding heavier at the start than at the end, so
            // `HairAnalytics.direction` has a real (improving) direction to report.
            entries = (0..<20).map { offset in
                DailyEntry(
                    date: calendar.date(byAdding: .day, value: -offset, to: now)!,
                    shed: offset > 12 ? .heavy : .elevated
                )
            }
            treatments = [Treatment(name: "Minoxidil", treatmentClass: .minoxidil,
                                    scheduleTimes: "08:00", startDate: now, isActive: true)]
            // 7% down over the window — the "rapid loss can trigger shedding" sentence.
            snapshots = [
                HealthSnapshot(date: calendar.date(byAdding: .day, value: -60, to: now)!,
                               sleepHours: 7.5, hrvSDNN: 48, bodyMassKg: 86),
                HealthSnapshot(date: now, sleepHours: 6.0, hrvSDNN: 41, bodyMassKg: 80),
            ]
            labs = [LabResult(test: .ferritin, value: 18, collectedAt: calendar.date(byAdding: .day, value: -5, to: now)!)]
            progressCheckIns = [ProgressCheckIn(date: calendar.date(byAdding: .day, value: -10, to: now)!,
                                                scalpPain: true, scalpPainNote: "tender crown")]
            sideEffects = [SideEffectLog(severity: 3, date: calendar.date(byAdding: .day, value: -2, to: now)!)]
        }
    }

    @MainActor
    private func context(for tier: EntitlementTier, record: LeakyRecord) -> InsightContext {
        TodayGating.insightContext(
            entries: record.entries, treatments: record.treatments, doses: [],
            snapshots: record.snapshots, triggers: [], labs: record.labs, profile: nil,
            progressCheckIns: record.progressCheckIns, sideEffects: record.sideEffects,
            entitlements: Entitlements(tier: tier), now: record.now
        )
    }

    /// The Critical this file's second half exists for: everything gated is withheld at the
    /// SOURCE — from the deterministic paragraph AND from the facts handed to the on-device
    /// model — not filtered out of the finished sentence afterwards.
    @Test @MainActor func freeTierInsightSeesNoGatedRecordAtAll() {
        let record = LeakyRecord()
        let free = context(for: .free, record: record)

        #expect(free.labs.isEmpty, "Labs are .labs — 'Ferritin is below the range…' is a locked value.")
        #expect(free.sleepHours == nil, "HealthKit is .bodySignals.")
        #expect(free.hrvSDNN == nil)
        #expect(free.rapidWeightLossPercent == nil, "The weight-loss sentence is derived entirely from HealthKit.")
        #expect(free.clinicianReviewFlags.isEmpty,
                "Progress check-ins and side-effect logs are .reports — the flags are the clinician summary it sells.")
        #expect(free.treatments.isEmpty, "Treatment names are .treatments.")
        #expect(free.describesTrend == false, "A direction is a statement about locked history.")

        let facts = RuleBasedInsight.facts(free)
        let paragraph = RuleBasedInsight.paragraph(free)
        for leak in ["Ferritin", "Minoxidil", "Weight is down", "Scalp pain", "severe side effect", "improving"] {
            #expect(!facts.contains(leak), "facts() leaked \(leak) to the on-device model")
            #expect(!paragraph.contains(leak), "paragraph() leaked \(leak) onto the free Today screen")
        }
    }

    /// Withholding must not produce a blank or broken paragraph: the free tier keeps today's own
    /// values, which the spec puts on the free side of the line, said without a trend clause.
    @Test @MainActor func freeTierInsightStillSpeaksAboutToday() {
        let paragraph = RuleBasedInsight.paragraph(context(for: .free, record: LeakyRecord()))
        #expect(paragraph.contains("Shedding is elevated today."))
        #expect(!paragraph.contains("steady"),
                "A data-starved direction of 0 must not render as 'steady' — that is still a claim about history.")
    }

    /// The count and the streak are the two numbers a free user is already shown (the hero's
    /// streak, `LockedHistoryCard`'s locked-day count), so they survive the filter. A count of 1
    /// would contradict the hero on the same screen AND route a twenty-day user into the "keep
    /// logging for a few more days" branch.
    @Test @MainActor func freeTierKeepsTheCountAndStreakItIsAlreadyShown() {
        let record = LeakyRecord()
        let free = context(for: .free, record: record)
        #expect(free.entryCount == 20)
        #expect(free.streak == 20)
    }

    @Test @MainActor func entitledTiersStillGetTheWholeRecord() {
        let record = LeakyRecord()
        for tier in [EntitlementTier.pro, .taster] {
            let full = context(for: tier, record: record)
            #expect(full.labs.contains { $0.name == "Ferritin" }, "\(tier) paid for labs.")
            #expect(full.sleepHours != nil, "\(tier) paid for body signals.")
            #expect(full.rapidWeightLossPercent != nil)
            #expect(full.clinicianReviewFlags.contains { $0.id == "scalpPain" }, "\(tier) paid for the review flags.")
            #expect(full.clinicianReviewFlags.contains { $0.id == "severeSideEffect" })
            #expect(full.treatments.contains { $0.name == "Minoxidil" })
            #expect(full.describesTrend, "\(tier) can see the history a direction describes.")
            #expect(full.entryCount == 20)

            let paragraph = RuleBasedInsight.paragraph(full)
            #expect(paragraph.contains("Minoxidil"))
            #expect(RuleBasedInsight.facts(full).contains("Ferritin"))
        }
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
