import Foundation
import SwiftData
import WidgetKit

// Shared contract with the widget target. Keep this struct in sync with the copy in
// Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift.
enum WidgetStore {
    static let appGroup = "group.harib.Hair-Compass-AI-5"
    static let snapshotKey = "clinicalSnapshot.v2"
    static let kind = "HairCompassCheckInWidget"
}

/// Snapshot v2 — the Compass Rings score, shielded streak, and today's remaining plan steps,
/// mirroring the Today tab's `CompassScore`/`HairAnalytics.shieldedStreak`. Duplicated
/// verbatim in the widget target (it cannot import the app target, and pulling in
/// CompassScore.swift/Clinical.swift would drag SwiftData model types into the extension) —
/// keep both copies field-for-field identical, including the key below.
struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let hasLoggedToday: Bool
    let score: Int          // Compass score 0–100 (CompassScore)
    let ringLog: Double     // 0…1
    let ringCare: Double?   // nil = no plan scheduled today
    let ringLens: Double    // 0…1
    let shedLabel: String   // latest entry's shed band ("Elevated"), "" if none
    let scalpLabel: String  // "Scalp mild", "" if none
    let streakDays: Int     // shielded streak
    let shieldsHeld: Int
    let dueTitles: [String] // remaining routine steps today
}

enum WidgetBridge {
    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: WidgetStore.appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WidgetStore.snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind)
    }
}

/// Builds the widget snapshot from live SwiftData — Compass rings/score, shielded streak,
/// today's remaining plan steps, and the latest scalp/shedding readout. Runs on the main
/// actor; the result is a plain Codable value.
enum WidgetSnapshotBuilder {
    @MainActor
    static func build(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        photos: [PhotoRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let active = treatments.filter { $0.isActive && !$0.slots.isEmpty }
        var due: [String] = []
        var doneCount = 0, totalCount = 0
        for t in active {
            for slot in t.slots {
                totalCount += 1
                let logged = doses.contains {
                    $0.treatment?.persistentModelID == t.persistentModelID
                        && $0.slot == slot && calendar.isDate($0.loggedAt, inSameDayAs: now)
                }
                if logged { doneCount += 1 }
                else { due.append("\(t.name.isEmpty ? t.treatmentClass.title : t.name) · \(slot)") }
            }
        }

        let hasLoggedToday = entries.contains { calendar.isDate($0.date, inSameDayAs: now) }
        let hasPhotoThisWeek = photos.contains {
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .weekOfYear)
        }
        let compass = CompassScore(
            hasLoggedToday: hasLoggedToday,
            medsDone: doneCount,
            medsTotal: totalCount,
            hasPhotoThisWeek: hasPhotoThisWeek
        )

        let latest = entries.max { $0.date < $1.date }
        let shedLabel = latest.map { $0.shed.title } ?? ""
        let scalpLabel = latest.map { "Scalp \($0.scalpBand.title.lowercased())" } ?? ""

        let shielded = HairAnalytics.shieldedStreak(entryDates: entries.map(\.date), now: now, calendar: calendar)

        return WidgetSnapshot(
            generatedAt: now,
            hasLoggedToday: hasLoggedToday,
            score: compass.score,
            ringLog: compass.log,
            ringCare: compass.care,
            ringLens: compass.lens,
            shedLabel: shedLabel,
            scalpLabel: scalpLabel,
            streakDays: shielded.streak,
            shieldsHeld: shielded.shieldsHeld,
            dueTitles: due
        )
    }
}
