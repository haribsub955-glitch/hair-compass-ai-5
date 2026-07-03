import SwiftUI
import WidgetKit

// Keep this snapshot in sync with Service/WidgetBridge.swift in the app target.
enum HairCompassWidgetStore {
    static let appGroup = "group.harib.Hair-Compass-AI-5"
    static let snapshotKey = "clinicalSnapshot"
}

struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let headline: String
    let severityLabel: String
    let streakDays: Int
    let dueTitles: [String]

    static let placeholder = WidgetSnapshot(
        generatedAt: .now,
        headline: "2 of 3 treatments logged",
        severityLabel: "Scalp: mild",
        streakDays: 6,
        dueTitles: ["Minoxidil · 21:00", "Finasteride · 21:00"]
    )
}

struct HairCompassEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct HairCompassProvider: TimelineProvider {
    func placeholder(in context: Context) -> HairCompassEntry {
        HairCompassEntry(date: .now, snapshot: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (HairCompassEntry) -> Void) {
        completion(HairCompassEntry(date: .now, snapshot: load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HairCompassEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [HairCompassEntry(date: .now, snapshot: load())], policy: .after(next)))
    }
    private func load() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: HairCompassWidgetStore.appGroup),
              let data = defaults.data(forKey: HairCompassWidgetStore.snapshotKey),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .placeholder
        }
        return snap
    }
}

struct HairCompassWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: HairCompassProvider.Entry

    // Warm & premium palette (mirrors Clinical in the app target).
    private let ink = Color(red: 0.169, green: 0.129, blue: 0.102)      // espresso
    private let secondary = Color(red: 0.478, green: 0.420, blue: 0.365) // warm taupe
    private let accent = Color(red: 0.694, green: 0.349, blue: 0.180)    // copper
    private let canvas = Color(red: 0.984, green: 0.965, blue: 0.937)    // warm ivory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HAIR COMPASS")
                    .font(.system(size: 10, weight: .semibold).monospaced())
                    .tracking(1.2)
                    .foregroundStyle(secondary)
                Spacer()
                Label("\(entry.snapshot.streakDays)", systemImage: "flame")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(entry.snapshot.headline)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(2)

            Text(entry.snapshot.severityLabel)
                .font(.system(size: 12))
                .foregroundStyle(secondary)

            if family != .systemSmall, !entry.snapshot.dueTitles.isEmpty {
                Divider()
                ForEach(entry.snapshot.dueTitles.prefix(2), id: \.self) { title in
                    HStack(spacing: 6) {
                        Image(systemName: "circle").font(.system(size: 9)).foregroundStyle(accent)
                        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "haircompass://today"))
        .containerBackground(canvas, for: .widget)
    }
}

struct HairCompassCheckInWidget: Widget {
    let kind = "HairCompassCheckInWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HairCompassProvider()) { entry in
            HairCompassWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Treatments due, scalp severity, and your logging streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HairCompassCheckInWidgetBundle: WidgetBundle {
    var body: some Widget {
        HairCompassCheckInWidget()
    }
}
