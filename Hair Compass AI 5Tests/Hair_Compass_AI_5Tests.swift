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

    // MARK: - Refill tracking

    @Test func refillUrgencyBandsAtTheDocumentedEdges() {
        #expect(HairAnalytics.refillUrgency(daysLeft: nil) == RefillUrgency.none)
        #expect(HairAnalytics.refillUrgency(daysLeft: -1) == .overdue)
        #expect(HairAnalytics.refillUrgency(daysLeft: 0) == .urgent)
        #expect(HairAnalytics.refillUrgency(daysLeft: 7) == .urgent)
        #expect(HairAnalytics.refillUrgency(daysLeft: 8) == .soon)
        #expect(HairAnalytics.refillUrgency(daysLeft: 14) == .soon)
        #expect(HairAnalytics.refillUrgency(daysLeft: 15) == .ok)
    }

    @Test func daysUntilRefillCountsWholeDaysAndGoesNegativeWhenOverdue() throws {
        let cal = Calendar.current
        let now = Date.now
        #expect(HairAnalytics.daysUntilRefill(nil, now: now) == nil)
        #expect(HairAnalytics.daysUntilRefill(now, now: now) == 0)
        let inTen = try #require(cal.date(byAdding: .day, value: 10, to: now))
        #expect(HairAnalytics.daysUntilRefill(inTen, now: now) == 10)
        let threeAgo = try #require(cal.date(byAdding: .day, value: -3, to: now))
        #expect(HairAnalytics.daysUntilRefill(threeAgo, now: now) == -3)
    }

    @Test func treatmentBridgesRefillDate() throws {
        let none = Treatment(treatmentClass: .minoxidil)
        #expect(none.daysUntilRefill == nil)
        let due = try #require(Calendar.current.date(byAdding: .day, value: 5, to: .now))
        let tracked = Treatment(treatmentClass: .minoxidil, refillBy: due)
        #expect(tracked.daysUntilRefill == 5)
    }

    // MARK: - Tolerability (side effects)

    @Test func severeSideEffectBannerNeedsSeverityThreeWithinFourteenDays() throws {
        let cal = Calendar.current
        let now = Date.now
        let recent = try #require(cal.date(byAdding: .day, value: -3, to: now))
        let old = try #require(cal.date(byAdding: .day, value: -20, to: now))
        // Severity 3 in-window → banner.
        #expect(HairAnalytics.hasRecentSevereSideEffect(logs: [(3, recent)], now: now) == true)
        // Severity 3 but stale, or recent-but-mild → no banner.
        #expect(HairAnalytics.hasRecentSevereSideEffect(logs: [(3, old)], now: now) == false)
        #expect(HairAnalytics.hasRecentSevereSideEffect(logs: [(2, recent), (1, recent)], now: now) == false)
        #expect(HairAnalytics.hasRecentSevereSideEffect(logs: [], now: now) == false)
    }

    @Test func sideEffectLogBridgesTypeAndClampsSeverity() {
        let log = SideEffectLog(type: .shedding, severity: 9, note: "early flare")
        #expect(log.type == .shedding)
        #expect(log.severity == 3)                        // clamped to 1…3
        #expect(log.type.caption == "Often transient early on")
        #expect(SideEffectLog(severity: 0).severity == 1) // floor
    }

    @Test @MainActor func refillReminderFiresAWeekBeforeAtTen() throws {
        let cal = Calendar.current
        let refillBy = try #require(cal.date(byAdding: .day, value: 30, to: cal.startOfDay(for: .now)))
        let fire = try #require(NotificationService.refillReminderDate(for: refillBy, calendar: cal))
        #expect(cal.dateComponents([.day], from: cal.startOfDay(for: fire), to: cal.startOfDay(for: refillBy)).day == 7)
        #expect(cal.component(.hour, from: fire) == 10)
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
        let doneWithoutStreak = AdherenceCoach.message(doneToday: 2, totalToday: 2, streak: 1, weeklyAdherence: nil)
        #expect(doneWithoutStreak.detail == "All 2 steps are complete. Your plan is set for today.")
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

    // MARK: - Progress report (the periodic synthesis)

    @Test func progressReportMilestonesFollowTheReviewCadence() {
        // Weeks 4, 12, 24, then every 12 (36, 48, …).
        for week in [4, 12, 24, 36, 48, 60] { #expect(ProgressReport.isMilestone(week: week)) }
        for week in [0, 1, 8, 20, 23, 25, 30, 47] { #expect(!ProgressReport.isMilestone(week: week)) }
        #expect(ProgressReport.nextMilestone(after: 0) == 4)
        #expect(ProgressReport.nextMilestone(after: 4) == 12)
        #expect(ProgressReport.nextMilestone(after: 12) == 24)
        #expect(ProgressReport.nextMilestone(after: 20) == 24)
        #expect(ProgressReport.nextMilestone(after: 24) == 36)
        #expect(ProgressReport.nextMilestone(after: 37) == 48)
        #expect(ProgressReport.nextMilestone(after: 48) == 60)
    }

    @Test func trendVerdictUsesTheDocumentedDeadband() {
        // Deadband 0.25 on the 0–3 shed scale: inside it is noise, at or beyond is a trend.
        #expect(ProgressReport.verdict(delta: -0.3, deadband: 0.25) == .improving)
        #expect(ProgressReport.verdict(delta: -0.25, deadband: 0.25) == .improving) // boundary counts
        #expect(ProgressReport.verdict(delta: -0.2, deadband: 0.25) == .stable)
        #expect(ProgressReport.verdict(delta: 0, deadband: 0.25) == .stable)
        #expect(ProgressReport.verdict(delta: 0.24, deadband: 0.25) == .stable)
        #expect(ProgressReport.verdict(delta: 0.25, deadband: 0.25) == .worsening)
        // Scalp uses its own deadband (1.0 on the 0–16 scale).
        #expect(ProgressReport.verdict(delta: -0.9, deadband: ProgressReport.scalpDeadband) == .stable)
        #expect(ProgressReport.verdict(delta: -1.2, deadband: ProgressReport.scalpDeadband) == .improving)
    }

    @Test func progressReportNeedsATreatmentOrEightWeeksOfEntries() {
        let cal = Calendar.current
        let now = Date.now
        // 3 weeks of entries, no active daily treatment → nothing to report on.
        let thin = (0..<21).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: now).map { DailyEntry(date: $0) }
        }
        #expect(ProgressReport.build(entries: thin, treatments: [], doses: [], labs: [],
                                     sideEffects: [], triggers: [], now: now) == nil)
        // ≥ 8 weeks of entries → a baseline report keyed to the first entry, no adherence.
        let long = (0..<63).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: now).map { DailyEntry(date: $0) }
        }
        let baseline = ProgressReport.build(entries: long, treatments: [], doses: [], labs: [],
                                            sideEffects: [], triggers: [], now: now)
        #expect(baseline?.weekNumber == 8)
        #expect(baseline?.treatment == nil)
        #expect(baseline?.adherence == nil)
        // An active daily treatment alone is enough, even before entries accumulate.
        let start = cal.date(byAdding: .day, value: -7, to: now)!
        let t = Treatment(treatmentClass: .minoxidil, startDate: start)
        #expect(ProgressReport.build(entries: [], treatments: [t], doses: [], labs: [],
                                     sideEffects: [], triggers: [], now: now) != nil)
    }

    @Test func weakestStretchFindsTheLapseOnlyBelowThreshold() throws {
        let cal = Calendar.current
        let now = Date.now
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -70, to: today)!
        // 2/day every day except a dead two weeks (offsets 28…41) → weakest window < 60%.
        var doses: [Date] = []
        for offset in 0...70 where !(28...41).contains(offset) {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            doses.append(day); doses.append(day)
        }
        let weak = try #require(ProgressReport.weakestStretch(
            doseDates: doses, expectedPerDay: 2, start: start, now: now, calendar: cal))
        #expect(weak.rate < 0.6)
        // A steady regimen (no lapse) reports no weak stretch at all.
        var steady: [Date] = []
        for offset in 0...70 {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            steady.append(day); steady.append(day)
        }
        #expect(ProgressReport.weakestStretch(
            doseDates: steady, expectedPerDay: 2, start: start, now: now, calendar: cal) == nil)
    }

    @Test func progressReportSynthesizesTheHonestRead() throws {
        let cal = Calendar.current
        let now = Date.now
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -140, to: today)!   // week 20 — pre-gate
        let minox = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil,
                              scheduleTimes: "08:00,21:00", startDate: start)
        var entries: [DailyEntry] = []
        var doses: [TreatmentDose] = []
        for offset in stride(from: 140, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            // Heavy shedding + inflamed scalp in the first half, settled in the second.
            entries.append(DailyEntry(
                date: day,
                shed: offset > 70 ? .heavy : .normal,
                flaking: offset > 70 ? 2 : 0,
                erythema: offset > 70 ? 2 : 0
            ))
            // Fully adherent except a dead fortnight (offsets 60…73).
            if !(60...73).contains(offset) {
                doses.append(TreatmentDose(treatment: minox, loggedAt: day, slot: "08:00"))
                doses.append(TreatmentDose(treatment: minox, loggedAt: day, slot: "21:00"))
            }
        }
        let report = try #require(ProgressReport.build(
            entries: entries, treatments: [minox], doses: doses,
            labs: [LabResult(test: .vitaminD, value: 24, collectedAt: start)],
            sideEffects: [SideEffectLog(treatment: minox, type: .scalpIrritation, severity: 2,
                                        date: cal.date(byAdding: .day, value: -9, to: today)!)],
            triggers: [], now: now
        ))

        #expect(report.weekNumber == 20)
        #expect(!report.isMilestoneWeek)
        #expect(report.nextMilestoneWeek == 24)
        #expect(report.treatmentTitle == "Minoxidil 5%")
        // Trajectories: 3 → 1 shed and 8 → 0 scalp both clear their deadbands.
        #expect(report.shedTrend?.verdict == .improving)
        #expect(report.scalpTrend?.verdict == .improving)
        // Adherence: 126 of 140 dosed days = 90%, with the dead fortnight surfaced.
        let adherence = try #require(report.adherence)
        #expect(abs(adherence.overall - 0.9) < 0.01)
        #expect(adherence.weakest != nil)
        // Tolerability and labs carried through.
        #expect(report.tolerability.moderate == 1)
        #expect(report.tolerability.hasSevere == false)
        #expect(report.labs.count == 1)
        #expect(report.labs.first?.isFlagged == true)   // vitamin D 24 < 30

        // The honest read: pre-24 framing, never a verdict on the treatment.
        #expect(report.honestRead.contains("Week 20 of 24"))
        #expect(report.honestRead.contains("too early to judge"))
        #expect(!report.honestRead.lowercased().contains("it's working"))
        #expect(!report.honestRead.lowercased().contains("stop taking"))

        // plainText carries the key numbers for sharing.
        let text = report.plainText()
        #expect(text.contains("WEEK 20 PROGRESS REPORT"))
        #expect(text.contains("Minoxidil 5%"))
        #expect(text.contains("90% of expected doses"))
        #expect(text.contains("3/3"))                    // first-4-weeks shed mean
        #expect(text.contains("1/3"))                    // last-4-weeks shed mean
        #expect(text.contains("improving"))
        #expect(text.contains("1 moderate"))
        #expect(text.contains("Vitamin D"))
        #expect(text.contains("Week 20 of 24"))
    }

    @Test func progressReportOpensTheWindowAtTwentyFourWeeks() throws {
        let cal = Calendar.current
        let now = Date.now
        let start = cal.date(byAdding: .day, value: -170, to: cal.startOfDay(for: now))!  // week 24+
        let minox = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, startDate: start)
        let report = try #require(ProgressReport.build(
            entries: [], treatments: [minox], doses: [], labs: [],
            sideEffects: [], triggers: [], now: now
        ))
        #expect(report.weekNumber == 24)
        #expect(report.isMilestoneWeek)
        #expect(report.honestRead.contains("the assessment window is open"))
        #expect(report.honestRead.contains("clinician"))
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

    @Test func chartRollingMeanSmoothsWithoutInventingData() {
        // Constant input → same constant (a flat signal stays flat).
        #expect(ChartMath.rollingMean([2, 2, 2, 2], window: 3) == [2, 2, 2, 2])
        // A spike is attenuated but not erased, and the length is preserved.
        let smoothed = ChartMath.rollingMean([0, 0, 6, 0, 0], window: 3)
        #expect(smoothed.count == 5)
        #expect(smoothed[2] < 6 && smoothed[2] > 0)   // (0+6+0)/3 = 2
        #expect(smoothed[2] == 2)
        // Centered: the spike bleeds symmetrically into both neighbors.
        #expect(smoothed[1] == 2 && smoothed[3] == 2)
        // Edges shrink the window to the array bounds instead of going blank.
        #expect(smoothed[0] == 0 && smoothed[4] == 0)
        // window ≤ 1 → identity; empty → empty.
        #expect(ChartMath.rollingMean([1, 3, 5], window: 1) == [1, 3, 5])
        #expect(ChartMath.rollingMean([], window: 7).isEmpty)
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

    // MARK: - Calendar-day bounds (one-entry-per-day upsert window)

    @Test func dayBoundsCoverTheWholeDayAndNothingMore() throws {
        let cal = Calendar.current
        let someAfternoon = try #require(cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14, minute: 37)))
        let bounds = HairAnalytics.dayBounds(for: someAfternoon, calendar: cal)

        // Lower bound is that day's midnight; the window is exactly one calendar day.
        #expect(bounds.lowerBound == cal.startOfDay(for: someAfternoon))
        #expect(bounds.upperBound == cal.date(byAdding: .day, value: 1, to: bounds.lowerBound))

        // 00:00:00 and 23:59:59 both belong to the day…
        #expect(bounds.contains(bounds.lowerBound))
        let lastSecond = try #require(cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 23, minute: 59, second: 59)))
        #expect(bounds.contains(lastSecond))

        // …but the next midnight and the previous day's last second do not.
        #expect(!bounds.contains(bounds.upperBound))
        let previousDay = try #require(cal.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 23, minute: 59, second: 59)))
        #expect(!bounds.contains(previousDay))
    }

    @Test func dayBoundsNormalizeAnyTimeOfDayToTheSameWindow() throws {
        let cal = Calendar.current
        let morning = try #require(cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 6)))
        let night = try #require(cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 23)))
        #expect(HairAnalytics.dayBounds(for: morning, calendar: cal) == HairAnalytics.dayBounds(for: night, calendar: cal))
    }

    @Test func normalizedLogDateKeepsClockTimeTodayAndUsesNoonForPastDays() throws {
        let cal = Calendar.current
        let now = Date.now

        // Today: keep the actual moment of logging.
        #expect(HairAnalytics.normalizedLogDate(for: now, now: now, calendar: cal) == now)

        // A backfilled day: pinned to noon of that day, stable inside the day window.
        let pastDay = try #require(cal.date(byAdding: .day, value: -10, to: now))
        let normalized = HairAnalytics.normalizedLogDate(for: pastDay, now: now, calendar: cal)
        #expect(cal.isDate(normalized, inSameDayAs: pastDay))
        #expect(cal.component(.hour, from: normalized) == 12)
        #expect(cal.component(.minute, from: normalized) == 0)
        #expect(HairAnalytics.dayBounds(for: pastDay, calendar: cal).contains(normalized))
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

    // MARK: - Gamification (effort-only XP, levels, badges)

    @Test func xpTotalFoldsTheDocumentedAwards() {
        let cal = Calendar.current
        let now = Date.now
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        // Two consecutive daily logs: 2 × 10, plus a streak bonus of +2 on day 2 of the run.
        let entries = [DailyEntry(date: yesterday), DailyEntry(date: now)]
        // Three doses today, but only 2 per day count: 2 × 3 = 6.
        let minox = Treatment(treatmentClass: .minoxidil)
        let doses = [
            TreatmentDose(treatment: minox, loggedAt: now, slot: "08:00"),
            TreatmentDose(treatment: minox, loggedAt: now, slot: "21:00"),
            TreatmentDose(treatment: minox, loggedAt: now, slot: "extra"),
        ]
        // Same region twice on one day counts once (15); a second region adds another 15.
        let photos = [
            PhotoRecord(region: .frontal, createdAt: now),
            PhotoRecord(region: .frontal, createdAt: now),
            PhotoRecord(region: .vertex, createdAt: now),
        ]
        let labs = [LabResult(test: .ferritin, value: 40, collectedAt: now)]
        let triggers = [TriggerEvent(type: .illness, date: yesterday)]
        let xp = XP.total(entries: entries, doses: doses, photos: photos,
                          labs: labs, triggers: triggers, now: now)
        // 20 logs + 2 streak + 6 doses + 30 photos + 20 lab + 5 trigger = 83.
        #expect(xp == 83)
    }

    @Test func xpNeverReadsHairOutcomes() {
        // The hard rule: a terrible hair day is worth exactly the same XP as a great one.
        let now = Date.now
        let goodDay = DailyEntry(date: now, shed: .minimal)
        let badDay = DailyEntry(date: now, shed: .heavy, flaking: 3, erythema: 3, itch: 3)
        let good = XP.total(entries: [goodDay], doses: [], photos: [], labs: [], triggers: [], now: now)
        let bad = XP.total(entries: [badDay], doses: [], photos: [], labs: [], triggers: [], now: now)
        #expect(good == bad)
    }

    @Test func levelLadderIsMonotonicAndMapsEdges() {
        let ladder = GamificationLevel.ladder
        for i in 1..<ladder.count {
            #expect(ladder[i].threshold > ladder[i - 1].threshold)   // strictly rising
            #expect(ladder[i].index == ladder[i - 1].index + 1)
        }
        #expect(GamificationLevel.level(for: 0).name == "Seed")
        #expect(GamificationLevel.level(for: 149).name == "Seed")
        #expect(GamificationLevel.level(for: 150).name == "Seedling")
        #expect(GamificationLevel.level(for: 5000).name == "Evergreen")
        #expect(GamificationLevel.level(for: 99_999).name == "Evergreen")

        // Halfway from Seedling (150) to Sprout (400).
        let mid = GamificationLevel.progressToNext(xp: 275)
        #expect(mid.next?.name == "Sprout")
        #expect(mid.remaining == 125)
        #expect(abs(mid.fraction - 0.5) < 0.001)
        // The top rung reads as complete, never as an unreachable next goal.
        let top = GamificationLevel.progressToNext(xp: 6000)
        #expect(top.next == nil)
        #expect(top.fraction == 1)
        #expect(top.remaining == 0)
    }

    @Test func achievementFirstLogAndStreakSeven() throws {
        let cal = Calendar.current
        let now = Date.now
        // Seven consecutive logged days ending today.
        let entries = (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: now).map { DailyEntry(date: $0) }
        }
        let first = Achievement.firstLog.earnedDate(
            entries: entries, treatments: [], doses: [], photos: [], labs: [], sideEffects: [], now: now)
        #expect(first == entries.map(\.date).min())

        let streak7 = try #require(Achievement.streak7.earnedDate(
            entries: entries, treatments: [], doses: [], photos: [], labs: [], sideEffects: [], now: now))
        #expect(cal.isDate(streak7, inSameDayAs: now))   // reached on the seventh day

        // Six consecutive days is not enough.
        #expect(Achievement.streak7.earnedDate(
            entries: Array(entries.dropFirst()), treatments: [], doses: [],
            photos: [], labs: [], sideEffects: [], now: now) == nil)
    }

    @Test func fullPhotoSetNeedsEveryRegion() throws {
        let cal = Calendar.current
        let now = Date.now
        var photos: [PhotoRecord] = []
        for (i, region) in PhotoRegion.allCases.dropLast().enumerated() {
            photos.append(PhotoRecord(region: region, createdAt: cal.date(byAdding: .day, value: -7 - i, to: now)!))
        }
        // One region still missing → not earned.
        #expect(Achievement.fullPhotoSet.earnedDate(
            entries: [], treatments: [], doses: [], photos: photos, labs: [], sideEffects: [], now: now) == nil)
        // The final region completes the set — earned on the completing photo's date.
        let completion = cal.date(byAdding: .day, value: -1, to: now)!
        photos.append(PhotoRecord(region: PhotoRegion.allCases.last!, createdAt: completion))
        let earned = try #require(Achievement.fullPhotoSet.earnedDate(
            entries: [], treatments: [], doses: [], photos: photos, labs: [], sideEffects: [], now: now))
        #expect(earned == completion)
    }

    @Test func adherenceBadgeIsNilSafeAndEarnable() throws {
        let cal = Calendar.current
        let now = Date.now
        // No treatments → the badge simply doesn't apply (never shown as "failed").
        #expect(Achievement.adherence4w90.earnedDate(
            entries: [], treatments: [], doses: [], photos: [], labs: [], sideEffects: [], now: now) == nil)
        // A periodic treatment has no daily expectation → still nil.
        let prp = Treatment(treatmentClass: .prp, startDate: cal.date(byAdding: .day, value: -60, to: now)!)
        #expect(Achievement.adherence4w90.earnedDate(
            entries: [], treatments: [prp], doses: [], photos: [], labs: [], sideEffects: [], now: now) == nil)
        // 28 fully-logged days of a once-daily treatment earn it at the window's end.
        let start = cal.date(byAdding: .day, value: -27, to: cal.startOfDay(for: now))!
        let fin = Treatment(treatmentClass: .finasteride, startDate: start)
        let doses = (0..<28).map { offset in
            TreatmentDose(treatment: fin, loggedAt: cal.date(byAdding: .day, value: offset, to: start)!, slot: "21:00")
        }
        let earned = try #require(Achievement.adherence4w90.earnedDate(
            entries: [], treatments: [fin], doses: doses, photos: [], labs: [], sideEffects: [], now: now))
        #expect(cal.isDate(earned, inSameDayAs: now))
    }

    // MARK: - Onboarding physics (falling-hair simulation)

    @Test func simIntensityScalesSpawnGravityAndSway() {
        // The shedding answer literally drives the simulation: heavier → faster, denser, wider swing.
        #expect(HairSim.spawnRate(0) == 1.1)
        #expect(HairSim.gravity(0) == 620)
        #expect(HairSim.sway(0) == 46)
        #expect(HairSim.spawnRate(1) > HairSim.spawnRate(0))
        #expect(HairSim.gravity(1) > HairSim.gravity(0))
        #expect(HairSim.sway(1) > HairSim.sway(0))
    }

    @Test func sheddingSceneMakesEachStatusVisuallyDistinctWithoutClaimingACount() {
        let minimal = SheddingSceneProfile.make(intensity: 0)
        let normal = SheddingSceneProfile.make(intensity: 1.0 / 3.0)
        let elevated = SheddingSceneProfile.make(intensity: 2.0 / 3.0)
        let heavy = SheddingSceneProfile.make(intensity: 1)

        #expect(minimal.band == 0)
        #expect(normal.band == 1)
        #expect(elevated.band == 2)
        #expect(heavy.band == 3)
        #expect(minimal.displayIntensity < normal.displayIntensity)
        #expect(normal.displayIntensity < elevated.displayIntensity)
        #expect(elevated.displayIntensity < heavy.displayIntensity)
        #expect(minimal.restingStrandCount < normal.restingStrandCount)
        #expect(normal.restingStrandCount < elevated.restingStrandCount)
        #expect(elevated.restingStrandCount < heavy.restingStrandCount)
        #expect(minimal.clusterCount == 0)
        #expect(normal.clusterCount == 0)
        #expect(elevated.clusterCount == 1)
        #expect(heavy.clusterCount == 2)
        #expect(minimal.washOpacity < heavy.washOpacity)
    }

    @Test func proceduralMotionUsesBoundedFrameBudgets() {
        #expect(abs(MotionCadence.interactive.minimumInterval - 1.0 / 60.0) < 0.000_001)
        #expect(abs(MotionCadence.ambient.minimumInterval - 1.0 / 30.0) < 0.000_001)
        #expect(abs(MotionCadence.decorative.minimumInterval - 1.0 / 15.0) < 0.000_001)
        #expect(MotionCadence.ambient.minimumInterval > MotionCadence.interactive.minimumInterval)
        #expect(MotionCadence.decorative.minimumInterval > MotionCadence.ambient.minimumInterval)
    }

    @Test func simSpawnsStrandsAndNeverExceedsMax() {
        var sim = HairSim()
        sim.size = CGSize(width: 200, height: 1_000_000)  // far taller than anything falls in this window
        for i in 0..<120 { sim.step(dt: 0.1, time: CGFloat(i) * 0.1, intensity: 1.0, rand: { 0.5 }) }
        #expect(!sim.strands.isEmpty)
        #expect(sim.strands.count <= HairSim.maxStrands)   // the hard invariant: never overflows the cap
        #expect(sim.strands.count == HairSim.maxStrands)   // 120 steps × ~2.31 spawns saturates it
    }

    @Test func simDoesNothingUntilItHasSize() {
        var sim = HairSim()
        sim.step(dt: 0.1, time: 0, intensity: 1.0, rand: { 0.5 })
        #expect(sim.strands.isEmpty)
    }

    @Test func integratePullsEveryPointDownward() {
        // rand 0.5 makes a perfectly vertical, evenly spaced strand, so uniform gravity translates it
        // straight down with no constraint correction — each point's y must increase.
        var s = HairSim.makeStrand(size: CGSize(width: 100, height: 100), rand: { 0.5 })
        let before = s.p.map(\.y)
        HairSim.integrate(&s, dt: 0.1, time: 0, g: 1000, swayA: 0)
        for (i, pt) in s.p.enumerated() { #expect(pt.y > before[i]) }
    }

    @Test func sheddingDialMapsIntensityToShedLevel() {
        #expect(SheddingDial.band(0.0) == 0)
        #expect(SheddingDial.band(1.0) == 3)
        #expect(SheddingDial.band(0.34) == 1)              // 0.34*3 = 1.02 → rounds to 1
        #expect(SheddingDial.shedLevel(0.0) == .minimal)
        #expect(SheddingDial.shedLevel(1.0) == .heavy)
    }

    // MARK: - Common-regimen dose presets

    @Test func everyClassExceptOtherHasADosePreset() {
        for c in TreatmentClass.allCases {
            let presets = TreatmentGuide.presets(for: c)
            if c == .other {
                #expect(presets.isEmpty)   // nothing honest to suggest for an unknown treatment
            } else {
                #expect(!presets.isEmpty)
            }
        }
        // Minoxidil offers both routes, in the documented order.
        #expect(TreatmentGuide.presets(for: .minoxidil).map(\.label) == ["Topical 5%", "Oral low-dose"])
    }

    @Test func dosePresetSchedulesParseThroughTreatmentSlots() {
        for c in TreatmentClass.allCases {
            for p in TreatmentGuide.presets(for: c) {
                let t = Treatment(name: p.name, treatmentClass: c, dose: p.dose, scheduleTimes: p.scheduleTimes)
                if c.isDaily {
                    // Daily classes: explicit non-empty slots that land in real time blocks.
                    #expect(!p.scheduleTimes.isEmpty)
                    #expect(!t.slots.isEmpty)
                    #expect(t.slots == p.slots)
                    for slot in t.slots { #expect(RoutineBlock.block(for: slot) != .periodic) }
                } else {
                    // Periodic classes: empty schedule → the Periodic block, no daily-adherence math.
                    #expect(p.scheduleTimes.isEmpty)
                    #expect(t.slots.isEmpty)
                }
                // Every preset carries the honest one-line caveat.
                #expect(!p.note.isEmpty)
            }
        }
    }

    // MARK: - Science products → plan ("Add to plan")

    @Test func addToPlanMapsToAnEditableOtherTreatment() throws {
        let rosemary = try #require(ScienceCatalog["rosemary"])
        let t = rosemary.makePlanTreatment()
        #expect(t.treatmentClass == .other)          // a supplement is never dressed up as a drug
        #expect(t.name == rosemary.name)
        #expect(t.dose == rosemary.suggestedDose)
        #expect(t.scheduleTimes == rosemary.suggestedSchedule)
        #expect(t.isActive)
    }

    @Test func addToPlanNameGuardPreventsDuplicates() throws {
        let rosemary = try #require(ScienceCatalog["rosemary"])
        var activeNames: [String] = []
        #expect(!rosemary.isInPlan(activeTreatmentNames: activeNames))     // first tap inserts
        activeNames.append(rosemary.makePlanTreatment().name)
        #expect(rosemary.isInPlan(activeTreatmentNames: activeNames))      // second tap is a no-op
        // The match is case- and whitespace-insensitive, so a lightly edited name still counts…
        #expect(rosemary.isInPlan(activeTreatmentNames: ["  ROSEMARY OIL "]))
        // …but a different product is not blocked.
        let keto = try #require(ScienceCatalog["ketoconazole"])
        #expect(!keto.isInPlan(activeTreatmentNames: activeNames))
    }

    @Test func everyProductScheduleParsesThroughTreatmentSlots() {
        for product in ScienceCatalog.products {
            #expect(!product.suggestedDose.isEmpty)
            let t = product.makePlanTreatment()
            if product.suggestedSchedule.isEmpty {
                #expect(t.slots.isEmpty)   // periodic: Periodic block, no false adherence math
            } else {
                #expect(!t.slots.isEmpty)
                for slot in t.slots { #expect(RoutineBlock.block(for: slot) != .periodic) }
            }
        }
    }

    @Test func otherClassDailyTreatmentCountsInAdherence() throws {
        // The slots-based expected-per-day is what lets an added product accrue adherence.
        let t = Treatment(name: "Rosemary oil", treatmentClass: .other, scheduleTimes: "21:00")
        #expect(t.slots == ["21:00"])
        let cal = Calendar.current
        let dates = (0..<14).compactMap { cal.date(byAdding: .day, value: -$0, to: .now) }
        let pct = try #require(HairAnalytics.adherence(
            doseDates: dates, expectedPerDay: t.slots.count, windowDays: 14))
        #expect(abs(pct - 1.0) < 0.001)
    }
}
