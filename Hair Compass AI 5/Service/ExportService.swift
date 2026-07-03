import Foundation
import SwiftData

/// Builds two things to share: a plain-text summary a clinician can read at a glance, and a
/// machine-readable JSON of the raw records (the user's own data, portable off-device).
enum ExportService {

    // MARK: - Clinician summary (human-readable)

    @MainActor
    static func clinicianSummary(
        profile: Profile?,
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        labs: [LabResult],
        triggers: [TriggerEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        var out = "HAIR COMPASS — SUMMARY FOR YOUR CLINICIAN\n"
        out += "Generated \(now.formatted(.dateTime.year().month().day()))\n"
        out += "A self-tracked record for documentation, not a diagnosis.\n\n"

        // Baseline
        if let p = profile {
            out += "BASELINE\n"
            out += "• Focus: \(p.condition.title)\n"
            out += "• Sex / age: \(p.sex.title)\(p.ageBand.isEmpty ? "" : " · \(p.ageBand)")\n"
            out += "• Family history: \(p.familyHistory.title)\n"
            if !p.baselineStage.isEmpty { out += "• Baseline stage: \(p.baselineStage)\n" }
            var practices: [String] = []
            if p.wearsTightStyles { practices.append("tight styles") }
            if p.usesHeat { practices.append("heat") }
            if p.usesChemicalTreatments { practices.append("chemical treatment") }
            if !practices.isEmpty { out += "• Hair-care: \(practices.joined(separator: ", "))\n" }
            out += "\n"
        }

        // Recent signals (last 30 days)
        let cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let recent = entries.filter { $0.date >= cutoff }
        out += "RECENT SIGNALS (last 30 days, \(recent.count) logs)\n"
        if !recent.isEmpty {
            let sheds = recent.map { Double($0.shed.rawValue) }
            let scalps = recent.map { Double($0.scalpTotal) }
            out += "• Shedding avg: \(oneDecimal(HairAnalytics.mean(sheds)))/3 (trend \(trend(HairAnalytics.direction(recent.sorted { $0.date < $1.date }.map { Double($0.shed.rawValue) }))))\n"
            out += "• Scalp severity avg: \(oneDecimal(HairAnalytics.mean(scalps)))/16\n"
            out += "• Sleep quality avg: \(oneDecimal(HairAnalytics.mean(recent.map { Double($0.sleepQuality) })))/5\n"
            out += "• Stress avg: \(oneDecimal(HairAnalytics.mean(recent.map { Double($0.stress) })))/5\n"
            let cigs = recent.map { $0.cigarettes }.reduce(0, +)
            if cigs > 0 { out += "• Cigarettes (30d total): \(cigs)\n" }
        } else {
            out += "• No recent logs.\n"
        }
        out += "• Logging streak: \(HairAnalytics.loggingStreak(entryDates: entries.map(\.date))) days\n\n"

        // Treatments
        out += "TREATMENTS\n"
        if treatments.isEmpty {
            out += "• None recorded.\n"
        } else {
            for t in treatments {
                let weeks = HairAnalytics.weeksElapsed(since: t.startDate)
                let ready = HairAnalytics.outcomeReady(weeksElapsed: weeks) ? "assessable" : "pre-24-week"
                let dates = doses.filter { $0.treatment?.persistentModelID == t.persistentModelID }.map(\.loggedAt)
                let adh = HairAnalytics.adherence(doseDates: dates, expectedPerDay: t.treatmentClass.defaultDailyCount)
                let adhStr = adh.map { " · \(Int(($0 * 100).rounded()))% adherence" } ?? ""
                out += "• \(t.name.isEmpty ? t.treatmentClass.title : t.name): week \(weeks)/24 (\(ready))\(adhStr)\(t.isActive ? "" : " [inactive]")\n"
            }
        }
        out += "\n"

        // Labs
        if !labs.isEmpty {
            out += "LABS\n"
            for l in labs.sorted(by: { $0.collectedAt > $1.collectedAt }) {
                out += "• \(l.test.title): \(oneDecimal(l.value)) \(l.test.unit) [\(l.flag.title)] — \(l.collectedAt.formatted(.dateTime.year().month().day()))\n"
            }
            out += "\n"
        }

        // Triggers
        if !triggers.isEmpty {
            out += "TRIGGER EVENTS\n"
            for e in triggers.sorted(by: { $0.date > $1.date }) {
                out += "• \(e.type.title): \(e.date.formatted(.dateTime.year().month().day()))\(e.note.isEmpty ? "" : " — \(e.note)")\n"
            }
            out += "\n"
        }

        out += "Bring your progress photos and trend charts to the appointment for the full picture."
        return out
    }

    // MARK: - Data export (machine-readable)

    @MainActor
    static func dataJSON(
        entries: [DailyEntry],
        doses: [TreatmentDose],
        labs: [LabResult],
        triggers: [TriggerEvent],
        snapshots: [HealthSnapshot]
    ) -> Data? {
        let dto = ExportBundle(
            exportedAt: .now,
            dailyEntries: entries.map {
                .init(date: $0.date, shed: $0.shed.rawValue, flaking: $0.flaking, erythema: $0.erythema,
                      itch: $0.itch, sleepQuality: $0.sleepQuality, stress: $0.stress,
                      cigarettes: $0.cigarettes, alcohol: $0.alcoholDrinks, oiliness: $0.oiliness, note: $0.note)
            },
            treatmentDoses: doses.map { .init(treatment: $0.treatment?.name ?? "", slot: $0.slot, loggedAt: $0.loggedAt) },
            labs: labs.map { .init(test: $0.test.rawValue, value: $0.value, unit: $0.test.unit, collectedAt: $0.collectedAt) },
            triggers: triggers.map { .init(type: $0.type.rawValue, date: $0.date, note: $0.note) },
            healthSnapshots: snapshots.map {
                .init(date: $0.date, sleepHours: $0.sleepHours, hrvSDNN: $0.hrvSDNN, restingHR: $0.restingHR,
                      bodyMassKg: $0.bodyMassKg, bmi: $0.bmi, dietaryProteinG: $0.dietaryProteinG)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(dto)
    }

    private static func oneDecimal(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
    private static func trend(_ d: Double) -> String {
        d < -0.05 ? "improving" : (d > 0.05 ? "rising" : "steady")
    }
}

// Codable DTOs for the JSON export — decoupled from the SwiftData @Model types.
private struct ExportBundle: Codable {
    let exportedAt: Date
    let dailyEntries: [Entry]
    let treatmentDoses: [Dose]
    let labs: [Lab]
    let triggers: [Trigger]
    let healthSnapshots: [Snapshot]

    struct Entry: Codable {
        let date: Date; let shed: Int; let flaking: Int; let erythema: Int; let itch: Int
        let sleepQuality: Int; let stress: Int; let cigarettes: Int; let alcohol: Int; let oiliness: Int; let note: String
    }
    struct Dose: Codable { let treatment: String; let slot: String; let loggedAt: Date }
    struct Lab: Codable { let test: String; let value: Double; let unit: String; let collectedAt: Date }
    struct Trigger: Codable { let type: String; let date: Date; let note: String }
    struct Snapshot: Codable {
        let date: Date; let sleepHours: Double?; let hrvSDNN: Double?; let restingHR: Double?
        let bodyMassKg: Double?; let bmi: Double?; let dietaryProteinG: Double?
    }
}
