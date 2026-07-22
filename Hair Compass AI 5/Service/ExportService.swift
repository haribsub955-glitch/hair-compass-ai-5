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
        progressCheckIns: [ProgressCheckIn],
        sideEffects: [SideEffectLog] = [],
        procedures: [ProcedureAppointment] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        var out = "HAIR COMPASS — SUMMARY FOR YOUR CLINICIAN\n"
        out += "Generated \(now.formatted(.dateTime.year().month().day()))\n"
        out += "A self-tracked record for documentation, not a diagnosis.\n\n"

        // Patterns worth a clinician's attention — consolidated from data tracked throughout the
        // app (see ClinicianReviewFlags). One honest line naming the fired patterns, never a
        // diagnosis.
        let reviewFlags = ClinicianReviewFlags.evaluate(
            progressCheckIns: progressCheckIns, entries: entries, triggers: triggers,
            sideEffects: sideEffects, now: now, calendar: calendar
        )
        if !reviewFlags.isEmpty {
            out += "PATTERNS WORTH A CLINICIAN'S REVIEW (record-keeping, not a diagnosis): "
            out += reviewFlags.map(\.title).joined(separator: "; ") + ".\n\n"
        }

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
            // Wash days read heavier than dry days for reasons unrelated to a real change —
            // splitting the average keeps the headline number from quietly absorbing that.
            let washed = recent.filter(\.washedHair).map { Double($0.shed.rawValue) }
            let dry = recent.filter { !$0.washedHair }.map { Double($0.shed.rawValue) }
            if !washed.isEmpty && !dry.isEmpty {
                out += "  – wash-day avg \(oneDecimal(HairAnalytics.mean(washed)))/3 (\(washed.count) days) vs non-wash avg \(oneDecimal(HairAnalytics.mean(dry)))/3 (\(dry.count) days)\n"
            }
            out += "• Scalp severity avg: \(oneDecimal(HairAnalytics.mean(scalps)))/16\n"
            out += "• Sleep quality avg: \(oneDecimal(HairAnalytics.mean(recent.map { Double($0.sleepQuality) })))/5\n"
            out += "• Stress avg: \(oneDecimal(HairAnalytics.mean(recent.map { Double($0.stress) })))/5\n"
            let cigs = recent.map { $0.cigarettes }.reduce(0, +)
            if cigs > 0 { out += "• Cigarettes (30d total): \(cigs)\n" }
        } else {
            out += "• No recent logs.\n"
        }
        out += "• Logging streak: \(HairAnalytics.loggingStreak(entryDates: entries.map(\.date))) days\n\n"

        // Notes — free-text context the user wrote down ("switched shampoo", "started keto",
        // "post-illness") that the structured fields can't hold. Previously write-only: stored
        // on every DailyEntry but never surfaced anywhere except reopening that exact day, so the
        // dated context that later explains a trend inflection silently never reached a visit.
        // Capped to the last 90 days / 15 entries so it can't balloon the summary.
        let noteCutoff = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let notedEntries = entries
            .filter { $0.date >= noteCutoff && !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.date > $1.date }
        if !notedEntries.isEmpty {
            out += "NOTES (last 90 days)\n"
            for e in notedEntries.prefix(15) {
                out += "• \(e.date.formatted(.dateTime.year().month().day())): \(e.note)\n"
            }
            out += "\n"
        }

        // Treatments
        out += "TREATMENTS\n"
        if treatments.isEmpty {
            out += "• None recorded.\n"
        } else {
            for t in treatments {
                let weeks = HairAnalytics.weeksElapsed(since: t.startDate)
                let ready = HairAnalytics.outcomeReady(weeksElapsed: weeks) ? "assessable" : "pre-24-week"
                let dates = doses.filter { $0.treatment?.persistentModelID == t.persistentModelID }.map(\.loggedAt)
                let adh = HairAnalytics.adherence(doseDates: dates, expectedPerDay: t.slots.count)
                let adhStr = adh.map { " · \(Int(($0 * 100).rounded()))% adherence" } ?? ""
                // A stop date is one of the most clinically actionable things on this line —
                // shedding changes after discontinuing a treatment often lag by 2–3 months, the
                // same delay taught for triggers below.
                let stopStr: String
                if let end = t.endDate {
                    let stoppedWeeks = HairAnalytics.weeksElapsed(since: t.startDate, now: end)
                    stopStr = " · stopped \(end.formatted(.dateTime.year().month().day())) after \(stoppedWeeks) week\(stoppedWeeks == 1 ? "" : "s")"
                } else {
                    stopStr = t.isActive ? "" : " [inactive]"
                }
                out += "• \(t.name.isEmpty ? t.treatmentClass.title : t.name): week \(weeks)/24 (\(ready))\(adhStr)\(stopStr)\n"
            }
        }
        out += "\n"

        // Tolerability — dated, severity-banded side-effect logs. The single most clinically
        // actionable artifact in the whole export: a prescriber conversation starter, never a
        // recommendation to change anything.
        if !sideEffects.isEmpty {
            out += "TOLERABILITY (self-logged, for your prescriber conversation)\n"
            for s in sideEffects.sorted(by: { $0.date > $1.date }) {
                let band = SeverityBand(rawValue: min(max(s.severity, 1), 3) - 1)?.title ?? "Mild"
                let treatmentName = s.treatment.map { $0.name.isEmpty ? $0.treatmentClass.title : $0.name } ?? "Unspecified"
                out += "• \(treatmentName) — \(s.type.title) (\(band)) — \(s.date.formatted(.dateTime.year().month().day()))\(s.note.isEmpty ? "" : " — \(s.note)")\n"
            }
            out += "\n"
        }

        // Procedures — dated in-office work (PRP, microneedling, transplant, LLLT sessions)
        // that often explains a trend inflection a chart alone can't.
        if !procedures.isEmpty {
            out += "PROCEDURES\n"
            for p in procedures.sorted(by: { $0.date > $1.date }) {
                let status = p.isCompleted ? "completed" : (p.isUpcoming ? "upcoming" : "not completed")
                out += "• \(p.type.title) — \(p.date.formatted(.dateTime.year().month().day())) (\(status))\(p.note.isEmpty ? "" : " — \(p.note)")\n"
            }
            out += "\n"
        }

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

        // Progress check-ins — self-reported answers to the between-visit questions a
        // dermatologist asks (regrowth, density/shedding/hairline trend, scalp symptoms).
        if !progressCheckIns.isEmpty {
            out += "PROGRESS CHECK-INS (self-reported)\n"
            for c in progressCheckIns.sorted(by: { $0.date > $1.date }).prefix(3) {
                out += "\(c.date.formatted(.dateTime.year().month().day())):\n"
                for line in c.clinicianSummary() {
                    out += "  • \(line)\n"
                }
            }
            out += "\n"
        }

        out += "This plain-text summary doesn't include photos or charts — the Visit report (PDF) does, in one document."
        return out
    }

    // MARK: - Data export (machine-readable)

    @MainActor
    static func dataJSON(
        profile: Profile?,
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        labs: [LabResult],
        triggers: [TriggerEvent],
        progressCheckIns: [ProgressCheckIn],
        snapshots: [HealthSnapshot],
        sideEffects: [SideEffectLog] = [],
        procedures: [ProcedureAppointment] = []
    ) -> Data? {
        let dto = ExportBundle(
            exportedAt: .now,
            profile: profile.map {
                .init(sex: $0.sexRaw, ageBand: $0.ageBand, condition: $0.conditionRaw,
                      familyHistory: $0.familyHistoryRaw, baselineStage: $0.baselineStage,
                      wearsTightStyles: $0.wearsTightStyles, usesHeat: $0.usesHeat,
                      usesChemicalTreatments: $0.usesChemicalTreatments)
            },
            dailyEntries: entries.map {
                .init(date: $0.date, shed: $0.shed.rawValue, flaking: $0.flaking, erythema: $0.erythema,
                      itch: $0.itch, sleepQuality: $0.sleepQuality, stress: $0.stress,
                      cigarettes: $0.cigarettes, alcohol: $0.alcoholDrinks, oiliness: $0.oiliness,
                      washedHair: $0.washedHair, note: $0.note)
            },
            treatments: treatments.map {
                .init(name: $0.name.isEmpty ? $0.treatmentClass.title : $0.name, treatmentClass: $0.classRaw,
                      dose: $0.dose, startDate: $0.startDate, endDate: $0.endDate, isActive: $0.isActive)
            },
            treatmentDoses: doses.map { .init(treatment: $0.treatment?.name ?? "", slot: $0.slot, loggedAt: $0.loggedAt) },
            sideEffects: sideEffects.map {
                .init(treatment: $0.treatment.map { t in t.name.isEmpty ? t.treatmentClass.title : t.name } ?? "",
                      type: $0.typeRaw, severity: $0.severity, date: $0.date, note: $0.note)
            },
            procedures: procedures.map {
                .init(type: $0.typeRaw, date: $0.date, isCompleted: $0.isCompleted, note: $0.note)
            },
            labs: labs.map { .init(test: $0.test.rawValue, value: $0.value, unit: $0.test.unit, collectedAt: $0.collectedAt) },
            triggers: triggers.map { .init(type: $0.type.rawValue, date: $0.date, note: $0.note) },
            progressCheckIns: progressCheckIns.map {
                .init(date: $0.date, regrowth: $0.regrowthRaw, density: $0.densityRaw, shedding: $0.sheddingRaw,
                      hairline: $0.hairlineRaw, overall: $0.overallRaw, scalpPain: $0.scalpPain,
                      scalpPainNote: $0.scalpPainNote, note: $0.note)
            },
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
        v.formatted(.number.precision(.fractionLength(0...1)))
    }
    private static func trend(_ d: Double) -> String {
        d < -0.05 ? "improving" : (d > 0.05 ? "rising" : "steady")
    }
}

// Codable DTOs for the JSON export — decoupled from the SwiftData @Model types.
private struct ExportBundle: Codable {
    let exportedAt: Date
    let profile: ProfileDTO?
    let dailyEntries: [Entry]
    let treatments: [TreatmentDTO]
    let treatmentDoses: [Dose]
    let sideEffects: [SideEffect]
    let procedures: [Procedure]
    let labs: [Lab]
    let triggers: [Trigger]
    let progressCheckIns: [CheckIn]
    let healthSnapshots: [Snapshot]

    /// Baseline context — no name, so the portable backup doesn't carry a directly-identifying
    /// field beyond what's already implicit in being the user's own export.
    struct ProfileDTO: Codable {
        let sex: String; let ageBand: String; let condition: String; let familyHistory: String
        let baselineStage: String; let wearsTightStyles: Bool; let usesHeat: Bool; let usesChemicalTreatments: Bool
    }
    struct Entry: Codable {
        let date: Date; let shed: Int; let flaking: Int; let erythema: Int; let itch: Int
        let sleepQuality: Int; let stress: Int; let cigarettes: Int; let alcohol: Int; let oiliness: Int
        let washedHair: Bool; let note: String
    }
    struct TreatmentDTO: Codable {
        let name: String; let treatmentClass: String; let dose: String
        let startDate: Date; let endDate: Date?; let isActive: Bool
    }
    struct Dose: Codable { let treatment: String; let slot: String; let loggedAt: Date }
    struct SideEffect: Codable { let treatment: String; let type: String; let severity: Int; let date: Date; let note: String }
    struct Procedure: Codable { let type: String; let date: Date; let isCompleted: Bool; let note: String }
    struct Lab: Codable { let test: String; let value: Double; let unit: String; let collectedAt: Date }
    struct Trigger: Codable { let type: String; let date: Date; let note: String }
    /// Raw answer fields (the model's own `...Raw` ints) rather than resolved titles, matching
    /// how the rest of this JSON export favors machine-stable raw values over display strings.
    struct CheckIn: Codable {
        let date: Date; let regrowth: Int; let density: Int; let shedding: Int; let hairline: Int
        let overall: Int; let scalpPain: Bool; let scalpPainNote: String; let note: String
    }
    struct Snapshot: Codable {
        let date: Date; let sleepHours: Double?; let hrvSDNN: Double?; let restingHR: Double?
        let bodyMassKg: Double?; let bmi: Double?; let dietaryProteinG: Double?
    }
}
