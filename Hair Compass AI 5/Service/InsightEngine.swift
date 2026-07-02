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
    var treatments: [TreatmentSummary]

    struct TriggerNote: Sendable { var title: String; var weeks: Int }
    struct TreatmentSummary: Sendable {
        var name: String
        var weeksElapsed: Int
        var outcomeReady: Bool
        var adherencePercent: Int?
    }

    /// Build the context on the main actor from the current SwiftData state.
    @MainActor
    static func build(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        snapshots: [HealthSnapshot],
        triggers: [TriggerEvent],
        profile: Profile?
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
                let adherence = HairAnalytics.adherence(doseDates: dates, expectedPerDay: t.treatmentClass.defaultDailyCount)
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
            treatments: treatmentSummaries
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
        lines.append("Daily logs recorded: \(c.entryCount); current streak \(c.streak) days.")
        if let shed = c.latestShed { lines.append("Latest shedding: \(shed); trend \(trend(c.shedDirection, invert: true)).") }
        if c.usesScalpScale, let total = c.latestScalpTotal, let band = c.latestScalpBand {
            lines.append("Scalp severity: \(total)/16 (\(band)); trend \(trend(c.scalpDirection, invert: true)).")
        }
        if let s = c.sleepHours { lines.append(String(format: "Sleep (auto): %.1f h.", s)) }
        if let h = c.hrvSDNN { lines.append("HRV (auto, stress proxy only): \(Int(h.rounded())) ms.") }
        if let pct = c.rapidWeightLossPercent { lines.append("Body weight down ~\(Int(pct.rounded()))% recently (possible shedding trigger in 2–3 months).") }
        if c.tractionRisk { lines.append("Baseline notes tight styling/heat/chemical use (traction risk).") }
        if let t = c.recentTrigger { lines.append("Trigger logged: \(t.title), \(t.weeks) weeks ago.") }
        for t in c.treatments {
            let adherence = t.adherencePercent.map { " · \($0)% adherence" } ?? ""
            let gate = t.outcomeReady ? "past the 24-week judging point" : "week \(t.weeksElapsed) of 24 before efficacy can be judged"
            lines.append("Treatment \(t.name): \(gate)\(adherence).")
        }
        return lines.joined(separator: "\n")
    }

    static func paragraph(_ c: InsightContext) -> String {
        var parts: [String] = []

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
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
