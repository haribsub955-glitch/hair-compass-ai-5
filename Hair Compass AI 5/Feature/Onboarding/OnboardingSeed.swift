import Foundation

/// Pure builders for the data onboarding seeds on finish — kept free of SwiftUI/SwiftData
/// context so they are unit-testable.
enum OnboardingSeed {
    /// Day-one entry from the onboarding answers. `stress`/`sleepQuality` are 1–5,
    /// `oiliness`/`flaking`/`itch` are 0–3 bands; everything is clamped defensively.
    static func dayOneEntry(
        shedIntensity: CGFloat,
        oiliness: Int, flaking: Int, itch: Int,
        stress: Int, sleepQuality: Int,
        date: Date = .now
    ) -> DailyEntry {
        DailyEntry(
            date: date,
            shed: SheddingDial.shedLevel(shedIntensity),
            flaking: min(max(flaking, 0), 3),
            erythema: 0,
            itch: min(max(itch, 0), 3),
            sleepQuality: min(max(sleepQuality, 1), 5),
            stress: min(max(stress, 1), 5),
            oiliness: min(max(oiliness, 0), 3)
        )
    }

    /// One TriggerEvent per selected trigger, dated `date` with an onboarding note.
    static func triggerEvents(_ selected: Set<TriggerType>, date: Date = .now) -> [TriggerEvent] {
        selected.sorted { $0.rawValue < $1.rawValue }.map {
            TriggerEvent(type: $0, date: date, note: "Reported during onboarding — happened in the last 3 months.")
        }
    }
}
