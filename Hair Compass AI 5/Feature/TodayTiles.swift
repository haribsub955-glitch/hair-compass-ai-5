import SwiftUI

/// Apple-Weather-style Today components in the warm-gouache language: a living conditions hero
/// where today's shedding *is* the weather (the signature falling-hair sim is our rain), and a
/// grid of small glanceable tiles each carrying a live mini motif from LogMotifs.swift.

// MARK: - Conditions hero

/// Full-bleed living hero: canvas→surface wash, the falling-hair simulation as backdrop, and a
/// big serif band word as the "temperature". Greeting/date/streak stay small around it.
struct ConditionsHero: View {
    var shed: ShedLevel?
    var scalpTotal: Int?
    var scalpBand: SeverityBand?
    let greeting: String
    let streak: Int
    /// Optional gamification level name ("Sapling") appended to the streak chip — effort-only.
    var levelName: String? = nil
    var onOpenBaseline: () -> Void
    var onLog: () -> Void

    /// Same visual floor as ShedDialField's preview: a panel-sized sim at true 0 looks dead, so
    /// the *display* intensity is floored while the stored data stays honest. Unlogged days get
    /// the gentlest ambient drizzle.
    private var heroIntensity: CGFloat {
        let raw = CGFloat(shed?.rawValue ?? 0) / 3
        return 0.22 + raw * 0.78
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Clinical.canvas, Clinical.surface],
                           startPoint: .top, endPoint: .bottom)
            FallingHairView(intensity: heroIntensity)
                .allowsHitTesting(false)
            // Legibility scrim: soft at the top (greeting), stronger at the bottom (band word),
            // clear through the middle so the simulation stays the hero.
            LinearGradient(stops: [
                .init(color: Clinical.canvas.opacity(0.72), location: 0),
                .init(color: Clinical.canvas.opacity(0), location: 0.30),
                .init(color: Clinical.surface.opacity(0), location: 0.52),
                .init(color: Clinical.surface.opacity(0.88), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28,
                                          style: .continuous))
        .shadow(color: Clinical.cardShadow, radius: 14, y: 6)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                        .font(Clinical.eyebrow(10)).tracking(1.4).foregroundStyle(Clinical.secondary)
                    Text(greeting).font(Clinical.headline(20)).foregroundStyle(Clinical.ink)
                }
                Spacer()
                Button(action: onOpenBaseline) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Clinical.ink.opacity(0.85), Clinical.surface.opacity(0.9))
                }
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Today's shedding")
                if let shed {
                    Text(shed.title)
                        .font(Clinical.headline(56)).foregroundStyle(Clinical.ink)
                        .lineLimit(1).minimumScaleFactor(0.55)
                    HStack(spacing: 10) {
                        if let scalpTotal, let scalpBand {
                            Text("Scalp \(scalpTotal)/16 · \(scalpBand.title)")
                                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        }
                        streakChip
                    }
                } else {
                    Text("Not logged")
                        .font(Clinical.headline(48)).foregroundStyle(Clinical.tertiary)
                        .lineLimit(1).minimumScaleFactor(0.55)
                    HStack(spacing: 10) {
                        Button(action: onLog) {
                            Label("Log today", systemImage: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Clinical.surface)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Clinical.accent, in: Capsule())
                                .shadow(color: Clinical.accent.opacity(0.28), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        streakChip
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 20)
    }

    private var streakChip: some View {
        Label(
            levelName.map { "\(streak)-day streak · \($0)" } ?? "\(streak)-day streak",
            systemImage: "flame.fill"
        )
            .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Clinical.surface.opacity(0.85), in: Capsule())
            .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
    }
}

// MARK: - Glance tile

/// A small Weather-style tile: mono eyebrow, big tabular value, short caption, and a live mini
/// motif washed into the lower band at reduced opacity so the text always stays legible.
struct GlanceTile<Motif: View>: View {
    let title: String
    let value: String
    var caption: String? = nil
    var valueColor: Color = Clinical.ink
    var motifOpacity: Double = 0.5
    var motifHeight: CGFloat = 62
    @ViewBuilder var motif: Motif

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Clinical.eyebrow(10)).tracking(1.2)
                .foregroundStyle(Clinical.tertiary)
            Spacer(minLength: 10)
            Text(value)
                .font(Clinical.number(24))
                .foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 11)).foregroundStyle(Clinical.secondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background(alignment: .bottom) {
            motif
                .frame(height: motifHeight)
                .opacity(motifOpacity)
                .allowsHitTesting(false)
        }
        .background(Clinical.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
        .shadow(color: Clinical.cardShadow, radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)\(caption.map { ", \($0)" } ?? "")")
    }
}

// MARK: - Tile grid

/// The 2-column glanceable grid under the hero — every tile is real data, and tiles whose data
/// doesn't exist today (meds with no routine, no recent trigger) simply don't appear.
struct TodayTileGrid: View {
    var entry: DailyEntry?
    var sleepHours: Double?
    var medsDone: Int
    var medsTotal: Int
    var triggerWeeks: Int?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            scalpTile
            sleepTile
            stressTile
            oilTile
            if medsTotal > 0 { medsTile }
            if let triggerWeeks { triggerTile(weeks: triggerWeeks) }
        }
    }

    // Individual tiles — unlogged days show "—" in tertiary with the motif idling at zero.

    private var scalpTile: some View {
        let total = entry?.scalpTotal
        return GlanceTile(
            title: "Scalp",
            value: total.map { "\($0)/16" } ?? "—",
            caption: entry?.scalpBand.title ?? "Not logged",
            valueColor: entry.map { Clinical.bandColor($0.scalpBand) } ?? Clinical.tertiary
        ) {
            RednessMotif(intensity: CGFloat(total ?? 0) / 16)
        }
    }

    private var sleepTile: some View {
        let quality = entry?.sleepQuality
        let value: String
        let caption: String
        let intensity: CGFloat
        if let sleepHours {
            value = String(format: "%.1fh", sleepHours)
            caption = "Hours · from Health"
            intensity = min(1, max(0, CGFloat(sleepHours) / 8))
        } else if let quality {
            value = "\(quality)/5"
            caption = "Self-reported quality"
            intensity = CGFloat(quality - 1) / 4
        } else {
            value = "—"
            caption = "Not logged"
            intensity = 0
        }
        return GlanceTile(
            title: "Sleep",
            value: value,
            caption: caption,
            valueColor: (sleepHours != nil || quality != nil) ? Clinical.ink : Clinical.tertiary
        ) {
            SleepMotif(intensity: intensity)
        }
    }

    private var stressTile: some View {
        let stress = entry?.stress
        return GlanceTile(
            title: "Stress",
            value: stress.map { "\($0)/5" } ?? "—",
            caption: stress.map(Self.stressWord) ?? "Not logged",
            valueColor: stress == nil ? Clinical.tertiary : Clinical.ink
        ) {
            StressMotif(intensity: stress.map { CGFloat($0 - 1) / 4 } ?? 0)
        }
    }

    private var oilTile: some View {
        let oil = entry?.oiliness
        return GlanceTile(
            title: "Oil",
            value: oil.map { "\($0)/3" } ?? "—",
            caption: oil.map(Self.oilWord) ?? "Not logged",
            valueColor: oil == nil ? Clinical.tertiary : Clinical.ink
        ) {
            OilMotif(intensity: oil.map { CGFloat($0) / 3 } ?? 0)
        }
    }

    /// The copper adherence arc IS the visualization here — same ring language as CareView's coach.
    private var medsTile: some View {
        GlanceTile(
            title: "Meds",
            value: "\(medsDone)/\(medsTotal)",
            caption: medsDone >= medsTotal ? "Routine done" : "\(medsTotal - medsDone) left today",
            valueColor: medsDone >= medsTotal ? Clinical.positive : Clinical.ink,
            motifOpacity: 1
        ) {
            HStack {
                Spacer()
                MedsArcRing(done: medsDone, total: medsTotal)
                    .padding(.trailing, 14)
                    .padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// Telogen-effluvium watch: the bar spans a 16-week watch period with the 8–12 week
    /// expected-shedding window shaded — the fill shows where today sits.
    private func triggerTile(weeks: Int) -> some View {
        GlanceTile(
            title: "Trigger watch",
            value: "Wk \(weeks)",
            caption: "Shedding window 8–12 wk",
            valueColor: Clinical.warning,
            motifOpacity: 1
        ) {
            TriggerWindowBar(weeks: weeks)
        }
    }

    private static func stressWord(_ s: Int) -> String {
        switch s {
        case ...1: return "Very calm"
        case 2: return "Calm"
        case 3: return "Moderate"
        case 4: return "High"
        default: return "Very high"
        }
    }

    private static func oilWord(_ o: Int) -> String {
        switch o {
        case ...0: return "Balanced"
        case 1: return "Slightly oily"
        case 2: return "Oily"
        default: return "Very oily"
        }
    }
}

// MARK: - Tile accessories

/// Small copper progress arc, the same ring language as CareView's coach ring.
private struct MedsArcRing: View {
    let done: Int
    let total: Int

    var body: some View {
        let progress = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().stroke(Clinical.hairline, lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 42, height: 42)
    }
}

/// Thin TE-window bar: track = 16-week watch period, shaded band = the 8–12 week window where
/// trigger-driven shedding typically peaks, fill = weeks elapsed.
private struct TriggerWindowBar: View {
    let weeks: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Clinical.hairline)
                // Expected-shedding window (8–12 of 16 weeks).
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Clinical.warning.opacity(0.25))
                    .frame(width: w * 0.25)
                    .offset(x: w * 0.5)
                Capsule()
                    .fill(Clinical.warning.opacity(0.85))
                    .frame(width: max(5, w * min(1, CGFloat(weeks) / 16)))
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 14)
        .padding(.bottom, 7)   // an edge strip below the caption text — never through it
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
