import SwiftUI
import WidgetKit

// Keep this snapshot in sync with Service/WidgetBridge.swift in the app target — field-for-field,
// same key. The widget target compiles ONLY the files under this directory (no Clinical.swift,
// no CompassScore.swift, no SwiftData model types), so it gets plain Doubles/Strings from the
// snapshot and draws its own static copy of the ring recipe + palette below.
enum HairCompassWidgetStore {
    static let appGroup = "group.harib.Hair-Compass-AI-5"
    static let snapshotKey = "clinicalSnapshot.v2"
}

/// Snapshot v2 — the Compass Rings score, shielded streak, and today's remaining plan steps.
/// Duplicated verbatim from Service/WidgetBridge.swift in the app target.
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

    /// Bundled preview + first-run fallback: every ring at rest, nothing logged yet. Never
    /// reads as an error — see `isFreshInstall` below for the copy it drives.
    static let placeholder = WidgetSnapshot(
        generatedAt: .now,
        hasLoggedToday: false,
        score: 0,
        ringLog: 0,
        ringCare: nil,
        ringLens: 0,
        shedLabel: "",
        scalpLabel: "",
        streakDays: 0,
        shieldsHeld: 0,
        dueTitles: []
    )

    /// True for the bundled placeholder and any genuinely untouched install — the total
    /// absence of every countable signal. Drives the "day one" invitation copy instead of the
    /// terser everyday "not logged yet" line; never true once the user has logged, has a
    /// photo, has an active plan, or has any streak history.
    var isFreshInstall: Bool {
        !hasLoggedToday && score == 0 && streakDays == 0 && shieldsHeld == 0
            && dueTitles.isEmpty && shedLabel.isEmpty && scalpLabel.isEmpty
    }
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

// MARK: - Palette

/// A static copy of Design/Clinical.swift's palette — the widget target can't import the app
/// target's Clinical.swift, so these RGB values are copied verbatim from it (2026-07-11).
enum WidgetPalette {
    static let canvas = Color(red: 0.984, green: 0.965, blue: 0.937)    // #FBF6EF warm ivory
    static let surface = Color(red: 0.996, green: 0.988, blue: 0.976)   // #FEFCF9 warm card white
    static let ink = Color(red: 0.169, green: 0.129, blue: 0.102)       // #2B211A espresso
    static let secondary = Color(red: 0.478, green: 0.420, blue: 0.365) // #7A6B5D warm taupe
    static let tertiary = Color(red: 0.486, green: 0.427, blue: 0.373)  // #7C6D5F muted warm umber
    static let hairline = Color(red: 0.929, green: 0.882, blue: 0.827)  // #EDE1D3 soft warm tan
    static let copper = Color(red: 0.694, green: 0.349, blue: 0.180)    // #B1592E copper/terracotta
    static let gold = Color(red: 0.788, green: 0.631, blue: 0.353)      // #C9A15A antique gold
    static let sage = Color(red: 0.541, green: 0.616, blue: 0.482)      // #8A9D7B
}

// MARK: - Compass mini rings (static — no animation in widgets)

/// A static copy of the app's `CompassRingsView` drawing recipe (Feature/CompassRings.swift):
/// a faint track, a rounded-cap fill trimmed to the progress value, rotated to start at
/// 12 o'clock. No `withAnimation`/`.animation` — widgets render one still frame per refresh.
private struct CompassMiniRings: View {
    let ringLog: Double
    let ringCare: Double?
    let ringLens: Double
    var size: CGFloat

    private var strokeWidth: CGFloat { size / 9 }

    var body: some View {
        ZStack {
            ring(color: WidgetPalette.copper, diameter: size, progress: ringLog)
            ring(color: WidgetPalette.sage, diameter: size * 0.7, progress: ringCare)
            ring(color: WidgetPalette.gold, diameter: size * 0.4, progress: ringLens)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func ring(color: Color, diameter: CGFloat, progress: Double?) -> some View {
        ZStack {
            if let progress {
                let clamped = max(0, min(1, progress))
                Circle().stroke(color.opacity(0.15), lineWidth: strokeWidth)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                // No plan today: a quiet dotted hairline, matching the app's excluded-ring state.
                Circle()
                    .stroke(WidgetPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The copper flame streak + sage shield count, shared by the small and medium layouts.
private struct StreakChip: View {
    let streak: Int
    let shields: Int
    var body: some View {
        HStack(spacing: 6) {
            Label("\(streak)", systemImage: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetPalette.copper)
            if shields > 0 {
                Label("\(shields)", systemImage: "shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.sage)
            }
        }
    }
}

// MARK: - systemSmall

private struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("COMPASS")
                    .font(.system(size: 10, weight: .semibold).monospaced())
                    .tracking(1.2)
                    .foregroundStyle(WidgetPalette.secondary)
                Spacer(minLength: 4)
                StreakChip(streak: snapshot.streakDays, shields: snapshot.shieldsHeld)
            }

            Spacer(minLength: 0)

            ZStack {
                CompassMiniRings(ringLog: snapshot.ringLog, ringCare: snapshot.ringCare,
                                  ringLens: snapshot.ringLens, size: 64)
                Text("\(snapshot.score)")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.ink)
            }

            Spacer(minLength: 0)

            Text(bottomLine)
                .font(.system(size: 12, weight: snapshot.hasLoggedToday ? .regular : .semibold))
                .foregroundStyle(snapshot.hasLoggedToday ? WidgetPalette.secondary : WidgetPalette.copper)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .widgetURL(URL(string: "haircompass://log"))
        .containerBackground(WidgetPalette.canvas, for: .widget)
    }

    private var bottomLine: String {
        if snapshot.hasLoggedToday { return "\(snapshot.shedLabel) · \(snapshot.scalpLabel)" }
        return snapshot.isFreshInstall ? "Your compass is ready — tap to log day one" : "Tap to log today"
    }
}

// MARK: - systemMedium

private struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                CompassMiniRings(ringLog: snapshot.ringLog, ringCare: snapshot.ringCare,
                                  ringLens: snapshot.ringLens, size: 78)
                Text("\(snapshot.score)")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.ink)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if !severityLine.isEmpty {
                    Text(severityLine)
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetPalette.secondary)
                        .lineLimit(1)
                }

                StreakChip(streak: snapshot.streakDays, shields: snapshot.shieldsHeld)

                if !snapshot.dueTitles.isEmpty {
                    Divider().overlay(WidgetPalette.hairline)
                    ForEach(snapshot.dueTitles.prefix(2), id: \.self) { title in
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .font(.system(size: 9))
                                .foregroundStyle(WidgetPalette.copper)
                            Text(title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WidgetPalette.ink)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "haircompass://log"))
        .containerBackground(WidgetPalette.canvas, for: .widget)
    }

    private var headline: String {
        if !snapshot.hasLoggedToday {
            return snapshot.isFreshInstall ? "Your compass is ready — tap to log day one" : "Log today's check-in"
        }
        if snapshot.dueTitles.isEmpty { return "Logged — nice." }
        let remaining = snapshot.dueTitles.count
        return "\(remaining) step\(remaining == 1 ? "" : "s") left today"
    }

    private var severityLine: String {
        [snapshot.shedLabel, snapshot.scalpLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Accessory families (Lock Screen / StandBy)

private struct AccessoryCircularWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: Double(snapshot.score), in: 0...100) {
                Text("Compass")
            } currentValueLabel: {
                Text("\(snapshot.score)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
        .widgetURL(URL(string: "haircompass://log"))
    }
}

private struct AccessoryRectangularWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hair Compass")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(statusLine)
                .font(.system(size: 12))
                .lineLimit(1)
            Label("\(snapshot.streakDays)", systemImage: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
        }
        // System tint handles color on the Lock Screen / StandBy — no WidgetPalette colors here.
        .widgetURL(URL(string: "haircompass://log"))
    }

    private var statusLine: String {
        snapshot.hasLoggedToday ? "\(snapshot.shedLabel) · \(snapshot.scalpLabel)" : "Log today"
    }
}

// MARK: - Root view

struct HairCompassWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: HairCompassProvider.Entry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(snapshot: entry.snapshot)
        case .accessoryCircular:
            AccessoryCircularWidgetView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            AccessoryRectangularWidgetView(snapshot: entry.snapshot)
        default:
            SmallWidgetView(snapshot: entry.snapshot)
        }
    }
}

struct HairCompassCheckInWidget: Widget {
    let kind = "HairCompassCheckInWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HairCompassProvider()) { entry in
            HairCompassWidgetView(entry: entry)
        }
        .configurationDisplayName("Compass")
        .description("Your rings, streak, and a one-tap check-in.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct HairCompassCheckInWidgetBundle: WidgetBundle {
    var body: some Widget {
        HairCompassCheckInWidget()
    }
}
