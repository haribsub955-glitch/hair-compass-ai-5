import Foundation
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
