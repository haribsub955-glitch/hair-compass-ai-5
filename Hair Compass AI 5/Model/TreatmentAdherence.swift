import Foundation
import SwiftData

/// Turns a treatment's discrete logged doses into a smooth daily "usage intensity" line —
/// the trailing `averagingDays`-day average doses/day — so consistent use reads against a
/// shedding trend. Pure + deterministic; doses matched to the treatment by persistentModelID.
enum TreatmentAdherence {
    static func dailyAverage(
        treatment: Treatment,
        doses: [TreatmentDose],
        window: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        averagingDays: Int = 14
    ) -> [(day: Date, value: Double)] {
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(window - 1), to: today) else { return [] }
        let startDay = max(cutoff, calendar.startOfDay(for: treatment.startDate))
        guard startDay <= today else { return [] }

        // Dose days for THIS treatment (start-of-day → count).
        var countByDay: [Date: Int] = [:]
        for d in doses where d.treatment?.persistentModelID == treatment.persistentModelID && d.loggedAt <= now {
            countByDay[calendar.startOfDay(for: d.loggedAt), default: 0] += 1
        }

        var out: [(day: Date, value: Double)] = []
        var day = startDay
        while day <= today {
            var total = 0
            for k in 0..<averagingDays {
                if let d = calendar.date(byAdding: .day, value: -k, to: day) { total += countByDay[d] ?? 0 }
            }
            out.append((day: day, value: Double(total) / Double(averagingDays)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }
}
