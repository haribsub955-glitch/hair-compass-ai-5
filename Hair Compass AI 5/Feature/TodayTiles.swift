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
    /// Drives the headline's accessibility-size fallback: at .accessibility1+ Dynamic Type the
    /// 44–50pt serif headline stops fighting for one crushed/truncated line — it drops the
    /// ladder's trailing reservation and wraps onto up to two lines at word boundaries instead
    /// (see round-5 fix below; `Text("Not logged")` used to render "Not lo…").
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isAccessibilitySize: Bool { dynamicTypeSize >= .accessibility1 }
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
                    .init(color: .clear, location: max(0, strandMaskTop - 0.16)),
                    .init(color: .black, location: strandMaskTop),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// Where falling strands become fully visible, as a fraction of hero height. At the calmest
    /// band (Minimal) the few strands are pushed below the band word, so one never drifts across
    /// the headline; busier bands keep the higher default and let the simulation fill the scene.
    private var strandMaskTop: CGFloat {
        SheddingDial.band(displayIntensity) == ShedLevel.minimal.rawValue ? 0.56 : 0.36
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
                    // occupies, so nothing reflows when the drag ends.
                    let caption = SheddingDial.bandCaption(dragIntensity)
                    bandWordText(caption.0)
                    subtitleText(caption.1.prefix(1).uppercased() + caption.1.dropFirst())
                    scalpLine
                    chipRow
                } else {
                    // Round-4 fix: the headline used to carry the whole instruction ("Not logged
                    // — drag to set"), which either got clipped mid-word at accessibility sizes
                    // or wrapped onto a second line starting with a bare em-dash at default size.
                    // Splitting it — a short headline that always fits one line, plus the
                    // instruction in the same small subtitle slot the drag-live and saved
                    // branches above use — lets the instruction wrap freely at body size instead
                    // of being crushed or truncated at 44pt, and keeps this branch's structure
                    // (headline + subtitle) identical to theirs so nothing reflows when a finger
                    // goes down.
                    //
                    // Round-5 fix: at .accessibility1+ Dynamic Type, `lineLimit(1) +
                    // minimumScaleFactor(0.65)` still couldn't fit "Not logged" and truncated to
                    // "Not lo…" — the one word this screen exists to show, unreadable. At those
                    // sizes the headline wraps onto up to two lines at a natural word boundary
                    // instead of scaling/truncating.
                    Text("Not logged")
                        .font(Clinical.headline(44)).foregroundStyle(Clinical.tertiary)
                        .lineLimit(isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(isAccessibilitySize ? 1 : 0.65)
                    if onShedSet != nil {
                        subtitleText("Drag the ladder to set")
                    }
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
            .lineLimit(isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(isAccessibilitySize ? 1 : 0.55)
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

    /// Falls back to a stacked layout when the row can't fit at large Dynamic Type instead of
    /// Everything that used to be four competing pill-shaped objects (streak chip, XP/level
    /// chip, copper Edit-log pill, floating SET stepper) is now one quiet annotation line plus
    /// one control row: a hairline of muted text stating streak/XP/level, and — directly below
    /// it — the sole button (Edit log) with the drag-to-set hint sitting beside it instead of
    /// hugging the screen edge. Falls back to a stacked layout only if Dynamic Type can't fit
    /// the annotation line on one row.
    private var chipRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            annotationLine
            controlsRow
        }
    }

    /// "1-day streak · Sapling" — one quiet footnote, no capsule strokes, no ring. The raw XP
    /// figure used to ride along here too, but it already lives with the badges/celebration
    /// sheet — saying it a second time on every visit to Today was the third of three competing
    /// footnotes this line used to fire at once.
    private var annotationLine: some View {
        HStack(spacing: 0) {
            Text(streakText)
            if let levelName {
                dotSeparator
                Text(levelName)
            }
        }
        .font(Clinical.eyebrow(10))
        .tracking(1.0)
        .foregroundStyle(Clinical.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(annotationAccessibilityLabel)
    }

    private var dotSeparator: some View {
        Text("  ·  ")
    }

    private var streakText: String {
        shields > 0 ? "\(streak)-day streak (\(shields) shield\(shields == 1 ? "" : "s"))" : "\(streak)-day streak"
    }

    private var annotationAccessibilityLabel: String {
        var parts = [streakText]
        if let levelName { parts.append("\(levelName) level") }
        return parts.joined(separator: ", ")
    }

    /// True while nothing is logged yet and no finger is down — the same state whose headline
    /// subtitle already reads "Drag the ladder to set". `controlsRow` skips the copper hint in
    /// this one state so the instruction is never said twice; once something's logged (or being
    /// dragged), the hint is the only surviving cue that the scene is still draggable.
    private var isNotLoggedState: Bool { shed == nil && dragIntensity == nil }

    private var controlsRow: some View {
        HStack(spacing: 16) {
            logButton
            if onShedSet != nil && !isNotLoggedState { setHint }
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

    /// The drag-to-set affordance, demoted from a floating edge-hugging capsule to a small
    /// inline copper text control that sits quietly beside Edit log — same discoverability,
    /// none of the edge clutter. Purely a visual hint (the gesture lives on the scene itself),
    /// so it stays decorative/non-interactive here too.
    private var setHint: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.up.and.down")
                .font(.system(size: 9, weight: .semibold))
            Text("Drag to set")
                .font(Clinical.eyebrow(10)).tracking(0.6)
        }
        .foregroundStyle(Clinical.accent)
        .accessibilityHidden(true)
    }
}

// MARK: - Signal ledger (margin-note rows)

/// The margin-note ledger that replaces the old boxed glance-tile grid: one hairline-ruled column
/// of quiet annotation rows directly on the canvas instead of stacked cards. Every signal is one
/// line — small-caps label, a state word in ink, and (only once something's actually logged) a
/// tiny inline trace on the right. An unlogged signal is nothing but its own "not noted" line —
/// no ghost chips, no idle decorative motif standing in for data that doesn't exist yet. Tapping
/// a row opens the same destination its predecessor tile did.
struct TodayTileGrid: View {
    var entry: DailyEntry?
    var sleepHours: Double?
    var medsDone: Int
    var medsTotal: Int
    var triggerWeeks: Int?
    /// The four self-report rows are shortcuts into the daily log sheet.
    var onLogTap: () -> Void = {}
    /// The meds row jumps to the Plan tab's full routine; nil leaves it a plain readout.
    var onOpenPlan: (() -> Void)? = nil

    var body: some View {
        // Entrance sequence continues from the hero (index 0), at a tighter 40ms step than the
        // rest of the page's cards — a short ledger of rows should settle quickly, not read as
        // its own slow reveal. TodayView's cards below pick up at their own indices/step.
        VStack(alignment: .leading, spacing: 0) {
            rule
            scalpRow.staggeredEntrance(index: 1, step: 0.04)
            rule
            sleepRow.staggeredEntrance(index: 2, step: 0.04)
            rule
            stressRow.staggeredEntrance(index: 3, step: 0.04)
            rule
            oilRow.staggeredEntrance(index: 4, step: 0.04)
            if medsTotal > 0 {
                rule
                medsRow.staggeredEntrance(index: 5, step: 0.04)
            }
            if let triggerWeeks {
                rule
                triggerRow(weeks: triggerWeeks)
                    .staggeredEntrance(index: medsTotal > 0 ? 6 : 5, step: 0.04)
            }
            rule
        }
    }

    private var rule: some View {
        Divider().overlay(Clinical.hairline)
    }

    // Whisper tint kept from the old tile grid for Stress's trace dots.
    private static let roseGrey = Clinical.critical.mix(with: Clinical.secondary, by: 0.55)

    // MARK: Rows — unlogged signals show only their "Not noted" line, no trace.

    private var scalpRow: some View {
        let total = entry?.scalpTotal
        let logged = total != nil
        let value = total.map { "\($0)/16 · \(entry!.scalpBand.title)" } ?? "Not noted"
        return AnnotationRow(
            label: "Scalp",
            value: value,
            logged: logged,
            action: onLogTap,
            actionHint: "Edits today's scalp check-in",
            trace: logged
                ? AnyView(ScalpTrace(flaking: entry?.flaking ?? 0, erythema: entry?.erythema ?? 0, itch: entry?.itch ?? 0))
                : nil
        )
    }

    private var sleepRow: some View {
        let quality = entry?.sleepQuality
        let value: String
        let fraction: CGFloat
        if let sleepHours {
            value = String(format: "%.1fh", sleepHours)
            fraction = min(1, max(0, CGFloat(sleepHours) / 8))
        } else if let quality {
            value = "\(quality)/5"
            fraction = CGFloat(quality - 1) / 4
        } else {
            value = "Not noted"
            fraction = 0
        }
        let logged = sleepHours != nil || quality != nil
        return AnnotationRow(
            label: "Sleep",
            value: value,
            logged: logged,
            action: onLogTap,
            actionHint: "Edits today's sleep check-in",
            trace: logged ? AnyView(MiniTrace(fraction: fraction, color: Clinical.sage)) : nil
        )
    }

    private var stressRow: some View {
        let stress = entry?.stress
        return AnnotationRow(
            label: "Stress",
            value: stress.map { "\($0)/5 · \(Self.stressWord($0))" } ?? "Not noted",
            logged: stress != nil,
            action: onLogTap,
            actionHint: "Edits today's stress check-in",
            trace: stress.map { AnyView(LevelDots(filled: $0, total: 5, color: Self.roseGrey)) }
        )
    }

    private var oilRow: some View {
        let oil = entry?.oiliness
        return AnnotationRow(
            label: "Oil",
            value: oil.map { "\($0)/3 · \(Self.oilWord($0))" } ?? "Not noted",
            logged: oil != nil,
            action: onLogTap,
            actionHint: "Edits today's oiliness check-in",
            trace: oil.map { AnyView(LevelDots(filled: $0, total: 3, color: Clinical.gold)) }
        )
    }

    private var medsRow: some View {
        AnnotationRow(
            label: "Meds",
            value: "\(medsDone)/\(medsTotal) · \(medsDone >= medsTotal ? "done" : "\(medsTotal - medsDone) left")",
            logged: true,
            valueColor: medsDone >= medsTotal ? Clinical.positive : Clinical.ink,
            action: onOpenPlan,
            actionHint: "Opens today's treatment plan",
            trace: AnyView(LevelDots(filled: medsDone, total: min(max(medsTotal, 1), 8), color: Clinical.accent))
        )
    }

    /// Telogen-effluvium watch: the trace's shaded band marks the 8–12 week window where
    /// trigger-driven shedding typically peaks; the dot marks where today sits in the 16-week watch.
    private func triggerRow(weeks: Int) -> some View {
        AnnotationRow(
            label: "Trigger watch",
            value: "Week \(weeks) of 16",
            logged: true,
            valueColor: Clinical.warning,
            trace: AnyView(MiniTrace(fraction: min(1, CGFloat(weeks) / 16), color: Clinical.warning,
                                      bandStart: 0.5, bandWidth: 0.25))
        )
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

// MARK: - Ledger row + traces

/// One quiet ledger row: small-caps label, a state word in ink (or "not noted" in faded ink when
/// unlogged), and — only when logged — a tiny inline trace on the right. No card surface, no
/// stroke, no shadow; hairline `Divider`s drawn by the ledger above separate rows.
private struct AnnotationRow: View {
    let label: String
    let value: String
    var logged: Bool
    var valueColor: Color = Clinical.ink
    var action: (() -> Void)? = nil
    var actionHint: String? = nil
    var trace: AnyView? = nil

    var body: some View {
        if let action {
            Button(action: action) { rowContent }
                .buttonStyle(.clinicalPressable)
                .accessibilityHint(actionHint ?? "Opens this item")
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(Clinical.eyebrow(10)).tracking(1.2)
                .foregroundStyle(Clinical.tertiary)
                .frame(minWidth: 82, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: logged ? .medium : .regular))
                .foregroundStyle(logged ? valueColor : Clinical.tertiary.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            if let trace { trace }
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Clinical.accent.opacity(0.5))
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// A tiny 40×6pt inline trace: a hairline track with a colored dot marking today's position — the
/// ledger's whole reply to what used to be a full-size background motif. An optional shaded band
/// (used by the trigger-watch row) marks a window of interest along the track.
private struct MiniTrace: View {
    let fraction: CGFloat
    var color: Color = Clinical.accent
    var bandStart: CGFloat? = nil
    var bandWidth: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Clinical.hairline).frame(height: 3)
                if let bandStart, let bandWidth {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color.opacity(0.22))
                        .frame(width: w * bandWidth, height: 3)
                        .offset(x: w * bandStart)
                }
                Circle().fill(color)
                    .frame(width: 6, height: 6)
                    .offset(x: max(0, min(w - 6, w * fraction - 3)))
            }
        }
        .frame(width: 40, height: 6)
    }
}

/// A row of small filled/unfilled dots — the ledger's reply to a pip stepper, used by Stress
/// (0–5), Oil (0–3) and Meds (done of total).
private struct LevelDots: View {
    let filled: Int
    let total: Int
    var color: Color = Clinical.accent

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Circle()
                    .fill(i < filled ? color : Clinical.hairline)
                    .frame(width: 5, height: 5)
            }
        }
    }
}

/// Three tiny dots — Flake / Red / Itch — so Scalp's ledger row still shows the makeup of its
/// 16-point total instead of only the sum. Opacity (not height) carries each component's 0–3
/// value, keeping the trace to the same 3-dot footprint as every other row's trace.
private struct ScalpTrace: View {
    let flaking: Int
    let erythema: Int
    let itch: Int

    var body: some View {
        HStack(spacing: 4) {
            dot(flaking)
            dot(erythema)
            dot(itch)
        }
    }

    private func dot(_ v: Int) -> some View {
        Circle()
            .fill(Clinical.critical.opacity(v > 0 ? min(1, 0.35 + Double(v) * 0.2) : 0.15))
            .frame(width: 6, height: 6)
    }
}
