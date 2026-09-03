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
//
// KEEP IN SYNC — WidgetSnapshot is duplicated in
//   Service/WidgetBridge.swift  and
//   Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift
// Stored fields (Codable): generatedAt, hasLoggedToday, score, ringLog, ringCare, ringLens,
//   shedLabel, scalpLabel, streakDays, shieldsHeld, dueTitles. Change both together.
struct WidgetSnapshot: Codable, Equatable {
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

    enum CodingKeys: String, CodingKey {
        case generatedAt, hasLoggedToday, score, ringLog, ringCare, ringLens, shedLabel, scalpLabel,
             streakDays, shieldsHeld, dueTitles
    }

    static let placeholder = WidgetSnapshot(
        generatedAt: .now, hasLoggedToday: false, score: 0, ringLog: 0, ringCare: nil,
        ringLens: 0, shedLabel: "", scalpLabel: "", streakDays: 0, shieldsHeld: 0,
        dueTitles: []
    )
}

/// Pure decoding boundary shared in behavior with the widget provider. Missing App Group data
/// and malformed payloads are both ordinary first-run states, never fatal widget errors.
enum WidgetSnapshotDecoder {
    static func decode(_ data: Data?) -> WidgetSnapshot {
        guard let data, let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }
}

enum WidgetDeepLinkDestination: Equatable {
    case checkIn
    case normal
    case lock
}

enum WidgetDeepLinkSurface: CaseIterable {
    case systemSmall, systemMedium
    case accessoryCircular, accessoryRectangular, accessoryInline
    case liveActivity

    var destination: WidgetDeepLinkDestination {
        switch self {
        case .systemSmall, .systemMedium: return .checkIn
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return .lock
        case .liveActivity: return .normal
        }
    }

    var url: URL {
        switch destination {
        case .checkIn: return URL(string: "haircompass://log")!
        case .lock: return URL(string: "haircompass://lock")!
        case .normal: return URL(string: "haircompass://")!
        }
    }
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
/// actor; the result is a plain Codable value. The due list and its counts come straight from
/// `PlanAdherence.today` — the same engine Today itself reads — so the widget never disagrees
/// with the app on a treatment's start date, weekday schedule or pause.
enum WidgetSnapshotBuilder {
    @MainActor
    static func build(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord] = [],
        photos: [PhotoRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let plan = PlanAdherence.today(treatments: treatments, doses: doses, missed: missed,
                                       now: now, calendar: calendar)
        let due = plan.occurrences.filter(\.isOpen).map { occurrence -> String in
            let name = occurrence.treatment.name.isEmpty
                ? occurrence.treatment.treatmentClass.title : occurrence.treatment.name
            return occurrence.slot.isEmpty ? name : "\(name) · \(occurrence.slot)"
        }

        let hasLoggedToday = entries.contains { calendar.isDate($0.date, inSameDayAs: now) }
        let hasPhotoThisWeek = photos.contains {
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .weekOfYear)
        }
        let compass = CompassScore(
            hasLoggedToday: hasLoggedToday,
            medsDone: plan.completedCount,
            medsTotal: plan.occurrences.count,
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
