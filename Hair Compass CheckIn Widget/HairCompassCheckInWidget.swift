import ActivityKit
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
              let data = defaults.data(forKey: HairCompassWidgetStore.snapshotKey) else {
            return WidgetSnapshotDecoder.decode(nil)
        }
        return WidgetSnapshotDecoder.decode(data)
    }
}

private enum WidgetSnapshotDecoder {
    static func decode(_ data: Data?) -> WidgetSnapshot {
        guard let data, let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }
}

private enum WidgetDeepLinkBuilder {
    static func url(for family: WidgetFamily) -> URL {
        switch family {
        case .systemSmall, .systemMedium:
            return URL(string: "haircompass://log")!
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return URL(string: "haircompass://lock")!
        default:
            return URL(string: "haircompass://")!
        }
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
        .widgetURL(WidgetDeepLinkBuilder.url(for: .systemSmall))
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
        .widgetURL(WidgetDeepLinkBuilder.url(for: .systemMedium))
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

/// accessoryCircular: a ring trimmed to today's check-in state (full when logged, empty when
/// not — no in-between, this isn't the Compass score) with a checkmark caption and the shielded
/// streak number centered. System tint colors the ring/text; no WidgetPalette here.
private struct AccessoryCircularWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Gauge(value: snapshot.hasLoggedToday ? 1.0 : 0.0, in: 0...1) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(snapshot.streakDays)")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetURL(WidgetDeepLinkBuilder.url(for: .accessoryCircular))
    }
}

/// accessoryRectangular: streak + today's status on one line, the next suggested plan step (or a
/// fallback) on a second. System tint handles color on the Lock Screen / StandBy — no
/// WidgetPalette colors here.
private struct AccessoryRectangularWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(streakStatusLine, systemImage: snapshot.hasLoggedToday ? "checkmark.circle.fill" : "flame.fill")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(nextActionLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .widgetURL(WidgetDeepLinkBuilder.url(for: .accessoryRectangular))
    }

    private var streakStatusLine: String {
        let day = "Day \(snapshot.streakDays)"
        return snapshot.hasLoggedToday ? "\(day) · Logged" : "\(day) · Not logged"
    }

    private var nextActionLine: String {
        if let next = snapshot.dueTitles.first { return "Next: \(next)" }
        return snapshot.hasLoggedToday ? "All steps done" : "Tap to check in"
    }
}

/// accessoryInline: a single Lock Screen text row — streak plus a terse check-in status.
private struct AccessoryInlineWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Label(inlineText, systemImage: snapshot.hasLoggedToday ? "checkmark.circle.fill" : "circle")
        .widgetURL(WidgetDeepLinkBuilder.url(for: .accessoryInline))
    }

    private var inlineText: String {
        let day = "Day \(snapshot.streakDays)"
        return snapshot.hasLoggedToday ? "\(day) · check-in done" : "\(day) · log today"
    }
}

// MARK: - Ritual Live Activity

/// SF Symbol per launch ritual (`RitualKind.rawValue` in the app target — kept as a plain String
/// here, see RitualActivityAttributes.swift). Falls back to a neutral glyph for any future kind
/// this copy of the widget doesn't know about yet, rather than failing to render.
private enum RitualGlyph {
    static func symbolName(for kind: String) -> String {
        switch kind {
        case "comb": return "comb.fill"
        case "knot": return "tornado"
        case "massage": return "water.waves"
        case "serum": return "drop.fill"
        default: return "sparkles"
        }
    }
}

/// A ring (progress trim of `state.progress`) with the ritual's glyph centered in it — the
/// "ritual glyph or progress ring" element reused across the banner, expanded leading region,
/// and compactLeading. `showsGlyph: false` renders just the ring for the space-starved minimal
/// presentation.
private struct RitualGlyphRing: View {
    let kind: String
    let progress: Double
    var size: CGFloat = 28
    var showsGlyph: Bool = true

    private var lineWidth: CGFloat { max(2, size / 9) }

    var body: some View {
        ZStack {
            Circle().stroke(WidgetPalette.copper.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.03, min(1, progress)))
                .stroke(WidgetPalette.copper, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsGlyph {
                Image(systemName: RitualGlyph.symbolName(for: kind))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(WidgetPalette.copper)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Countdown (for the fixed-duration comb/massage phases) or a plain progress bar (for the
/// interaction-paced knot/serum phases, which have no fixed end time) — used in the banner and
/// the Dynamic Island's expanded bottom region. `now` is captured once so the countdown range's
/// lower bound can never end up after its upper bound (which would trap `Text(timerInterval:)`)
/// if `endDate` is at or just past "now" by the time this renders.
private struct RitualProgressFooter: View {
    let state: RitualActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            if let endDate = state.endDate, endDate > now {
                Text(timerInterval: now...endDate, countsDown: true)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WidgetPalette.copper)
            }
            ProgressView(value: state.progress)
                .tint(WidgetPalette.copper)
        }
    }
}

/// compactTrailing: a short countdown while a fixed-duration phase is running, otherwise the
/// completion percentage. Same "now captured once" guard as `RitualProgressFooter`.
private struct RitualCompactTrailing: View {
    let state: RitualActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        if let endDate = state.endDate, endDate > now {
            Text(timerInterval: now...endDate, countsDown: true)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(WidgetPalette.copper)
                .frame(width: 34)
        } else {
            Text("\(Int((state.progress * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WidgetPalette.copper)
        }
    }
}

/// Lock Screen / banner presentation: ritual glyph ring, name + current step, and the
/// countdown-or-progress readout.
private struct RitualActivityBannerView: View {
    let attributes: RitualActivityAttributes
    let state: RitualActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            RitualGlyphRing(kind: attributes.ritualKind, progress: state.progress, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.ritualName)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.ink)
                Text(state.stepName)
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            RitualProgressFooter(state: state)
                .frame(width: 84)
        }
        .padding(16)
    }
}

/// Live Activity for a launch ritual (Feature/Ritual/RitualView.swift, app target) — started,
/// updated, and ended by Service/RitualActivityService.swift. See RitualActivityAttributes.swift
/// in this target for the required-identical-to-the-app-target contract.
struct RitualLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RitualActivityAttributes.self) { context in
            RitualActivityBannerView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(WidgetPalette.canvas)
                .activitySystemActionForegroundColor(WidgetPalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RitualGlyphRing(kind: context.attributes.ritualKind, progress: context.state.progress, size: 30)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.ritualName)
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(.primary)
                        Text(context.state.stepName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RitualProgressFooter(state: context.state)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                RitualGlyphRing(kind: context.attributes.ritualKind, progress: context.state.progress, size: 20)
            } compactTrailing: {
                RitualCompactTrailing(state: context.state)
            } minimal: {
                RitualGlyphRing(kind: context.attributes.ritualKind, progress: context.state.progress, size: 16, showsGlyph: false)
            }
            .widgetURL(URL(string: "haircompass://"))
            .keylineTint(WidgetPalette.copper)
        }
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
        case .accessoryInline:
            AccessoryInlineWidgetView(snapshot: entry.snapshot)
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
        .description("Your rings, streak, and a one-tap check-in — on the Home Screen and Lock Screen.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

@main
struct HairCompassCheckInWidgetBundle: WidgetBundle {
    var body: some Widget {
        HairCompassCheckInWidget()
        RitualLiveActivity()
    }
}
