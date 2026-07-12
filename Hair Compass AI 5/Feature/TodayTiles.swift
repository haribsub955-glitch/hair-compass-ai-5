import SwiftUI
import UIKit

/// Apple-Weather-style Today components in the warm-gouache language: a living conditions hero
/// where today's shedding *is* the weather (the signature falling-hair sim is our rain), and a
/// grid of small glanceable tiles each carrying a live mini motif from LogMotifs.swift.

// MARK: - Conditions hero

/// Full-bleed living hero: canvas→surface wash, the falling-hair simulation as backdrop, and a
/// big serif band word as the "temperature". Greeting/date/streak stay small around it. The
/// scene doubles as a drag-to-set input when `onShedSet` is supplied (see `sceneLayer`).
struct ConditionsHero: View {
    var shed: ShedLevel?
    var scalpTotal: Int?
    var scalpBand: SeverityBand?
    var hasLoggedToday = false
    let greeting: String
    let streak: Int
    /// Streak shields currently held (0–2, Duolingo-style): a single-day logging gap consumes
    /// one instead of breaking the streak. Purely a display badge on the streak chip below.
    var shields: Int = 0
    /// Optional gamification level name ("Sapling") shown in the XP chip — effort-only.
    var levelName: String? = nil
    var onOpenBaseline: () -> Void
    var onLog: () -> Void
    /// Total XP — display only; this view never awards points, it only reflects them.
    var xp: Int
    /// Fraction (0…1) of the way to the next level (`GamificationLevel.progressToNext(xp:).fraction`).
    var levelProgress: Double
    /// Drag-to-set callback. When nil, the scene stays passive — no gesture, no accessibility
    /// adjustable action, no rail-chip affordance (used by previews and any non-interactive host).
    var onShedSet: ((ShedLevel) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Transient live value while a finger is on the scene — overrides the entry-driven
    /// intensity so the falling-hair simulation and band word track the drag in real time.
    /// Cleared on release, at which point the display falls back to `heroIntensity`, which by
    /// then reflects the just-saved value.
    @State private var dragIntensity: CGFloat?

    /// Raw categorical intensity. `SheddingStatusScene` owns the small visual floor and adds a
    /// deterministic resting collection, so the saved status feels identical to the one chosen
    /// in the log sheet without pretending to be an exact strand count.
    private var heroIntensity: CGFloat {
        CGFloat(shed?.rawValue ?? 0) / 3
    }

    /// What the scene and band word actually display: the live drag value while a finger is
    /// down, otherwise whatever today's entry says.
    private var displayIntensity: CGFloat {
        dragIntensity ?? heroIntensity
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Clinical.canvas, Clinical.surface],
                           startPoint: .top, endPoint: .bottom)
            sceneLayer
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
            if onShedSet != nil {
                // Decorative only — allowsHitTesting(false) so it never competes with the
                // scene's own drag gesture underneath it. Centered on the trailing edge of the
                // scene band (clear of both the greeting/avatar row above and the band-word/chip
                // row below) so it never collides with the 44pt avatar button.
                HStack(alignment: .center, spacing: 10) {
                    if shed == nil {
                        bandTickScale
                    }
                    dragRailChip
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 304, alignment: .topLeading)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28,
                                          style: .continuous))
        .shadow(color: Clinical.cardShadow, radius: 14, y: 6)
    }

    // MARK: - Scene (backdrop + drag-to-set)

    /// The falling-hair backdrop. Passive (`allowsHitTesting(false)`, no gesture) when
    /// `onShedSet` is nil. Otherwise this exact subview — which sits entirely inside the hero's
    /// own bounds at the very top of the page — is the drag-to-set surface: a vertical
    /// `DragGesture` attached only here, never to the outer hero container or the ScrollView, so
    /// page scrolling initiated anywhere else (i.e. almost the whole screen, since the hero is a
    /// fixed ~304pt band) is completely unaffected. See ConditionsHero doc + Task C5 in the plan.
    private var sceneLayer: some View {
        Group {
            if let onShedSet {
                GeometryReader { geo in
                    SheddingStatusScene(
                        intensity: displayIntensity,
                        showsCollection: dragIntensity != nil || shed != nil,
                        ambientWhenEmpty: true
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(height: geo.size.height, set: onShedSet))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today's shedding")
                .accessibilityValue(shed?.title ?? "Not logged")
                .accessibilityAdjustableAction { direction in
                    let current = shed?.rawValue ?? ShedLevel.normal.rawValue
                    switch direction {
                    case .increment: setBand(current + 1, set: onShedSet)
                    case .decrement: setBand(current - 1, set: onShedSet)
                    @unknown default: break
                    }
                }
            } else {
                SheddingStatusScene(intensity: displayIntensity, showsCollection: shed != nil)
                    .allowsHitTesting(false)
            }
        }
        // Keep motion out of the greeting/profile zone. The simulation becomes visible
        // below the header, so decorative strands never cross the user's name. (This is a
        // rendering-only mask — SwiftUI does not restrict hit-testing to the opaque region —
        // so the drag gesture above still recognizes touches anywhere in the full frame.)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.20),
                    .init(color: .black, location: 0.36),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func dragGesture(height: CGFloat, set: @escaping (ShedLevel) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard height > 0 else { return }
                let previousBand = SheddingDial.band(dragIntensity ?? heroIntensity)
                let clamped = min(1, max(0, 1 - value.location.y / height))
                dragIntensity = clamped
                if SheddingDial.band(clamped) != previousBand {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { value in
                let clamped = dragIntensity ?? min(1, max(0, 1 - value.location.y / height))
                set(SheddingDial.shedLevel(clamped))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dragIntensity = nil
            }
    }

    /// VoiceOver adjustable-action path — a discrete step rather than a continuous drag, mirrors
    /// `ShedDialField.setBand`'s band mutation (minus the local-state animation, since this view
    /// has no authoritative intensity of its own outside a live drag).
    private func setBand(_ band: Int, set: (ShedLevel) -> Void) {
        let clamped = min(3, max(0, band))
        guard let level = ShedLevel(rawValue: clamped) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        set(level)
    }

    /// Trailing vertical "drag rail" affordance — chevron/SET/chevron — so the gesture is
    /// discoverable. Mirrors ShedDialField's "Live portrait" chip styling.
    private var dragRailChip: some View {
        VStack(spacing: 5) {
            Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Clinical.accent)
            Text("SET").font(Clinical.eyebrow(9)).tracking(1.0)
                .foregroundStyle(Clinical.secondary)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Clinical.accent)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .background(Clinical.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
        .shadow(color: Clinical.cardShadow, radius: 6, y: 2)
        .accessibilityHidden(true)
    }

    /// Ghosted band-name ticks along the drag path, shown only before anything is logged so the
    /// void between the greeting and the headline reads as an intentional scale rather than
    /// empty space with a lone rail chip floating in it. Sits at a low, non-competing opacity —
    /// decorative only, same as the rail chip it sits beside — and brightens the row nearest a
    /// live drag so the scale doubles as feedback once a finger is down.
    private var bandTickScale: some View {
        VStack(alignment: .trailing, spacing: 13) {
            ForEach(ShedLevel.allCases.reversed()) { level in
                Text(level.title.uppercased())
                    .font(Clinical.eyebrow(8)).tracking(0.8)
                    .foregroundStyle(Clinical.ink)
                    .opacity(tickOpacity(for: level))
            }
        }
        .accessibilityHidden(true)
    }

    private func tickOpacity(for level: ShedLevel) -> Double {
        guard let dragIntensity else { return 0.30 }
        return SheddingDial.band(dragIntensity) == level.rawValue ? 0.85 : 0.18
    }

    /// Trailing space reserved on the headline so it never renders under `bandTickScale` +
    /// `dragRailChip`. Scaled through the same `UIFontMetrics` text style the ladder's own
    /// labels use, so the reservation grows with Dynamic Type roughly in step with what it's
    /// protecting against instead of a fixed constant that would fall short at larger sizes.
    private var ladderReservedInset: CGFloat {
        UIFontMetrics(forTextStyle: .caption2).scaledValue(for: 108)
    }

    // MARK: - Foreground content

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
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit profile and baseline")
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Today's shedding")
                if let shed, dragIntensity == nil {
                    let reflection = SheddingReflection.make(band: shed.rawValue)
                    bandWordText(shed.title)
                    subtitleText(reflection.detail)
                    scalpLine
                    chipRow
                } else if let dragIntensity {
                    // Live preview while the finger is down — same slot the saved band word
                    // occupies, so nothing reflows when the drag ends. Reserves the ladder's
                    // trailing column (it's on screen throughout the drag) so the band word
                    // never renders under it.
                    let caption = SheddingDial.bandCaption(dragIntensity)
                    bandWordText(caption.0)
                        .padding(.trailing, ladderReservedInset)
                    subtitleText(caption.1.prefix(1).uppercased() + caption.1.dropFirst())
                    scalpLine
                    chipRow
                } else {
                    // Reserves the same trailing column the tick ladder occupies (visible
                    // whenever nothing is logged) instead of overlaying it — a fixed single-line
                    // headline would otherwise span the full width and collide with the ladder's
                    // top label at large Dynamic Type sizes (round-3 fix). Wrapping to 2 lines
                    // replaces the old lineLimit(1)+aggressive minimumScaleFactor, which used to
                    // crush the whole headline down to stay on one line under the same pressure.
                    Text(onShedSet != nil ? "Not logged — drag to set" : "Not logged")
                        .font(Clinical.headline(44)).foregroundStyle(Clinical.tertiary)
                        .lineLimit(2).minimumScaleFactor(0.65)
                        .padding(.trailing, onShedSet != nil ? ladderReservedInset : 0)
                    chipRow
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 20)
    }

    /// Drives the band-word crossfade — the live drag band while dragging (so crossing a
    /// threshold mid-drag still gets ShedDialField's characteristic eased swap), otherwise the
    /// saved band. Mirrors ShedDialField's `previewPanel`, whose `.animation(value: band)` fires
    /// on both live drags and settled taps for the same reason.
    private var currentBand: Int {
        if let dragIntensity { return SheddingDial.band(dragIntensity) }
        return shed?.rawValue ?? -1
    }

    private func bandWordText(_ text: String) -> some View {
        Text(text)
            .font(Clinical.headline(50)).foregroundStyle(Clinical.ink)
            .lineLimit(1).minimumScaleFactor(0.55)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.25), value: currentBand)
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Clinical.secondary)
            .lineLimit(2)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.25), value: currentBand)
    }

    @ViewBuilder
    private var scalpLine: some View {
        if let scalpTotal, let scalpBand {
            Text("Scalp \(scalpTotal)/16 · \(scalpBand.title)")
                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            streakChip
            xpChip
            Spacer(minLength: 0)
            logButton
        }
    }

    private var logButton: some View {
        Button(action: onLog) {
            Label(hasLoggedToday ? "Edit log" : "Log today",
                  systemImage: hasLoggedToday ? "pencil" : "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Clinical.surface)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(Clinical.accent, in: Capsule())
                .shadow(color: Clinical.accent.opacity(0.24), radius: 8, y: 3)
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityHint(hasLoggedToday ? "Edits today's check-in" : "Opens today's check-in")
    }

    private var streakChip: some View {
        HStack(spacing: 5) {
            Label("\(streak)-day streak", systemImage: "flame.fill")
            if shields > 0 {
                Label("\(shields)", systemImage: "shield.fill")
                    .foregroundStyle(Clinical.sage)
            }
        }
        .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Clinical.surface.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            shields > 0
                ? "\(streak)-day streak, \(shields) streak shield\(shields == 1 ? "" : "s") held"
                : "\(streak)-day streak"
        )
    }

    /// Ring (progress to next level) + XP total + level name, all in one chip so the row stays
    /// to one line. `ViewThatFits` picks the fullest label ("1,623 XP · Sapling") that fits the
    /// available width and falls back to the number-only label ("1,623 XP") rather than letting
    /// the level name ellipsize into gibberish — the level name always stays in the
    /// accessibility label either way. `.numericText()` only wraps the number itself, so a
    /// level-up's longer name doesn't fight the digit-roll transition.
    private var xpChip: some View {
        HStack(spacing: 6) {
            XPProgressRing(progress: levelProgress)
            ViewThatFits(in: .horizontal) {
                xpLabel(showsLevel: true)
                xpLabel(showsLevel: false)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Clinical.surface.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(levelName.map { "\(xp) XP, \($0) level" } ?? "\(xp) XP")
    }

    private func xpLabel(showsLevel: Bool) -> some View {
        HStack(spacing: 2) {
            Text("\(xp)")
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: xp)
            Text("XP" + (showsLevel ? (levelName.map { " · \($0)" } ?? "") : ""))
        }
        .font(Clinical.eyebrow(10))
        .foregroundStyle(Clinical.accent)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Small copper progress ring — accent fill on an accentSoft track, same language as
/// `MedsArcRing` below but sized for an inline chip. Draws once with a spring on appear (instant
/// under Reduce Motion); later XP changes spring to the new fraction.
private struct XPProgressRing: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let clamped = max(0, min(1, progress))
        ZStack {
            Circle().stroke(Clinical.accentSoft, lineWidth: 3)
            Circle()
                .trim(from: 0, to: shown ? clamped : 0)
                .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: clamped)
        .onAppear {
            guard !shown else { return }
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { shown = true }
            }
        }
        .accessibilityHidden(true)
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
    /// Whisper of identity: a barely-there wash keyed to the tile's metric, settling toward the
    /// bottom edge like `Clinical.surfaceWash`. Peaks at 0.06 opacity — the tile must still read
    /// ivory; this is a whisper, not a paint job.
    var tint: Color? = nil
    var motifOpacity: Double = 0.38
    var motifHeight: CGFloat = 62
    /// When true and the tile is in its not-logged state (`value == "—"`), the value/caption
    /// block centers vertically instead of clustering at the bottom under a dead middle band —
    /// the tile reads as an intentional, minimal empty state rather than half-finished.
    var centerWhenEmpty = false
    /// When set, the whole tile is a Button (a shortcut into the log sheet / plan) with the
    /// clinical spring press style.
    var action: (() -> Void)? = nil
    var actionHint: String? = nil
    @ViewBuilder var motif: Motif

    private var isEmptyState: Bool { value == "—" }

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(.clinicalPressable)
                .accessibilityHint(actionHint ?? "Opens this item")
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(Clinical.eyebrow(10)).tracking(1.2)
                    .foregroundStyle(Clinical.tertiary)
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Clinical.accent.opacity(0.75))
                        .accessibilityHidden(true)
                }
            }
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
            if centerWhenEmpty && isEmptyState { Spacer(minLength: 10) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background(alignment: .bottom) {
            motif
                .frame(height: motifHeight)
                .opacity(motifOpacity)
                .allowsHitTesting(false)
        }
        .background {
            // Identity wash sits between the motif and the ivory surface — over the paper,
            // under the ink.
            if let tint {
                LinearGradient(colors: [tint.opacity(0.02), tint.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom)
            }
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
    /// The four self-report tiles are shortcuts into the daily log sheet.
    var onLogTap: () -> Void = {}
    /// The meds tile jumps to the Plan tab's full routine; nil leaves it a plain readout.
    var onOpenPlan: (() -> Void)? = nil

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        // Entrance sequence continues from the hero (index 0); TodayView's cards pick up at 7.
        LazyVGrid(columns: columns, spacing: 12) {
            scalpTile.staggeredEntrance(index: 1)
            sleepTile.staggeredEntrance(index: 2)
            stressTile.staggeredEntrance(index: 3)
            oilTile.staggeredEntrance(index: 4)
            if medsTotal > 0 { medsTile.staggeredEntrance(index: 5) }
            if let triggerWeeks {
                triggerTile(weeks: triggerWeeks)
                    .staggeredEntrance(index: medsTotal > 0 ? 6 : 5)
            }
        }
    }

    // Whisper tints — every wash is an existing Clinical token (or a blend of two), peaking at
    // 0.06 opacity inside GlanceTile so the grid still reads ivory at a glance.
    private static let roseGrey = Clinical.critical.mix(with: Clinical.secondary, by: 0.55)

    // Individual tiles — unlogged days show "—" in tertiary with the motif idling at zero.

    /// Unlike the other three self-report tiles, Scalp's total is a composite of three
    /// components — the tile earns its place by breaking the total down (Flake/Red/Itch bars)
    /// instead of just repeating the "\(total)/16 · \(band)" line the hero subline already shows.
    ///
    /// This is a bespoke layout rather than `GlanceTile` because the bar cluster needs its own
    /// row in the normal flow: GlanceTile's background-motif layering (built for a light wash
    /// behind the text) let the not-logged caption visually collide with the Flake/Red/Itch
    /// labels underneath it. Explicit rows with real spacing keep the two apart at every state.
    private var scalpTile: some View {
        let total = entry?.scalpTotal
        let logged = total != nil
        return Button(action: onLogTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("SCALP")
                        .font(Clinical.eyebrow(10)).tracking(1.2)
                        .foregroundStyle(Clinical.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Clinical.accent.opacity(0.75))
                        .accessibilityHidden(true)
                }
                Text(total.map { "\($0)/16" } ?? "—")
                    .font(Clinical.number(24))
                    .foregroundStyle(entry.map { Clinical.bandColor($0.scalpBand) } ?? Clinical.tertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(entry?.scalpBand.title ?? "Not logged")
                    .font(.system(size: 11)).foregroundStyle(Clinical.secondary)
                    .lineLimit(1)
                Spacer(minLength: 10)
                ScalpComponentBars(
                    flaking: entry?.flaking ?? 0,
                    erythema: entry?.erythema ?? 0,
                    itch: entry?.itch ?? 0,
                    logged: logged
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
            .background {
                // Identity wash — the redness/rose family, same whisper the other tiles use.
                LinearGradient(colors: [Clinical.critical.opacity(0.02), Clinical.critical.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom)
            }
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
            .shadow(color: Clinical.cardShadow, radius: 10, y: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scalp: \(total.map { "\($0)/16" } ?? "not logged"), \(entry?.scalpBand.title ?? "not logged")")
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityHint("Edits today's scalp check-in")
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
        let logged = sleepHours != nil || quality != nil
        return GlanceTile(
            title: "Sleep",
            value: value,
            caption: caption,
            valueColor: logged ? Clinical.ink : Clinical.tertiary,
            tint: Clinical.sage,
            // Quieter wave while empty — centered, it would otherwise cross the "—" baseline.
            motifOpacity: logged ? 0.38 : 0.16,
            centerWhenEmpty: true,
            action: onLogTap,
            actionHint: "Edits today's sleep check-in"
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
            valueColor: stress == nil ? Clinical.tertiary : Clinical.ink,
            tint: Self.roseGrey,
            action: onLogTap,
            actionHint: "Edits today's stress check-in"
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
            valueColor: oil == nil ? Clinical.tertiary : Clinical.ink,
            tint: Clinical.gold,
            motifOpacity: 1,
            centerWhenEmpty: true,
            action: onLogTap,
            actionHint: "Edits today's oiliness check-in"
        ) {
            OilLevelGauge(level: oil ?? 0)
        }
    }

    /// The copper adherence arc IS the visualization here — same ring language as CareView's coach.
    private var medsTile: some View {
        GlanceTile(
            title: "Meds",
            value: "\(medsDone)/\(medsTotal)",
            caption: medsDone >= medsTotal ? "Routine done" : "\(medsTotal - medsDone) left today",
            valueColor: medsDone >= medsTotal ? Clinical.positive : Clinical.ink,
            tint: Clinical.accent,
            motifOpacity: 1,
            action: onOpenPlan,
            actionHint: "Opens today's treatment plan"
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
            tint: Clinical.gold,
            motifOpacity: 1
        ) {
            TriggerWindowBar(weeks: weeks)
        }
    }

    nonisolated private static func stressWord(_ s: Int) -> String {
        switch s {
        case ...1: return "Very calm"
        case 2: return "Calm"
        case 3: return "Moderate"
        case 4: return "High"
        default: return "Very high"
        }
    }

    nonisolated private static func oilWord(_ o: Int) -> String {
        switch o {
        case ...0: return "Balanced"
        case 1: return "Slightly oily"
        case 2: return "Oily"
        default: return "Very oily"
        }
    }
}

// MARK: - Tile accessories

/// Small copper progress arc, the same ring language as CareView's coach ring: full-strength
/// copper over an accent-0.15 track (a hairline track read as washed beige). The fill draws once
/// with a spring on appear — under Reduce Motion it renders instantly — and later dose toggles
/// spring to the new value.
private struct MedsArcRing: View {
    let done: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let progress = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().stroke(Clinical.accent.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: shown ? progress : 0)
                .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 42, height: 42)
        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8), value: progress)
        .onAppear {
            guard !shown else { return }
            if reduceMotion {
                shown = true
            } else {
                // Delayed past the tile's own entrance so the ring draws after the card lands.
                withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.4)) { shown = true }
            }
        }
    }
}

/// Three small component bars — Flake / Red / Itch, each 0–3 — so the Scalp tile shows the
/// makeup of its 16-point total instead of leaving the middle band empty. Bottoms align like a
/// tiny bar chart; an unflagged component still draws a faint track so the trio always reads as
/// one composed visual, not a sometimes-empty one. Sits in the normal VStack flow below the
/// value/caption (not layered as a background motif), so it never overlaps the text above it.
/// When nothing is logged yet, the bars ghost to a flat zero-height track — an intentional
/// empty state rather than a bare "—" — and the caption above already reads "Not logged" once,
/// so the bars themselves stay silent rather than repeating it.
private struct ScalpComponentBars: View {
    let flaking: Int
    let erythema: Int
    let itch: Int
    var logged: Bool = true

    private var components: [(label: String, value: Int)] {
        [("Flake", flaking), ("Red", erythema), ("Itch", itch)]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(components, id: \.label) { component in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Clinical.critical.opacity(logged ? (component.value > 0 ? 0.7 : 0.16) : 0.10))
                        .frame(width: 12, height: logged ? 6 + CGFloat(min(3, max(0, component.value))) * 9 : 6)
                    Text(component.label)
                        .font(Clinical.eyebrow(7))
                        .foregroundStyle(Clinical.tertiary.opacity(logged ? 1 : 0.55))
                }
            }
        }
    }
}

/// A 3-segment fuel-gauge matching Oil's 0–3 self-report scale — filled segments show the
/// logged level at a glance instead of leaving the tile's middle band blank.
private struct OilLevelGauge: View {
    let level: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index < level ? Clinical.gold : Clinical.hairline)
                    .frame(height: 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
