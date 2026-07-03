//
//  Hair_Compass_AI_5Tests.swift
//  Hair Compass AI 5Tests
//
//  Tests the evidence-based analytics core (see docs/TrackingSpec.md).
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct Hair_Compass_AI_5Tests {

    // MARK: - Seborrheic-dermatitis 16-point scale (Zhang 2023)

    @Test func scalpTotalMapsFlakingBandOntoValidatedScale() {
        // Flaking band 0..3 → 0/3/6/10; plus erythema + itch (0..3 each), total /16.
        #expect(HairAnalytics.scalpTotal(flaking: 0, erythema: 0, itch: 0) == 0)
        #expect(HairAnalytics.scalpTotal(flaking: 3, erythema: 3, itch: 3) == 16)
        #expect(HairAnalytics.scalpTotal(flaking: 1, erythema: 1, itch: 1) == 5) // 3+1+1
        #expect(HairAnalytics.scalpTotal(flaking: 2, erythema: 0, itch: 1) == 7) // 6+0+1
    }

    @Test func scalpBandsUsePublishedThresholds() {
        #expect(HairAnalytics.scalpBand(total: 0) == .mild)
        #expect(HairAnalytics.scalpBand(total: 5) == .mild)
        #expect(HairAnalytics.scalpBand(total: 6) == .moderate)
        #expect(HairAnalytics.scalpBand(total: 9) == .moderate)
        #expect(HairAnalytics.scalpBand(total: 10) == .severe)
        #expect(HairAnalytics.scalpBand(total: 16) == .severe)
    }

    // MARK: - Labs

    @Test func labFlagsAgainstReferenceRanges() {
        #expect(HairAnalytics.flag(for: 10, test: .ferritin) == .low)   // < 30
        #expect(HairAnalytics.flag(for: 80, test: .ferritin) == .normal)
        #expect(HairAnalytics.flag(for: 20, test: .vitaminD) == .low)   // < 30
        #expect(HairAnalytics.flag(for: 5.0, test: .tsh) == .high)      // > 4.0
    }

    // MARK: - 24-week outcome gate

    @Test func outcomeGateOpensAtTwentyFourWeeks() {
        #expect(HairAnalytics.outcomeReady(weeksElapsed: 23) == false)
        #expect(HairAnalytics.outcomeReady(weeksElapsed: 24) == true)
        #expect(HairAnalytics.outcomeProgress(weeksElapsed: 12) == 0.5)
        #expect(HairAnalytics.outcomeProgress(weeksElapsed: 48) == 1.0) // capped
    }

    @Test func weeksElapsedCountsWholeWeeks() {
        let start = Calendar.current.date(byAdding: .day, value: -21, to: .now)!
        #expect(HairAnalytics.weeksElapsed(since: start) == 3)
    }

    // MARK: - Adherence

    @Test func adherenceIsLoggedOverExpectedInWindow() throws {
        let cal = Calendar.current
        let now = Date.now
        // 2x/day expected over 14 days = 28 expected. Log 14 (one per day) = 50%.
        var dates: [Date] = []
        for d in 0..<14 {
            if let day = cal.date(byAdding: .day, value: -d, to: now) { dates.append(day) }
        }
        let pct = try #require(HairAnalytics.adherence(doseDates: dates, expectedPerDay: 2, windowDays: 14, now: now))
        #expect(abs(pct - 0.5) < 0.001)
    }

    @Test func adherenceIsNilForPeriodicTreatments() {
        #expect(HairAnalytics.adherence(doseDates: [], expectedPerDay: 0) == nil)
    }

    // MARK: - Trends

    @Test func directionDetectsRiseAndFall() {
        #expect(HairAnalytics.direction([1, 1, 1, 5, 5, 5]) > 0)   // rising
        #expect(HairAnalytics.direction([5, 5, 5, 1, 1, 1]) < 0)   // falling
    }

    @Test func rollingAverageSmoothsSeries() {
        let smoothed = HairAnalytics.rollingAverage([0, 10, 0, 10], window: 2)
        #expect(smoothed[0] == 0)
        #expect(smoothed[1] == 5)
        #expect(smoothed[3] == 5)
    }

    // MARK: - Rapid weight loss (telogen-effluvium trigger)

    @Test func rapidWeightLossFlagsMeaningfulDrop() throws {
        let cal = Calendar.current
        let now = Date.now
        // 80kg → 74kg over the window = 7.5% drop, above the 5% threshold.
        let samples: [(date: Date, massKg: Double)] = [
            (cal.date(byAdding: .day, value: -60, to: now)!, 80),
            (cal.date(byAdding: .day, value: -30, to: now)!, 77),
            (cal.date(byAdding: .day, value: -2, to: now)!, 74)
        ]
        let pct = try #require(HairAnalytics.rapidWeightLossPercent(samples: samples, now: now))
        #expect(abs(pct - 7.5) < 0.001)
    }

    @Test func rapidWeightLossIgnoresSmallOrStableChange() {
        let cal = Calendar.current
        let now = Date.now
        let samples: [(date: Date, massKg: Double)] = [
            (cal.date(byAdding: .day, value: -60, to: now)!, 80),
            (cal.date(byAdding: .day, value: -2, to: now)!, 79) // 1.25% — below threshold
        ]
        #expect(HairAnalytics.rapidWeightLossPercent(samples: samples, now: now) == nil)
    }

    @Test func rapidWeightLossIgnoresReadingsOutsideWindow() {
        let cal = Calendar.current
        let now = Date.now
        // Only an old reading and a recent one 6 months apart — the old one is outside 90 days.
        let samples: [(date: Date, massKg: Double)] = [
            (cal.date(byAdding: .day, value: -180, to: now)!, 90),
            (cal.date(byAdding: .day, value: -2, to: now)!, 74)
        ]
        #expect(HairAnalytics.rapidWeightLossPercent(samples: samples, now: now) == nil)
    }

    // MARK: - New daily fields

    @Test func dailyEntryStoresOilinessAndAlcohol() {
        let entry = DailyEntry(alcoholDrinks: 2, oiliness: 3)
        #expect(entry.alcoholDrinks == 2)
        #expect(entry.oiliness == 3)
        // Oiliness must not feed the validated scalp score.
        #expect(entry.scalpTotal == 0)
    }

    @Test func profileFlagsTractionRisk() {
        #expect(Profile().hasTractionRisk == false)
        #expect(Profile(usesHeat: true).hasTractionRisk == true)
    }

    // MARK: - Tracked-variable catalog

    @Test func catalogTiersMatchTheEvidencePass() {
        #expect(TrackedVariable["oiliness"]?.tier == .weak)   // observation, not a risk driver
        #expect(TrackedVariable["cigarettes"]?.tier == .strong)
        #expect(TrackedVariable["hrv"]?.capture == .auto)     // stress proxy, auto-fetched
        #expect(TrackedVariable["weight"]?.capture == .auto)
    }

    // MARK: - Routine planner (Plan)

    @Test func routineGroupsSlotsIntoTimeBlocks() {
        let steps = RoutinePlanner.steps(
            treatments: [
                (id: "1", name: "Minoxidil", symbol: "drop.fill", slots: ["08:00", "21:00"], isActive: true, treatmentClass: .minoxidil),
                (id: "2", name: "PRP", symbol: "syringe.fill", slots: [], isActive: true, treatmentClass: .prp),
                (id: "3", name: "Old", symbol: "x", slots: ["09:00"], isActive: false, treatmentClass: .other)
            ],
            loggedSlots: ["1|08:00"]
        )
        #expect(steps[.morning]?.count == 1)      // 08:00 minoxidil
        #expect(steps[.evening]?.count == 1)      // 21:00 minoxidil
        #expect(steps[.periodic]?.count == 1)     // PRP
        #expect(steps[.morning]?.first?.done == true)   // logged
        #expect(steps[.evening]?.first?.done == false)  // not logged
        // Inactive treatment is excluded entirely.
        #expect((steps[.morning] ?? []).allSatisfy { $0.treatmentName != "Old" })
    }

    @Test func dailyProgressCountsNonPeriodicSteps() {
        let steps = RoutinePlanner.steps(
            treatments: [(id: "1", name: "Minox", symbol: "d", slots: ["08:00", "21:00"], isActive: true, treatmentClass: .minoxidil)],
            loggedSlots: ["1|08:00"]
        )
        let p = RoutinePlanner.dailyProgress(steps)
        #expect(p.done == 1)
        #expect(p.total == 2)
    }

    // MARK: - Adherence coach

    @Test func coachReflectsRemainingSteps() {
        let done = AdherenceCoach.message(doneToday: 2, totalToday: 2, streak: 5, weeklyAdherence: nil)
        #expect(done.headline == "Today's routine is done")
        let left = AdherenceCoach.message(doneToday: 1, totalToday: 3, streak: 0, weeklyAdherence: nil)
        #expect(left.headline == "2 steps left today")
        let one = AdherenceCoach.message(doneToday: 2, totalToday: 3, streak: 0, weeklyAdherence: nil)
        #expect(one.headline == "1 step left today")
    }

    // MARK: - Milestones

    @Test func milestonesDetectStreakAndTreatmentMarks() {
        let m = Milestones.achieved(streak: 7, treatments: [(name: "Minox", weeks: 26), (name: "Fin", weeks: 13)])
        #expect(m.contains { $0.id == "streak-7" })
        #expect(m.contains { $0.id == "ready-Minox" })   // >= 24 weeks
        #expect(m.contains { $0.id == "half-Fin" })       // 12..<24
        // Below the first threshold, no streak milestone.
        #expect(Milestones.achieved(streak: 2, treatments: []).isEmpty)
    }

    // MARK: - Learn library integrity

    @Test func learnLibraryCoversEveryCategoryWithUniqueIDs() {
        for category in LearnCategory.allCases {
            #expect(!LearnLibrary.cards(in: category).isEmpty)
        }
        let ids = LearnLibrary.cards.map(\.id)
        #expect(Set(ids).count == ids.count)                       // unique ids
        #expect(LearnLibrary.cards(in: .myths).allSatisfy { $0.isMyth })
    }

    // MARK: - Science product catalog (affiliate)

    @Test func scienceCatalogIsHonestAndMythFree() {
        let ids = ScienceCatalog.products.map(\.id)
        #expect(Set(ids).count == ids.count)                       // unique ids
        // The myths/harmful items must never appear as sellable products.
        let banned = ["biotin", "collagen", "zinc", "niacinamide", "gummies", "multivitamin"]
        for product in ScienceCatalog.products {
            #expect(!banned.contains(product.id))
        }
        // The three defensible ones are present and tiered moderate.
        #expect(ScienceCatalog["rosemary"]?.evidence == .moderate)
        #expect(ScienceCatalog["sawpalmetto"]?.evidence == .moderate)
        // Deficiency-gated items are flagged so the UI can gate them.
        #expect(ScienceCatalog["iron"]?.deficiencyGated == true)
        #expect(ScienceCatalog["vitamind"]?.evidence == .conditional)
    }

    @Test @MainActor func affiliateStoreRoundTripsAndHidesEmpty() {
        let store = AffiliateStore()
        let id = "rosemary"
        store.setLink("", for: id)
        #expect(store.hasLink(for: id) == false)                   // empty → no buy button
        store.setLink("https://iherb.com/pr/rosemary", for: id)
        #expect(store.hasLink(for: id) == true)
        #expect(store.url(for: id)?.absoluteString == "https://iherb.com/pr/rosemary")
        store.setLink("", for: id)                                 // clean up
    }

    // MARK: - Compare (chart math)

    @Test func chartAssociationReadsSignAndClarity() {
        let up = [1.0, 2, 3, 4, 5], upToo = [2.0, 4, 6, 8, 10]
        #expect(ChartMath.association(hair: up, lifestyle: upToo, minPairs: 4) == .together)
        let down = [5.0, 4, 3, 2, 1]
        #expect(ChartMath.association(hair: up, lifestyle: down, minPairs: 4) == .opposite)
        // Too few pairs → insufficient regardless of shape.
        if case .insufficient = ChartMath.association(hair: [1, 2], lifestyle: [1, 2], minPairs: 8) {} else {
            Issue.record("expected .insufficient")
        }
    }

    @Test func chartNormalizeMapsToUnitRange() {
        let n = ChartMath.normalize([10, 20, 30])
        #expect(n.first == 0)
        #expect(n.last == 1)
        // Flat series → all mid, no divide-by-zero.
        #expect(ChartMath.normalize([7, 7, 7]).allSatisfy { $0 == 0.5 })
    }

    @Test func chartPairWithLagShiftsLifestyleEarlier() {
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: .now)
        func d(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: day0)! }
        // Hair today; lifestyle 14 days earlier. A 14-day lag should pair them.
        let hair = [(day: d(0), value: 3.0)]
        let life = [(day: d(-14), value: 9.0)]
        let paired = ChartMath.pairWithLag(hair: hair, lifestyle: life, lagDays: 14)
        #expect(paired.hair == [3.0])
        #expect(paired.lifestyle == [9.0])
        // With no lag, they wouldn't line up.
        #expect(ChartMath.pairWithLag(hair: hair, lifestyle: life, lagDays: 0).hair.isEmpty)
    }

    // MARK: - Treatment recommender (gentle educator)

    @Test func recommenderRanksByPatternAndStaysNonPrescriptive() {
        let male = TreatmentRecommender.options(condition: .androgenetic, sex: .male)
        #expect(male.first?.id == "combo")          // most effective combo ranked first
        #expect(male.first?.tier == .strong)
        // Every option carries a clinician note (never a bare prescription).
        #expect(male.allSatisfy { !$0.clinicianNote.isEmpty })
        // Female AGA leads with topical minoxidil, not finasteride.
        #expect(TreatmentRecommender.options(condition: .androgenetic, sex: .female).first?.id == "minox-f")
        // Alopecia areata routes to a specialist.
        #expect(TreatmentRecommender.options(condition: .alopeciaAreata, sex: .male).first?.id == "derm-aa")
    }

    // MARK: - Widget snapshot

    @Test @MainActor func widgetSnapshotSummarizesStreakAndDue() {
        let cal = Calendar.current
        let entry = DailyEntry(date: .now, flaking: 1, erythema: 1, itch: 1)
        let t = Treatment(name: "Minoxidil", treatmentClass: .minoxidil, scheduleTimes: "08:00,21:00", startDate: .now, isActive: true)
        let snap = WidgetSnapshotBuilder.build(entries: [entry], treatments: [t], doses: [], now: .now, calendar: cal)
        #expect(snap.streakDays == 1)
        #expect(snap.dueTitles.count == 2)          // both slots unlogged
        #expect(snap.headline == "2 steps left today")
    }

    // MARK: - Streak

    @Test func loggingStreakCountsConsecutiveDays() {
        let cal = Calendar.current
        let now = Date.now
        let dates = (0..<3).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
        #expect(HairAnalytics.loggingStreak(entryDates: dates, now: now) == 3)
    }

    @Test func loggingStreakBreaksOnGap() {
        let cal = Calendar.current
        let now = Date.now
        let today = now
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: now)!
        #expect(HairAnalytics.loggingStreak(entryDates: [today, threeDaysAgo], now: now) == 1)
    }

    // MARK: - Model bridging

    @Test func dailyEntryComputesScalpBandFromItems() {
        let entry = DailyEntry(flaking: 3, erythema: 3, itch: 3)
        #expect(entry.scalpTotal == 16)
        #expect(entry.scalpBand == .severe)
    }

    @Test func treatmentFallsBackToDefaultSlots() {
        let minox = Treatment(treatmentClass: .minoxidil)
        #expect(minox.slots == ["08:00", "21:00"])
        let prp = Treatment(treatmentClass: .prp)
        #expect(prp.slots.isEmpty)
    }
}
