import SwiftUI
import WidgetKit

enum HairCompassWidgetStore {
    static let appGroup = "group.harib.Hair-Compass-AI-5"
    static let snapshotKey = "dashboardSnapshot"
}

struct HairCompassWidgetSnapshot: Codable {
    let generatedAt: Date
    let routineHeadline: String
    let progressLabel: String
    let checkInLabel: String
    let completedCount: Int
    let totalCount: Int
    let upcomingTitles: [String]

    static let placeholder = HairCompassWidgetSnapshot(
        generatedAt: .now,
        routineHeadline: "2 actions waiting today",
        progressLabel: "1 of 3 complete",
        checkInLabel: "Last check-in yesterday",
        completedCount: 1,
        totalCount: 3,
        upcomingTitles: ["Topical minoxidil", "Scalp massage", "Weekly photo review"]
    )
}

struct HairCompassRoutineEntry: TimelineEntry {
    let date: Date
    let snapshot: HairCompassWidgetSnapshot
}

struct HairCompassRoutineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HairCompassRoutineEntry {
        HairCompassRoutineEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (HairCompassRoutineEntry) -> Void) {
        completion(HairCompassRoutineEntry(date: .now, snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HairCompassRoutineEntry>) -> Void) {
        let entry = HairCompassRoutineEntry(date: .now, snapshot: loadSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSnapshot() -> HairCompassWidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: HairCompassWidgetStore.appGroup),
              let data = defaults.data(forKey: HairCompassWidgetStore.snapshotKey),
              let snapshot = try? JSONDecoder().decode(HairCompassWidgetSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }
}

struct HairCompassCheckInWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: HairCompassRoutineProvider.Entry

    private var progressValue: Double {
        guard entry.snapshot.totalCount > 0 else { return 0 }
        return Double(entry.snapshot.completedCount) / Double(entry.snapshot.totalCount)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.24, blue: 0.27),
                    Color(red: 0.31, green: 0.44, blue: 0.47),
                    Color(red: 0.83, green: 0.88, blue: 0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 12) {
                header
                if family == .systemSmall {
                    smallContent
                } else {
                    mediumContent
                }
            }
            .padding(16)
        }
        .widgetURL(URL(string: "haircompass://routine"))
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hair Compass")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                Text("Today")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text(entry.date, style: .date)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.snapshot.routineHeadline)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.snapshot.progressLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                    Spacer()
                    Text("\(Int((progressValue * 100).rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                        Capsule()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: max(proxy.size.width * progressValue, progressValue > 0 ? 18 : 0))
                    }
                }
                .frame(height: 8)
            }

            Text(entry.snapshot.checkInLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)
        }
    }

    private var mediumContent: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.snapshot.routineHeadline)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Label(entry.snapshot.progressLabel, systemImage: "checklist.checked")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))

                Label(entry.snapshot.checkInLabel, systemImage: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("Next up")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))

                ForEach(entry.snapshot.upcomingTitles.prefix(3), id: \.self) { title in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.white.opacity(0.88))
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: 140, alignment: .leading)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct HairCompassCheckInWidget: Widget {
    let kind: String = "HairCompassCheckInWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HairCompassRoutineProvider()) { entry in
            HairCompassCheckInWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Routine Snapshot")
        .description("See today’s routine progress and the next actions to complete.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HairCompassCheckInWidgetBundle: WidgetBundle {
    var body: some Widget {
        HairCompassCheckInWidget()
    }
}
