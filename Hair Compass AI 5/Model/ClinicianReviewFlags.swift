import Foundation
import SwiftData

/// A single deterministic, conservative pattern worth showing a clinician — built only from data
/// the app already tracks. This NAMES A PATTERN, never a condition or a diagnosis; the app's
/// stance (docs/TrackingSpec.md) stays record-keeping and honest uncertainty throughout.
struct ClinicianReviewFlag: Identifiable, Equatable, Sendable {
    let id: String
    /// Short label for a card row, export bullet, or Learn-style summary.
    let title: String
    /// One clinician-readable sentence — reused verbatim by Trends, the export, and the daily insight.
    let detail: String
}

/// Computes `ClinicianReviewFlag`s from data the app already collects. Pure: plain model arrays
/// in, a value array out — no `ModelContext`, so every rule here is unit-testable in isolation.
/// Every threshold mirrors guidance the app already teaches elsewhere, consolidated instead of
/// left scattered:
/// - Scalp pain: the existing `ProgressCheckIn.scalpPain` red flag (previously surfaced only in
///   `TrendsView`'s monthly card and the export's per-check-in lines).
/// - The 6-month shedding window: `TreatmentRecommender`'s own telogen-effluvium teaching
///   ("persistent shedding beyond 6 months warrants a review"), visible only to TE-condition
///   users who open the recommender.
/// - Severity-3 side effects: the same predicate `CareView`'s quiet banner already uses.
/// - Two straight weeks of Heavy shedding: new, but conservative — a fixed, high bar (half the
///   trailing fortnight) rather than a single bad day.
enum ClinicianReviewFlags {
    /// Heavy-shed days at or above this count inside the trailing window are worth naming.
    static let heavyShedThreshold = 7
    static let heavyShedWindowDays = 14
    /// Mirrors `TreatmentRecommender`'s own "persistent shedding beyond 6 months warrants a review".
    static let staleTriggerWeeks = 26
    /// How far back the shed-direction check looks to judge "still rising" near a stale trigger.
    static let recentDirectionWindowDays = 60
    static let sideEffectWindowDays = 14

    static func evaluate(
        progressCheckIns: [ProgressCheckIn],
        entries: [DailyEntry],
        triggers: [TriggerEvent],
        sideEffects: [SideEffectLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ClinicianReviewFlag] {
        var flags: [ClinicianReviewFlag] = []

        // 1. Scalp pain from the most recent monthly check-in that reported it — already modeled
        //    as a genuine red flag (persistent pain can mean scarring alopecia). Surfaced however
        //    long ago it was reported, matching TrendsView's existing precedent for this field.
        if let pain = progressCheckIns.sorted(by: { $0.date < $1.date }).last(where: { $0.scalpPain }) {
            let note = pain.scalpPainNote.trimmingCharacters(in: .whitespacesAndNewlines)
            flags.append(ClinicianReviewFlag(
                id: "scalpPain",
                title: "Scalp pain reported",
                detail: "Scalp pain/tenderness was reported in a monthly check-in\(note.isEmpty ? "" : " (\(note))") — persistent pain can be a sign of scarring alopecia, worth a prompt review."
            ))
        }

        // 2. A severity-3 side effect logged recently — the same predicate Care's own quiet
        //    banner already uses, reused here so it also surfaces on Trends and in the export.
        if HairAnalytics.hasRecentSevereSideEffect(
            logs: sideEffects.map { ($0.severity, $0.date) },
            windowDays: sideEffectWindowDays, now: now, calendar: calendar
        ) {
            flags.append(ClinicianReviewFlag(
                id: "severeSideEffect",
                title: "Severe side effect logged",
                detail: "A severe side effect was logged in the last \(sideEffectWindowDays) days — worth discussing with your prescriber."
            ))
        }

        // 3. Shed logged Heavy on most days of the last two weeks — a sustained pattern, not one
        //    bad day.
        let shedWindowStart = calendar.date(
            byAdding: .day, value: -(heavyShedWindowDays - 1), to: calendar.startOfDay(for: now)
        ) ?? now
        let heavyDays = entries.filter { $0.date >= shedWindowStart && $0.shed == .heavy }.count
        if heavyDays >= heavyShedThreshold {
            flags.append(ClinicianReviewFlag(
                id: "heavyShed",
                title: "Heavy shedding most days",
                detail: "Shedding was logged Heavy on \(heavyDays) of the last \(heavyShedWindowDays) days."
            ))
        }

        // 4. A trigger old enough that telogen effluvium should have settled, while recent
        //    shedding is still trending up — mirrors `TreatmentRecommender`'s own teaching that
        //    shedding persisting beyond ~6 months warrants a review.
        let directionStart = calendar.date(byAdding: .day, value: -recentDirectionWindowDays, to: now) ?? now
        let recentShedValues = entries
            .filter { $0.date >= directionStart }
            .sorted { $0.date < $1.date }
            .map { Double($0.shed.rawValue) }
        let direction = HairAnalytics.direction(recentShedValues)
        if direction > 0.05,
           let stale = triggers
               .filter({ $0.weeksElapsed(now: now, calendar: calendar) > staleTriggerWeeks })
               .max(by: { $0.date < $1.date }) {
            let weeks = stale.weeksElapsed(now: now, calendar: calendar)
            flags.append(ClinicianReviewFlag(
                id: "staleTrigger",
                title: "Shedding beyond 6 months",
                detail: "\(stale.type.title) was \(weeks) weeks ago and recent shedding is still trending up — telogen effluvium usually settles within about 6 months."
            ))
        }

        return flags
    }
}
