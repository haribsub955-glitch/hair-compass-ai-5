import Foundation
import SwiftData
import WidgetKit

// Shared contract with the widget target. Keep this struct in sync with the copy in
// Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift.
enum WidgetStore {
    static let appGroup = "group.harib.Hair-Compass-AI-5"
    static let snapshotKey = "clinicalSnapshot"
    static let kind = "HairCompassCheckInWidget"
}

struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let headline: String        // e.g. "2 of 3 treatments logged"
    let severityLabel: String   // e.g. "Scalp: mild"
    let streakDays: Int
    let dueTitles: [String]
}

enum WidgetBridge {
    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: WidgetStore.appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WidgetStore.snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind)
    }
}

/// Builds the widget snapshot from live SwiftData — streak, today's remaining plan steps, and the
/// latest scalp/shedding readout. Runs on the main actor; the result is a plain Codable value.
enum WidgetSnapshotBuilder {
    @MainActor
    static func build(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
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

        let headline: String
        if totalCount == 0 {
            headline = entries.contains { calendar.isDate($0.date, inSameDayAs: now) } ? "Logged today" : "Log today's check-in"
        } else if doneCount >= totalCount {
            headline = "Routine done today"
        } else {
            headline = "\(totalCount - doneCount) step\(totalCount - doneCount == 1 ? "" : "s") left today"
        }

        let latest = entries.max { $0.date < $1.date }
        let severity: String = {
            guard let e = latest else { return "No entries yet" }
            return "Scalp: \(e.scalpBand.title.lowercased()) · shed \(e.shed.title.lowercased())"
        }()

        return WidgetSnapshot(
            generatedAt: now,
            headline: headline,
            severityLabel: severity,
            streakDays: HairAnalytics.loggingStreak(entryDates: entries.map(\.date), now: now, calendar: calendar),
            dueTitles: due
        )
    }
}
