//
//  InsightLabsTests.swift
//  Hair Compass AI 5Tests
//
//  The Today daily insight (InsightEngine.swift) gained labs so it can reference a low
//  ferritin or an out-of-range thyroid result, matching the deep-analysis/chat AIContext,
//  which already carries labs. Covers: latest-per-test dedup, flag mapping, and that the
//  honest (never-diagnostic) lab note only appears when a relevant lab is actually out of range.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct InsightLabsTests {

    private let calendar = Calendar.current

    /// Fixed reference "now" so date arithmetic never straddles midnight.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    /// Enough logging history that `paragraph()` doesn't short-circuit on the "keep logging"
    /// branch (entryCount < 3), so the lab note has a chance to surface.
    private var baselineEntries: [DailyEntry] {
        (0..<5).map { DailyEntry(date: day(-$0), shed: .normal) }
    }

    // MARK: - context.labs: latest-per-test dedup + flag mapping

    @Test func labsCarryTheLatestResultPerTestWithMappedFlags() {
        let labs = [
            // Two ferritin draws — only the more recent (day -5, below range) should survive.
            LabResult(test: .ferritin, value: 45, collectedAt: day(-90)),   // in range, stale
            LabResult(test: .ferritin, value: 18, collectedAt: day(-5)),    // < 30 → below
            LabResult(test: .tsh, value: 2.1, collectedAt: day(-20)),       // in range
        ]
        let context = InsightContext.build(
            entries: baselineEntries, treatments: [], doses: [], snapshots: [],
            triggers: [], labs: labs, profile: nil)

        #expect(context.labs.count == 2)

        let ferritin = context.labs.first { $0.name == "Ferritin" }
        #expect(ferritin?.flag == "below")
        #expect(ferritin?.value == 18)
        #expect(ferritin?.unit == "ng/mL")

        let tsh = context.labs.first { $0.name == "TSH" }
        #expect(tsh?.flag == "in")
        #expect(tsh?.value == 2.1)
    }

    @Test func labsAreEmptyWhenNoneAreLogged() {
        let context = InsightContext.build(
            entries: baselineEntries, treatments: [], doses: [], snapshots: [],
            triggers: [], labs: [], profile: nil)
        #expect(context.labs.isEmpty)
    }

    @Test func aboveRangeFlagMapsCorrectly() {
        let labs = [LabResult(test: .vitaminD, value: 150, collectedAt: day(-3))]   // > 100 → above
        let context = InsightContext.build(
            entries: baselineEntries, treatments: [], doses: [], snapshots: [],
            triggers: [], labs: labs, profile: nil)
        #expect(context.labs.first?.flag == "above")
    }

    // MARK: - Rule-based paragraph: honest, non-diagnostic note

    @Test func belowRangeFerritinYieldsTheHonestLabNoteInTheParagraph() {
        let labs = [LabResult(test: .ferritin, value: 18, collectedAt: day(-5))]
        let context = InsightContext.build(
            entries: baselineEntries, treatments: [], doses: [], snapshots: [],
            triggers: [], labs: labs, profile: nil)

        let text = RuleBasedInsight.paragraph(context)
        #expect(text.contains("Ferritin is below the range"))
        #expect(text.contains("clinician"))
        // Never phrased as a diagnosis.
        #expect(!text.lowercased().contains("you have"))
        #expect(!text.lowercased().contains("diagnos"))
    }

    @Test func outOfRangeThyroidYieldsANoteWhenFerritinIsFine() {
        let labs = [
            LabResult(test: .ferritin, value: 80, collectedAt: day(-5)),   // in range
            LabResult(test: .tsh, value: 6.0, collectedAt: day(-4)),       // > 4.0 → above
        ]
        let context = InsightContext.build(
            entries: baselineEntries, treatments: [], doses: [], snapshots: [],
            triggers: [], labs: labs, profile: nil)

        let text = RuleBasedInsight.paragraph(context)
        #expect(text.contains("TSH"))
        #expect(text.contains("clinician"))
    }

    @Test func inRangeLabsNeverProduceANote() {
        let labs = [
            LabResult(test: .ferritin, value: 80, collectedAt: day(-5)),
            LabResult(test: .tsh, value: 2.0, collectedAt: day(-4)),
        ]
        let context = InsightContext.build(
            entries: baselineEntries, treatments: [], doses: [], snapshots: [],
            triggers: [], labs: labs, profile: nil)

        let text = RuleBasedInsight.paragraph(context)
        #expect(!text.contains("clinician"))
    }

    @Test func noLabsNeverInventsANote() {
        let context = InsightContext.build(
            entries: baselineEntries, treatments: [], doses: [], snapshots: [],
            triggers: [], labs: [], profile: nil)
        #expect(context.labs.isEmpty)

        let text = RuleBasedInsight.paragraph(context)
        #expect(!text.contains("clinician"))
        #expect(!text.contains("Ferritin"))
    }

    // MARK: - Prompt path (facts()): the on-device model sees the same lab facts

    @Test func factsIncludeARecentLabsLineWhenLabsExist() {
        let labs = [
            LabResult(test: .ferritin, value: 18, collectedAt: day(-5)),
            LabResult(test: .tsh, value: 2.1, collectedAt: day(-4)),
        ]
        let context = InsightContext.build(
            entries: baselineEntries, treatments: [], doses: [], snapshots: [],
            triggers: [], labs: labs, profile: nil)

        let facts = RuleBasedInsight.facts(context)
        #expect(facts.contains("Recent labs:"))
        #expect(facts.contains("Ferritin"))
        #expect(facts.contains("below range"))
        #expect(facts.contains("TSH"))
        #expect(facts.contains("in range"))
    }

    @Test func factsOmitTheLabsLineWhenNoneAreLogged() {
        let context = InsightContext.build(
            entries: baselineEntries, treatments: [], doses: [], snapshots: [],
            triggers: [], labs: [], profile: nil)
        #expect(!RuleBasedInsight.facts(context).contains("Recent labs:"))
    }
}
