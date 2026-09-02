import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A Sendable snapshot of everything an insight needs. Built on the main actor from SwiftData
/// models, then handed to the engines — so the numbers always come from deterministic analytics,
/// never from a model.
struct InsightContext: Sendable {
    var conditionTitle: String
    var conditionShort: String
    var usesScalpScale: Bool
    var familyHistoryNotes: [String]
    var entryCount: Int
    var streak: Int
    var shedDirection: Double
    var latestShed: String?
    var scalpDirection: Double
    var latestScalpTotal: Int?
    var latestScalpBand: String?
    var sleepHours: Double?
    var hrvSDNN: Double?
    var rapidWeightLossPercent: Double?
    var tractionRisk: Bool
    var recentTrigger: TriggerNote?
    /// A recently stopped treatment reads like a trigger for insight purposes — post-stop
    /// shedding changes often lag by the same 2–3 months, so it deserves the same nudge.
    /// Never a suggestion to stop or restart anything, only context for what's already logged.
    var recentStop: TriggerNote?
    var treatments: [TreatmentSummary]
    /// Latest result per lab test — a lower-priority, honest note for the daily insight, never
    /// a diagnosis. Matches the deep-analysis/chat `AIContext`'s labs, which already carry this.
    var labs: [LabNote]
    /// Consolidated, deterministic "worth a clinician review" patterns (see
    /// `ClinicianReviewFlags`) — fed in ahead of everything else so both the rule-based
    /// paragraph and the on-device model prioritize them over routine trend commentary.
    var clinicianReviewFlags: [ClinicianReviewFlag]

    struct TriggerNote: Sendable { var title: String; var weeks: Int }
    struct TreatmentSummary: Sendable {
        var name: String
        var weeksElapsed: Int
        var outcomeReady: Bool
        var adherencePercent: Int?
    }
    struct LabNote: Sendable { var name: String; var flag: String; var value: Double; var unit: String }

    /// Build the context on the main actor from the current SwiftData state.
    @MainActor
    static func build(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        snapshots: [HealthSnapshot],
        triggers: [TriggerEvent],
        labs: [LabResult],
        profile: Profile?,
        progressCheckIns: [ProgressCheckIn] = [],
        sideEffects: [SideEffectLog] = []
    ) -> InsightContext {
        let sortedEntries = entries.sorted { $0.date < $1.date }
        let shedValues = sortedEntries.map { Double($0.shed.rawValue) }
        let scalpValues = sortedEntries.map { Double($0.scalpTotal) }
        let latest = sortedEntries.last
        let latestSnapshot = snapshots.max { $0.date < $1.date }

        let massSamples = snapshots.compactMap { s -> (date: Date, massKg: Double)? in
            guard let m = s.bodyMassKg else { return nil }
            return (s.date, m)
        }

        let treatmentSummaries: [TreatmentSummary] = treatments
            .filter { $0.isActive }
            .map { t in
                let weeks = HairAnalytics.weeksElapsed(since: t.startDate)
                let dates = doses.filter { $0.treatment?.persistentModelID == t.persistentModelID }.map(\.loggedAt)
                let adherence = HairAnalytics.adherence(doseDates: dates, expectedPerDay: t.slots.count)
                return TreatmentSummary(
                    name: t.name.isEmpty ? t.treatmentClass.title : t.name,
                    weeksElapsed: weeks,
                    outcomeReady: HairAnalytics.outcomeReady(weeksElapsed: weeks),
                    adherencePercent: adherence.map { Int(($0 * 100).rounded()) }
                )
            }

        var trigger: TriggerNote?
        if let t = triggers.max(by: { $0.date < $1.date }) {
            trigger = TriggerNote(title: t.type.title, weeks: t.weeksElapsed())
        }

        var stop: TriggerNote?
        if let stopped = treatments.filter({ $0.endDate != nil }).max(by: { $0.endDate! < $1.endDate! }),
           let endDate = stopped.endDate {
            let weeks = max(0, HairAnalytics.weeksElapsed(since: endDate))
            stop = TriggerNote(
                title: "Stopped \(stopped.name.isEmpty ? stopped.treatmentClass.title : stopped.name)",
                weeks: weeks
            )
        }

        // Latest LabResult per LabTest — never invented, only what's actually logged.
        // Iterate LabTest.allCases (not the dictionary) so the note order is deterministic.
        let latestPerTest = Dictionary(grouping: labs, by: \.test)
            .compactMapValues { results in results.max { $0.collectedAt < $1.collectedAt } }
        let labNotes: [LabNote] = LabTest.allCases.compactMap { test in
            guard let result = latestPerTest[test] else { return nil }
            let flagText: String
            switch result.flag {
            case .low: flagText = "below"
            case .normal: flagText = "in"
            case .high: flagText = "above"
            }
            return LabNote(name: test.title, flag: flagText, value: result.value, unit: test.unit)
        }

        let reviewFlags = ClinicianReviewFlags.evaluate(
            progressCheckIns: progressCheckIns, entries: entries, triggers: triggers, sideEffects: sideEffects
        )

        let condition = profile?.condition ?? .unsure
        return InsightContext(
            conditionTitle: condition.title,
            conditionShort: condition.shortLabel,
            usesScalpScale: condition.usesScalpScale,
            familyHistoryNotes: HairAnalytics.baselineRiskNotes(
                familyHistory: profile?.familyHistory ?? .none, condition: condition),
            entryCount: entries.count,
            streak: HairAnalytics.loggingStreak(entryDates: entries.map(\.date)),
            shedDirection: HairAnalytics.direction(shedValues),
            latestShed: latest?.shed.title,
            scalpDirection: HairAnalytics.direction(scalpValues),
            latestScalpTotal: latest.map(\.scalpTotal),
            latestScalpBand: latest.map(\.scalpBand.title),
            sleepHours: latestSnapshot?.sleepHours,
            hrvSDNN: latestSnapshot?.hrvSDNN,
            rapidWeightLossPercent: HairAnalytics.rapidWeightLossPercent(samples: massSamples),
            tractionRisk: profile?.hasTractionRisk ?? false,
            recentTrigger: trigger,
            recentStop: stop,
            treatments: treatmentSummaries,
            labs: labNotes,
            clinicianReviewFlags: reviewFlags
        )
    }
}

/// Plain-language `DailyInsight` and where it came from. Every insight carries a not-diagnosis
/// framing regardless of source.
struct DailyInsight {
    let text: String
    let source: Source
    enum Source { case rules, onDevice
        var label: String { self == .onDevice ? "On-device AI" : "Insight" }
    }
}

/// Deterministic core. `facts` is the grounding fed to the LLM; `paragraph` is the always-available
/// human insight and the fallback when no model is present. Numbers only ever originate here.
enum RuleBasedInsight {
    static func facts(_ c: InsightContext) -> String {
        var lines: [String] = []
        lines.append("Condition focus: \(c.conditionTitle).")
        // Clinician-review patterns lead the fact list — the LLM instructions ask it to
        // "explain and prioritize" the facts it's given, so putting these first is what makes
        // it actually prioritize them over routine trend commentary.
        if !c.clinicianReviewFlags.isEmpty {
            let flagText = c.clinicianReviewFlags.map(\.detail).joined(separator: " ")
            lines.append("Worth a clinician's review: \(flagText)")
        }
        lines.append("Daily logs recorded: \(c.entryCount); current streak \(c.streak) days.")
        if let shed = c.latestShed { lines.append("Latest shedding: \(shed); trend \(trend(c.shedDirection, invert: true)).") }
        if c.usesScalpScale, let total = c.latestScalpTotal, let band = c.latestScalpBand {
            lines.append("Scalp severity: \(total)/16 (\(band)); trend \(trend(c.scalpDirection, invert: true)).")
        }
        if let s = c.sleepHours { lines.append("Sleep (auto): \(s.formatted(.number.precision(.fractionLength(1)))) h.") }
        if let h = c.hrvSDNN { lines.append("HRV (auto, stress proxy only): \(Int(h.rounded())) ms.") }
        if let pct = c.rapidWeightLossPercent { lines.append("Body weight down ~\(Int(pct.rounded()))% recently (possible shedding trigger in 2–3 months).") }
        if c.tractionRisk { lines.append("Baseline notes tight styling/heat/chemical use (traction risk).") }
        if let t = c.recentTrigger { lines.append("Trigger logged: \(t.title), \(t.weeks) weeks ago.") }
        if let s = c.recentStop { lines.append("\(s.title), \(s.weeks) weeks ago.") }
        for t in c.treatments {
            let adherence = t.adherencePercent.map { " · \($0)% adherence" } ?? ""
            let gate = t.outcomeReady ? "past the 24-week judging point" : "week \(t.weeksElapsed) of 24 before efficacy can be judged"
            lines.append("Treatment \(t.name): \(gate)\(adherence).")
        }
        // Structured lab facts so the on-device model sees the same numbers the rule-based
        // path does — never invented, only what's actually been logged.
        if !c.labs.isEmpty {
            let labText = c.labs
                .map { "\($0.name) \(formattedLabValue($0.value)) \($0.unit) (\($0.flag) range)" }
                .joined(separator: ", ")
            lines.append("Recent labs: \(labText).")
        }
        return lines.joined(separator: "\n")
    }

    static func paragraph(_ c: InsightContext) -> String {
        var parts: [String] = []

        // A fired clinician-review pattern leads the paragraph — it outranks routine trend
        // commentary, but stays a plain observation, never advice to act.
        if let leadFlag = c.clinicianReviewFlags.first {
            parts.append(leadFlag.detail)
        }

        if c.entryCount < 3 {
            parts.append("Keep logging for a few more days — trends and a clearer readout appear once there's a short history to compare against.")
        } else {
            if c.usesScalpScale, let band = c.latestScalpBand {
                parts.append("Scalp severity is \(band.lowercased()) and \(trend(c.scalpDirection, invert: true)).")
            } else if let shed = c.latestShed {
                parts.append("Shedding is \(shed.lowercased()) and \(trend(c.shedDirection, invert: true)).")
            }
        }

        if let pending = c.treatments.first(where: { !$0.outcomeReady }) {
            parts.append("Judge \(pending.name) at 6 months, not sooner — you're at week \(pending.weeksElapsed) of 24.")
        } else if let ready = c.treatments.first(where: { $0.outcomeReady }) {
            parts.append("\(ready.name) has passed the 24-week mark, so its effect is now fair to judge.")
        }

        if let pct = c.rapidWeightLossPercent {
            parts.append("Weight is down about \(Int(pct.rounded()))% recently; rapid loss can trigger shedding around two to three months later.")
        }
        if let t = c.recentTrigger, t.weeks <= 20 {
            parts.append("\(t.title) \(t.weeks) weeks ago may still be echoing — diffuse shedding often lags a trigger by 2–3 months.")
        }
        if let s = c.recentStop, s.weeks <= 20 {
            parts.append("\(s.title) \(s.weeks) week\(s.weeks == 1 ? "" : "s") ago — shedding changes after stopping a treatment often lag by 2–3 months too.")
        }

        // Labs are an additional, lower-priority note — only added when something's actually
        // out of range, and always context, never a diagnosis.
        if let note = labNote(c.labs) {
            parts.append(note)
        }

        if parts.isEmpty { parts.append("Nothing stands out today. Consistent logging is what makes the trends trustworthy.") }
        return parts.joined(separator: " ")
    }

    private static func trend(_ direction: Double, invert: Bool) -> String {
        let improving = invert ? direction < -0.05 : direction > 0.05
        let worsening = invert ? direction > 0.05 : direction < -0.05
        if improving { return "improving" }
        if worsening { return "rising" }
        return "steady"
    }

    /// An honest, non-diagnostic lab note — surfaced only when a hair-relevant lab is actually
    /// out of range. Prioritizes a below-range ferritin, then any out-of-range thyroid result
    /// (TSH/Free T4). Never invents a lab that wasn't logged.
    private static func labNote(_ labs: [InsightContext.LabNote]) -> String? {
        if labs.contains(where: { $0.name == LabTest.ferritin.title && $0.flag == "below" }) {
            return "Ferritin is below the range often cited for hair — worth raising with a clinician."
        }
        if let thyroid = labs.first(where: {
            ($0.name == LabTest.tsh.title || $0.name == LabTest.freeT4.title) && $0.flag != "in"
        }) {
            return "\(thyroid.name) is \(thyroid.flag) range — thyroid results are worth discussing with a clinician, since they can affect hair."
        }
        return nil
    }

    private static func formattedLabValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// Hybrid entry point. Tries the private on-device model to explain and prioritize the deterministic
/// facts; falls back to the rule-based paragraph when Apple Intelligence isn't available.
enum InsightEngine {
    static let instructions = """
    You are a careful hair-health companion inside a documentation app — NOT a diagnostic tool. \
    You will receive a short list of already-computed facts about one person. Write 2–3 warm, plain \
    sentences that explain and prioritize those facts for them. Rules: never invent numbers or facts \
    beyond the list; never diagnose or name a condition they didn't state; only discuss whether a \
    treatment is 'working' if a treatment is past its 24-week judging point; frame everything as \
    record-keeping and honest uncertainty. No lists, no headings — just the sentences.
    """

    static func dailyInsight(for context: InsightContext) async -> DailyInsight {
        let facts = RuleBasedInsight.facts(context)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceInsight.isAvailable {
            if let text = await OnDeviceInsight.generate(facts: facts, instructions: instructions),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               AIOutputValidator.isSafe(
                    text, suppliedFacts: facts,
                    allTreatmentsOutcomeReady: context.treatments.allSatisfy(\.outcomeReady)
               ) {
                return DailyInsight(text: text, source: .onDevice)
            }
        }
        #endif
        return DailyInsight(text: RuleBasedInsight.paragraph(context), source: .rules)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
enum OnDeviceInsight {
    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default: return false
        }
    }

    static func generate(facts: String, instructions: String) async -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: break
        default: return nil
        }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: facts)
            return response.content
        } catch {
            return nil
        }
    }
}
#endif
