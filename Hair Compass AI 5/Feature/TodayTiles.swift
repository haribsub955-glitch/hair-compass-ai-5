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
    /// True once the user has ever successfully dragged the ladder to set a shedding level —
    /// persists across launches so the visual drag hint (subtitle while unlogged, "Drag to set"
    /// beside the button once logged) is a one-time teach, not a permanent utterance competing
    /// with "+ Log today" on every visit. VoiceOver users keep the instruction regardless, via
    /// `logButton`'s accessibility hint.
    @AppStorage("hasCompletedShedDrag") private var hasCompletedShedDrag = false
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
            // Round-5 fix: the wash used to bottom out at a solid `Clinical.surface` fill,
            // clipped by an `UnevenRoundedRectangle` with a shadow — reading as one big card
            // floating over the page, exactly the container chrome the field-journal vision
            // forbids. The wash now fades back out to the bare canvas by the bottom of the
            // frame, so the falling-hair backdrop breathes directly onto the page with no
            // edge, no corner radius, no shadow to announce a boundary.
            LinearGradient(stops: [
                .init(color: Clinical.canvas, location: 0),
                .init(color: Clinical.surface.opacity(0.9), location: 0.55),
                .init(color: Clinical.canvas, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            sceneLayer
            // Legibility scrim: soft at the top (greeting), stronger over the band word,
            // clear through the middle so the simulation stays the hero — now fading through
            // canvas tones (not surface) so it never reintroduces the dissolved card edge.
            LinearGradient(stops: [
                .init(color: Clinical.canvas.opacity(0.72), location: 0),
                .init(color: Clinical.canvas.opacity(0), location: 0.30),
                .init(color: Clinical.canvas.opacity(0), location: 0.52),
                .init(color: Clinical.canvas.opacity(0.85), location: 0.86),
                .init(color: Clinical.canvas.opacity(0.3), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            content
            if onShedSet != nil && !hasCompletedShedDrag {
                LadderHintRail()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 22)
                    .padding(.bottom, 26)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 304, alignment: .topLeading)
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
                if !hasCompletedShedDrag {
                    withAnimation(.easeOut(duration: 0.4)) { hasCompletedShedDrag = true }
                }
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
                    controlsRow
                } else if let dragIntensity {
                    // Live preview while the finger is down — same slot the saved band word
                    // occupies, so nothing reflows when the drag ends.
                    let caption = SheddingDial.bandCaption(dragIntensity)
                    bandWordText(caption.0)
                    subtitleText(caption.1.prefix(1).uppercased() + caption.1.dropFirst())
                    scalpLine
                    controlsRow
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
                    // Round-5: the permanent "Drag the ladder to set" caption is gone — the
                    // gesture is now taught once by the copper shimmer on `LadderHintRail`
                    // (see `body`), so the unlogged state carries exactly one subtitle line
                    // (none, here) and one action (`logButton` in `controlsRow`).
                    controlsRow
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

    /// Round-5: the streak/level footnote that used to live here is gone — the whole app now
    /// says that fact exactly once, on Trends' `ConsistencyCard` (see its "Sapling · Level 4 ·
    /// 177 XP to Grove · 1-day streak" footnote). `streak`/`shields`/`levelName`/`xp`/
    /// `levelProgress` stay on this view's interface — the celebration flow and XP mechanics
    /// that read them elsewhere are untouched — only the duplicate on-hero display is gone. What
    /// remains here is the single control row: the sole action (Log/Edit today).
    private var controlsRow: some View {
        logButton
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
        .accessibilityHint(logButtonAccessibilityHint)
    }

    /// Carries the drag-to-set instruction for VoiceOver permanently — sighted users lose the
    /// visual hint after their first successful drag (`hasCompletedShedDrag`), but this hint
    /// never fades, since VoiceOver users can't rediscover a gesture from a vanished caption.
    private var logButtonAccessibilityHint: String {
        let base = hasLoggedToday ? "Edits today's check-in" : "Opens today's check-in"
        guard onShedSet != nil else { return base }
        return base + ". Or drag the scene above to set today's shedding level directly."
    }

}

/// Round-5: the sighted teach for the drag-to-set gesture, demoted from a permanent text
/// caption ("Drag the ladder to set" / "Drag to set") to a small vertical rail of four hairline
/// ticks — one per shed band — sitting quietly at the hero's trailing edge. A single copper dot
/// travels once from the bottom tick to the top ("the ladder"), then the whole rail fades away;
/// it never repeats and never returns once `hasCompletedShedDrag` flips true. VoiceOver keeps
/// its own permanent instruction via `logButtonAccessibilityHint` regardless — this rail is
/// purely decorative motion, so it stays hidden from the accessibility tree. Under Reduce
/// Motion the rail never appears at all: the gesture is still reachable via the accessibility
/// adjustable action and the log sheet, just not taught by an animation.
private struct LadderHintRail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = false
    @State private var visible = true

    private enum Phase: CaseIterable { case rest, rise, gone }

    var body: some View {
        Group {
            if !reduceMotion && visible {
                GeometryReader { geo in
                    let h = geo.size.height
                    ZStack(alignment: .bottom) {
                        VStack(spacing: (h - 4 * 3) / 3) {
                            ForEach(0..<4, id: \.self) { _ in
                                Circle().fill(Clinical.hairline).frame(width: 3, height: 3)
                            }
                        }
                        PhaseAnimator(Phase.allCases, trigger: trigger) { phase in
                            Circle()
                                .fill(Clinical.accent)
                                .frame(width: 6, height: 6)
                                .shadow(color: Clinical.accent.opacity(0.35), radius: 3)
                                .offset(y: phase == .rest ? 0 : -(h - 6))
                                .opacity(phase == .gone ? 0 : 1)
                        } animation: { phase in
                            switch phase {
                            case .rest: return nil
                            case .rise: return .easeInOut(duration: 1.1)
                            case .gone: return .easeOut(duration: 0.4)
                            }
                        }
                    }
                }
                .frame(width: 10, height: 88)
                .onAppear {
                    // "First idle": give the hero a beat to settle before teaching the gesture,
                    // then run the one pass and let the rail dissolve for good.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        trigger.toggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
                            withAnimation(.easeOut(duration: 0.5)) { visible = false }
                        }
                    }
                }
            }
        }
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
    /// Today's due routine steps (treatment + slot), rendered as checkable continuation rows of
    /// this same ledger — the checklist card they replaced used to sit in its own boxed card
    /// below the hero, duplicating the "Meds" summary row above with the exact same data.
    var routineSteps: [(Treatment, String)] = []
    var isSlotLogged: (Treatment, String) -> Bool = { _, _ in false }
    var onToggleSlot: (Treatment, String) -> Void = { _, _ in }
    /// The four self-report rows are shortcuts into the daily log sheet.
    var onLogTap: () -> Void = {}
    /// The meds row jumps to the Plan tab's full routine; nil leaves it a plain readout.
    var onOpenPlan: (() -> Void)? = nil
    /// Quiet copper footnote at the very end of the ledger — backfills a past day's entry.
    var onBackfill: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True once the folded "not noted" row has been tapped open — the four self-report rows
    /// then show individually for the rest of this view's lifetime (never auto re-collapses
    /// while the user is working; a fresh appearance of the screen starts folded again).
    @State private var expandedUnlogged = false

    private var scalpLogged: Bool { entry?.scalpTotal != nil }
    private var sleepLogged: Bool { sleepHours != nil || entry?.sleepQuality != nil }
    private var stressLogged: Bool { entry?.stress != nil }
    private var oilLogged: Bool { entry?.oiliness != nil }

    /// Short labels for whichever of the four self-report signals have nothing logged today —
    /// what the folded row lists.
    private var unloggedLabels: [String] {
        var labels: [String] = []
        if !scalpLogged { labels.append("scalp") }
        if !sleepLogged { labels.append("sleep") }
        if !stressLogged { labels.append("stress") }
        if !oilLogged { labels.append("oil") }
        return labels
    }

    var body: some View {
        // Entrance sequence continues from the hero (index 0), at a tighter 40ms step than the
        // rest of the page's cards — a short ledger of rows should settle quickly, not read as
        // its own slow reveal. TodayView's cards below pick up at their own indices/step.
        VStack(alignment: .leading, spacing: 0) {
            rule
            ForEach(Array(visibleRows.enumerated()), id: \.offset) { _, row in
                row
                rule
            }
        }
    }

    /// Logged signals always show their own full row; unlogged ones among scalp/sleep/stress/oil
    /// fold into a single "not noted yet" row instead of four consecutive empty placeholders —
    /// congestion made of absence, on an unlogged morning. Tapping the folded row expands the
    /// remaining rows in place with a staggered cascade.
    private var visibleRows: [AnyView] {
        var rows: [AnyView] = []
        var index = 1
        func add<V: View>(_ view: V) {
            rows.append(AnyView(view.staggeredEntrance(index: index, step: 0.04)))
            index += 1
        }
        if scalpLogged || expandedUnlogged { add(scalpRow) }
        if sleepLogged || expandedUnlogged { add(sleepRow) }
        if stressLogged || expandedUnlogged { add(stressRow) }
        if oilLogged || expandedUnlogged { add(oilRow) }
        if !expandedUnlogged && !unloggedLabels.isEmpty { add(collapsedUnloggedRow) }
        // Round-7 fix: when the ROUTINE ledger below has rows to show, they already display these
        // exact doses live (checkable circles) — a "Meds N/M" readout directly above would say the
        // same fact twice. `medsRow` now only appears as a fallback for meds that exist but for
        // whatever reason produced no routine rows today (e.g. every dose is off-schedule).
        if medsTotal > 0 && routineSteps.isEmpty { add(medsRow) }
        if let triggerWeeks { add(triggerRow(weeks: triggerWeeks)) }
        if !routineSteps.isEmpty {
            add(routineHeaderRow)
            for step in routineSteps { add(routineStepRow(step.0, slot: step.1)) }
        }
        if let onBackfill { add(backfillFootnoteRow(onBackfill)) }
        return rows
    }

    // MARK: Routine (absorbed from the old boxed checklist card)

    /// One small-caps label row — replaces the boxed "Today's checklist" card's Eyebrow, now a
    /// continuation of the same hairline-ruled ledger instead of its own heading over its own box.
    /// Round-7: carries the remaining-dose count that used to be its own "Meds N/M" row above —
    /// a quiet right-aligned counter that ticks down (with a soft spring) as circles below are
    /// checked, so the header itself answers "how many left" instead of restating the ledger.
    private var routineHeaderRow: some View {
        HStack {
            Text("ROUTINE")
                .font(Clinical.eyebrow(10)).tracking(1.2)
                .foregroundStyle(Clinical.tertiary)
            Spacer()
            if medsTotal > 0 {
                Text(medsRemainingLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(medsDone >= medsTotal ? Clinical.positive : Clinical.tertiary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: medsTotal - medsDone)
            }
        }
        .padding(.vertical, 13)
    }

    private var medsRemainingLabel: String {
        let remaining = medsTotal - medsDone
        return remaining <= 0 ? "Done" : "\(remaining) left"
    }

    private func routineStepRow(_ treatment: Treatment, slot: String) -> some View {
        let done = isSlotLogged(treatment, slot)
        let cls = treatment.treatmentClass.title
        return RoutineLedgerRow(
            name: treatment.name,
            // Round-8: matches Plan's identical row grammar — a mono time (or "TODAY" for a
            // slotless periodic care product) in the leading margin, the name once in ink, and
            // the class repeated underneath only when the name doesn't already say it. The old
            // subtitle ("21:00 · Finasteride") echoed the row's own name directly above it.
            timeLabel: slot.isEmpty ? "TODAY" : slot,
            classSubtitle: treatment.name.localizedCaseInsensitiveContains(cls) ? nil : cls,
            done: done,
            action: { onToggleSlot(treatment, slot) }
        )
    }

    /// "Past day" backfill, demoted from a header-row button on the old checklist card to the
    /// quiet copper line that closes the whole ledger.
    private func backfillFootnoteRow(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("Log a past day")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Clinical.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Clinical.accent.opacity(0.5))
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityHint("Backfills a check-in for an earlier day")
    }

    private var rule: some View {
        Divider().overlay(Clinical.hairline)
    }

    /// One quiet row folding every currently-unlogged self-report signal into a single line —
    /// "Not noted yet — scalp · sleep · stress · oil" — with a small copper "add" affordance.
    /// Tapping expands the folded rows in place so every existing control stays reachable.
    private var collapsedUnloggedRow: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if reduceMotion {
                expandedUnlogged = true
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { expandedUnlogged = true }
            }
        } label: {
            HStack(spacing: 10) {
                Text("Not noted yet")
                    .font(.system(size: 14))
                    .foregroundStyle(Clinical.tertiary.opacity(0.7))
                Text(unloggedLabels.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Clinical.tertiary.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Label("Add", systemImage: "plus")
                    .font(Clinical.eyebrow(10)).tracking(0.6)
                    .foregroundStyle(Clinical.accent)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Not noted yet: \(unloggedLabels.joined(separator: ", "))")
        .accessibilityHint("Expands to log these")
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

    /// Fallback-only readout (see `visibleRows`) — no LevelDots trace alongside the chevron
    /// anymore, since dots + chevron read as two affordances for one tap target. The chevron
    /// alone (from `action`) is enough.
    private var medsRow: some View {
        AnnotationRow(
            label: "Meds",
            value: "\(medsDone)/\(medsTotal) · \(medsDone >= medsTotal ? "done" : "\(medsTotal - medsDone) left")",
            logged: true,
            valueColor: medsDone >= medsTotal ? Clinical.positive : Clinical.ink,
            action: onOpenPlan,
            actionHint: "Opens today's treatment plan"
        )
    }

    /// Telogen-effluvium watch: margin ink, not a control — a hairline rule with one copper tick
    /// marking today's week and a faint sage band over the 8–12 week peak-shedding window. Round-7
    /// replaced a dot-on-track trace that read as a draggable slider knob; this has none.
    private func triggerRow(weeks: Int) -> some View {
        AnnotationRow(
            label: "Trigger watch",
            value: "Week \(weeks) of 16",
            logged: true,
            valueColor: Clinical.warning,
            trace: AnyView(TriggerTickTrace(fraction: min(1, CGFloat(weeks) / 16)))
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
/// stroke, no shadow; hairline `Divider`s drawn by the ledger above separate rows. Internal (not
/// file-private) so Trends' own margin-note rows (scalp/adherence) can reuse the same language
/// instead of duplicating it.
struct AnnotationRow: View {
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

/// One checkable routine step, styled to continue the ledger's rows: a small hairline circle
/// leading (fills copper with a check when logged), a mono time in the leading margin, the step
/// name once in ink, no card, no strikethrough — a current-treatment list reads a struck-through
/// name as "discontinued", which this app must never imply.
///
/// Round-8: the old subtitle ("21:00 · Finasteride") echoed the row's own name directly above it
/// and spoke a different grammar than the identical row on Plan. This now shares Plan's exact
/// grammar — mono time in the margin, name once, class only when the name doesn't already say it
/// — so the same fact is said in the same voice on both screens (see `RoutineStepRow` in
/// CareView.swift).
private struct RoutineLedgerRow: View {
    let name: String
    let timeLabel: String
    let classSubtitle: String?
    let done: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop = false

    private var accessibilityDetail: String {
        [timeLabel, classSubtitle].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        Button {
            let willCheck = !done
            action()
            guard willCheck, !reduceMotion else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                pop = true
            } completion: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pop = false }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(done ? Clinical.accent : Clinical.accent.opacity(0.06))
                    Circle().strokeBorder(done ? Clinical.accent : Clinical.accent.opacity(0.4), lineWidth: 1.5)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Clinical.surface)
                    }
                }
                .frame(width: 20, height: 20)
                .scaleEffect(pop ? 1.15 : 1)
                Text(timeLabel.uppercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Clinical.secondary)
                    .frame(width: 46, alignment: .leading)
                    .opacity(done ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 14, weight: done ? .regular : .medium))
                        .foregroundStyle(done ? Clinical.secondary : Clinical.ink)
                    if let classSubtitle {
                        Text(classSubtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Clinical.tertiary)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel("\(name), \(accessibilityDetail)")
        .accessibilityValue(done ? "Logged" : "Not logged")
        .accessibilityHint("Toggles today's dose as logged")
    }
}

/// A tiny 40×6pt inline trace: a hairline track with a colored dot marking today's position — the
/// ledger's whole reply to what used to be a full-size background motif. An optional shaded band
/// (used by the trigger-watch row) marks a window of interest along the track. Internal so Trends'
/// scalp/adherence rows can share it.
struct MiniTrace: View {
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

/// Margin-ink reading for the trigger watch: a 1pt `Clinical.hairline` rule, a faint sage band
/// over the 8–12-week peak-shedding window, and one copper tick marking today's week — annotation
/// language, not a control. Round-7 replaced this row's previous dot-on-track trace, which read as
/// a slider knob competing with the ledger's real controls (the routine circles below it). The
/// tick slides in once from week 0 to its resting position on first appearance; under Reduce
/// Motion it simply appears already settled, matching every other one-time draw-in in this file.
private struct TriggerTickTrace: View {
    let fraction: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Clinical.hairline).frame(height: 1)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Clinical.sage.opacity(0.3))
                    .frame(width: w * 0.25, height: 4)
                    .offset(x: w * 0.5)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Clinical.accent)
                    .frame(width: 2, height: 8)
                    .offset(x: max(0, min(w - 2, w * (arrived ? fraction : 0) - 1)))
            }
        }
        .frame(width: 40, height: 8)
        .onAppear {
            guard !arrived else { return }
            if reduceMotion {
                arrived = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { arrived = true }
            }
        }
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
