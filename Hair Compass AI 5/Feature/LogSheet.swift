import SwiftData
import SwiftUI

/// Daily self-report. Fields are exactly the evidence-backed signals from TrackingSpec.md.
/// Every field is a living gauge — the animated preview *is* the thing being measured — so
/// logging reads like your scalp, not a form. Gauges hold a 0…1 intensity while dragging;
/// the discrete Ints stored on `DailyEntry` are derived from those intensities (same
/// round-trip `ShedDialField` does with `shed`).
struct LogSheet: View {
    let existing: DailyEntry?
    let condition: HairCondition
    /// Called (after dismiss) when a save actually earned something — a new logged day or a
    /// fresh badge — so the presenter can show the check-in celebration. Never called for
    /// pure edits of an already-logged day: those have no XP delta and stay quiet.
    var onSaved: ((CheckInReward) -> Void)?

    init(existing: DailyEntry?, condition: HairCondition, onSaved: ((CheckInReward) -> Void)? = nil) {
        self.existing = existing
        self.condition = condition
        self.onSaved = onSaved
        _logDate = State(initialValue: existing?.date ?? .now)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ProcedureAppointment.date, order: .reverse) private var procedureAppointments: [ProcedureAppointment]

    /// The calendar day this log belongs to. Scrubbable (up to 60 days back) when creating a
    /// new entry; fixed to the entry's own day when editing an existing one.
    @State private var logDate: Date
    @State private var scrollTarget: String?
    /// When creating a new entry and the scrubbed day already has one, that entry — the form
    /// shows its values and save() writes into it instead of inserting a duplicate.
    @State private var matchedEntry: DailyEntry?

    @State private var shed: ShedLevel = .normal
    /// Shed hair reads far heavier on wash days — this one tap keeps that confound out of the
    /// honest read on Trends/ProgressReport/Compare instead of a wash day silently masquerading
    /// as a real change.
    @State private var washedHair = false
    @State private var flakeI: CGFloat = 0
    @State private var redI: CGFloat = 0
    @State private var itchI: CGFloat = 0
    @State private var oilI: CGFloat = 0
    @State private var sleepI: CGFloat = 0.5   // sleepQuality 3
    @State private var stressI: CGFloat = 0.5  // stress 3
    @State private var cigarettes = 0
    @State private var alcoholDrinks = 0
    @State private var note = ""

    // The stored values stay the source of truth in save(): each is the band of the live
    // intensity, so the severity readout below updates as you drag.
    private var flaking: Int { GaugeBand.index(flakeI, count: 4) }
    private var erythema: Int { GaugeBand.index(redI, count: 4) }
    private var itch: Int { GaugeBand.index(itchI, count: 4) }
    private var oiliness: Int { GaugeBand.index(oilI, count: 4) }
    private var sleepQuality: Int { 1 + GaugeBand.index(sleepI, count: 5) }
    private var stress: Int { 1 + GaugeBand.index(stressI, count: 5) }

    private var scalpTotal: Int { HairAnalytics.scalpTotal(flaking: flaking, erythema: erythema, itch: itch) }
    private var scalpBand: SeverityBand { HairAnalytics.scalpBand(total: scalpTotal) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    CheckInJourneyHeader(onSelect: scrollToChapter)

                    section("Day") {
                        if existing == nil {
                            DateStripPicker(selection: $logDate, range: backfillRange)
                            if matchedEntry != nil {
                                Text("This day already has an entry — you're editing it.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Clinical.tertiary)
                            }
                        } else {
                            Text(logDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .font(Clinical.headline(17))
                                .foregroundStyle(Clinical.ink)
                        }
                    }

                    section(variable: "shedding") {
                        ShedDialField(shed: $shed)
                        washDayToggle
                    }
                    .id("checkInHair")

                    section(variable: "scalp", trailing: AnyView(severityReadout)) {
                        VStack(spacing: 16) {
                            LivingGauge(title: "Flaking", intensity: $flakeI, bandCount: 4,
                                        tint: Clinical.secondary,
                                        zones: ["NONE", "POWDERY", "VISIBLE", "ADHERENT"], ends: nil,
                                        caption: flakeCaption) { i in FlakeMotif(intensity: i) }
                            LivingGauge(title: "Redness", intensity: $redI, bandCount: 4,
                                        tint: Clinical.critical,
                                        panelBackground: Clinical.canvas,  // a hair warmer, so the flush reads
                                        zones: ["NONE", "MILD", "MODERATE", "MARKED"], ends: nil,
                                        caption: rednessCaption) { i in RednessMotif(intensity: i) }
                            LivingGauge(title: "Itch", intensity: $itchI, bandCount: 4,
                                        tint: Clinical.warning,
                                        zones: ["NONE", "MILD", "MODERATE", "MARKED"], ends: nil,
                                        caption: itchCaption) { i in ItchMotif(intensity: i) }
                        }

                        Divider().overlay(Clinical.hairline).padding(.vertical, 2)

                        LivingGauge(title: "Oiliness", intensity: $oilI, bandCount: 4,
                                    tint: Clinical.gold,
                                    zones: ["NORMAL", "SLIGHT", "OILY", "VERY"], ends: nil,
                                    caption: oilinessCaption) { i in OilMotif(intensity: i) }
                        Text("An observation, not a risk driver — it doesn't feed the severity score.")
                            .font(.system(size: 11))
                            .foregroundStyle(Clinical.tertiary)
                    }
                    .id("checkInScalp")

                    section("Wellbeing") {
                        VStack(spacing: 16) {
                            LivingGauge(title: "Sleep quality", intensity: $sleepI, bandCount: 5,
                                        tint: Clinical.ink,
                                        zones: nil, ends: ("POOR", "DEEP"),
                                        caption: sleepCaption) { i in SleepMotif(intensity: i) }
                            LivingGauge(title: "Stress", intensity: $stressI, bandCount: 5,
                                        tint: Clinical.critical,
                                        zones: nil, ends: ("CALM", "HIGH"),
                                        caption: stressCaption) { i in StressMotif(intensity: i) }
                        }
                        CountScrubber(title: "Cigarettes today", value: $cigarettes, range: 0...60, tint: Clinical.warning, motif: .smoke)
                        CountScrubber(title: "Alcoholic drinks", value: $alcoholDrinks, range: 0...30, tint: Clinical.secondary, motif: .drops)
                        Text("Smoking is a strong, quantified risk factor. Sleep and stress are context; alcohol is a weak signal.")
                            .font(.system(size: 11))
                            .foregroundStyle(Clinical.tertiary)
                    }
                    .id("checkInContext")

                    CheckInPortraitCard(
                        shed: shed,
                        scalpTotal: scalpTotal,
                        scalpBand: scalpBand,
                        sleepQuality: sleepQuality,
                        stress: stress
                    )
                    .id("checkInPortrait")

                    section("Note") {
                        TextField(
                            "",
                            text: $note,
                            prompt: Text("Anything worth remembering")
                                .foregroundStyle(Clinical.secondary.opacity(0.78)),
                            axis: .vertical
                        )
                            .lineLimit(2...5)
                            .font(.system(size: 15))
                            .foregroundStyle(Clinical.ink)
                            .tint(Clinical.accent)
                            .padding(12)
                            .background(Clinical.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Clinical.hairline, lineWidth: 1)
                            )
                    }

                    // Optional, minimal, and fully independent of the DailyEntry save below —
                    // it acts immediately on tap and never gates or is gated by the main Save.
                    if Calendar.current.isDateInToday(logDate) {
                        section("Procedure") { procedureControl }
                    }

                    Button(saveButtonTitle, action: save)
                        .buttonStyle(ClinicalButtonStyle())
                }
                .padding(20)
                .padding(.bottom, 20)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollTarget, anchor: .top)
            .clinicalScreen()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if existing != nil || matchedEntry != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                            .accessibilityHint("Saves these changes without scrolling to the end")
                    }
                }
            }
            .onAppear(perform: loadExisting)
            .onChange(of: logDate) { _, newDay in
                guard existing == nil else { return }
                syncForm(to: newDay)
            }
        }
    }

    // MARK: Day selection

    /// Backfill window: 60 days ago through today. Never the future.
    private var backfillRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let lower = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        return lower...today
    }

    private var dayLabel: String {
        Calendar.current.isDateInToday(logDate)
            ? "today"
            : logDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private var saveButtonTitle: String {
        if existing != nil { return "Update entry" }
        return matchedEntry == nil ? "Save \(dayLabel)" : "Update \(dayLabel)"
    }

    private var navigationTitle: String {
        if existing != nil { return "Edit today" }
        return Calendar.current.isDateInToday(logDate) ? "Log today" : "Log \(dayLabel)"
    }

    /// Live scalp-severity composite — recomputed from the current gauge intensities, so it
    /// updates while you drag (flaking + redness + itch, the Zhang 2023 16-point scale).
    private var severityReadout: some View {
        AnimatedSeverityReadout(total: scalpTotal, band: scalpBand)
    }

    /// One-tap wash-day flag right beside the shed selector — the single biggest confound on
    /// a self-reported shed read. Kept to one explainer line so it doesn't compete with the
    /// dial for attention; Trends/ProgressReport/Compare use it to hedge, never to hide data.
    private var washDayToggle: some View {
        Toggle(isOn: $washedHair) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Washed hair today").font(.system(size: 13, weight: .medium)).foregroundStyle(Clinical.ink)
                Text("Shed hairs are far more visible on wash days.")
                    .font(.system(size: 11)).foregroundStyle(Clinical.secondary)
            }
        }
        .tint(Clinical.accent)
    }

    private func scrollToChapter(_ id: String) {
        if reduceMotion {
            scrollTarget = id
        } else {
            withAnimation(.easeInOut(duration: 0.28)) { scrollTarget = id }
        }
    }

    // MARK: Procedure — a compact, optional "did a procedure today?" affordance (Track C).

    private var todaysProcedures: [ProcedureAppointment] {
        procedureAppointments.filter { Calendar.current.isDateInToday($0.date) }
    }
    /// A scheduled, not-yet-done appointment dated today — offered a one-tap "Mark done".
    private var pendingProcedureToday: ProcedureAppointment? {
        todaysProcedures.first { !$0.isCompleted }
    }
    private var completedProceduresToday: [ProcedureAppointment] {
        todaysProcedures.filter(\.isCompleted)
    }

    @ViewBuilder
    private var procedureControl: some View {
        if let appt = pendingProcedureToday {
            HStack(spacing: 10) {
                Image(systemName: appt.type.symbol)
                    .font(.system(size: 14)).foregroundStyle(Clinical.accent)
                    .frame(width: 31, height: 31)
                    .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(appt.type.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                    Text("Scheduled today").font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                }
                Spacer()
                Button("Mark done") { markProcedureDone(appt) }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Clinical.surface)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Clinical.accent, in: Capsule())
                    .buttonStyle(.plain)
            }
        } else if !completedProceduresToday.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(completedProceduresToday) { appt in
                    Label("\(appt.type.title) · logged", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Clinical.positive)
                }
            }
        } else {
            Menu {
                ForEach(ProcedureType.allCases) { type in
                    Button(type.title) { logAdHocProcedure(type) }
                }
            } label: {
                Label("Did a procedure today?", systemImage: "plus.circle")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Clinical.accent)
            }
        }
    }

    private func markProcedureDone(_ appt: ProcedureAppointment) {
        appt.isCompleted = true
        appt.completedAt = .now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func logAdHocProcedure(_ type: ProcedureType) {
        context.insert(ProcedureAppointment(type: type, date: .now, isCompleted: true, completedAt: .now))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Captions — titles reuse the app's existing vocabulary; subtitles from the design.

    private func flakeCaption(_ i: CGFloat) -> (String, String) {
        let b = GaugeBand.index(i, count: 4)
        return (["None", "Powdery", "Visible", "Adherent"][b],
                ["clear today", "fine dust", "flakes you can see", "stuck to the scalp"][b])
    }
    private func rednessCaption(_ i: CGFloat) -> (String, String) {
        let b = GaugeBand.index(i, count: 4)
        return (level3Caption(b), ["calm scalp", "a slight flush", "clearly pink", "angry and inflamed"][b])
    }
    private func itchCaption(_ i: CGFloat) -> (String, String) {
        let b = GaugeBand.index(i, count: 4)
        return (level3Caption(b), ["settled", "the odd prickle", "distracting", "hard to ignore"][b])
    }
    private func oilinessCaption(_ i: CGFloat) -> (String, String) {
        let b = GaugeBand.index(i, count: 4)
        return (["Normal", "Slightly oily", "Oily", "Very oily"][b],
                ["normal for you", "a little shine", "noticeably oily", "greasy by midday"][b])
    }
    private func sleepCaption(_ i: CGFloat) -> (String, String) {
        let level = 1 + GaugeBand.index(i, count: 5)
        return (["Poor", "Restless", "Okay", "Good", "Deep"][level - 1],
                ["barely slept", "a broken night", "an average night", "solid rest", "fully rested"][level - 1] + " · \(level)/5")
    }
    private func stressCaption(_ i: CGFloat) -> (String, String) {
        let level = 1 + GaugeBand.index(i, count: 5)
        return (["Calm", "Steady", "Moderate", "Tense", "High"][level - 1],
                ["at ease", "mostly fine", "some pressure", "wound up", "overwhelmed"][level - 1] + " · \(level)/5")
    }
    private func level3Caption(_ v: Int) -> String {
        ["None", "Mild", "Moderate", "Marked"][min(max(v, 0), 3)]
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: title)
            content()
        }
    }

    @ViewBuilder
    private func section<Content: View>(variable id: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VariableSectionHeader(variableID: id, trailing: trailing)
            content()
        }
    }

    private func loadExisting() {
        if let e = existing {
            load(from: e)
        } else {
            // New-entry flow: if the initial day (today) already has an entry, become an edit
            // of it — the same live-load the date scrub does.
            syncForm(to: logDate)
        }

#if DEBUG
        // Deterministic visual-QA hook: `HC_SHED_BAND 0...3` opens the sheet at a chosen
        // semantic portrait without changing seed data or production behavior.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "HC_SHED_BAND"),
           arguments.indices.contains(index + 1),
           let raw = Int(arguments[index + 1]),
           let level = ShedLevel(rawValue: min(3, max(0, raw))) {
            shed = level
        }
        if arguments.contains("HC_LOG_PORTRAIT") {
            scrollTarget = "checkInPortrait"
        }
#endif
    }

    private func load(from e: DailyEntry) {
        shed = e.shed
        washedHair = e.washedHair
        flakeI = CGFloat(min(max(e.flaking, 0), 3)) / 3
        redI = CGFloat(min(max(e.erythema, 0), 3)) / 3
        itchI = CGFloat(min(max(e.itch, 0), 3)) / 3
        oilI = CGFloat(min(max(e.oiliness, 0), 3)) / 3
        sleepI = CGFloat(min(max(e.sleepQuality, 1), 5) - 1) / 4
        stressI = CGFloat(min(max(e.stress, 1), 5) - 1) / 4
        cigarettes = e.cigarettes
        alcoholDrinks = e.alcoholDrinks
        note = e.note
    }

    /// Live-load when the scrubbed day already has an entry, so the sheet becomes an edit of
    /// that day. Leaving a matched day for an empty one resets the form to defaults so the
    /// gauges never show another day's values against an empty day.
    private func syncForm(to day: Date) {
        let found = fetchEntry(on: day)
        if let found {
            load(from: found)
        } else if matchedEntry != nil {
            resetForm()
        }
        matchedEntry = found
    }

    private func resetForm() {
        shed = .normal
        washedHair = false
        flakeI = 0; redI = 0; itchI = 0; oilI = 0
        sleepI = 0.5; stressI = 0.5
        cigarettes = 0; alcoholDrinks = 0
        note = ""
    }

    /// The one-entry-per-day guard: the first `DailyEntry` whose date falls inside the
    /// calendar day, fetched with two captured Date constants (SwiftData predicates can't
    /// call Calendar).
    private func fetchEntry(on day: Date) -> DailyEntry? {
        let bounds = HairAnalytics.dayBounds(for: day)
        let lower = bounds.lowerBound
        let upper = bounds.upperBound
        var descriptor = FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.date >= lower && $0.date < upper },
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        // Reward diff: capture the record before the upsert. The snapshots hold model
        // references, which is safe here — the engines only read fields this save never
        // mutates (dates/timestamps), and a newly inserted entry isn't in the before arrays.
        let before = CheckInReward.Snapshot(context: context)

        let target: DailyEntry
        if let e = existing {
            target = e
        } else if let sameDay = fetchEntry(on: logDate) {
            // Upsert: a row for this calendar day already exists — write into it,
            // never insert a duplicate.
            target = sameDay
        } else {
            target = DailyEntry(date: HairAnalytics.normalizedLogDate(for: logDate))
            context.insert(target)
        }
        target.shed = shed
        target.washedHair = washedHair
        target.flaking = flaking
        target.erythema = erythema
        target.itch = itch
        target.sleepQuality = sleepQuality
        target.stress = stress
        target.cigarettes = cigarettes
        target.alcoholDrinks = alcoholDrinks
        target.oiliness = oiliness
        target.note = note

        let after = CheckInReward.Snapshot(context: context)
        let reward = CheckInReward.build(before: before, after: after)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()

        // The no-celebrate-on-pure-edit rule: only a save that earned something (a new
        // logged day's XP, or a badge) triggers the celebration. Editing an existing
        // entry's values yields xpGained == 0 and no new badges → no celebration.
        if reward.isWorthCelebrating {
            onSaved?(reward)
        }
    }
}

/// The scalp composite should feel like a current condition, not a spreadsheet subtotal. Pulse
/// strength rises gently with the score; the label remains calm and categorical. Reduce Motion
/// holds the same cue as a static dot.
private struct AnimatedSeverityReadout: View {
    let total: Int
    let band: SeverityBand

    private var color: Color { Clinical.bandColor(band) }
    private var intensity: CGFloat { CGFloat(min(max(total, 0), 16)) / 16 }

    var body: some View {
        MotionTimeline(cadence: .decorative) { timeline, reduceMotion in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 60)
            let wave = reduceMotion
                ? 0.0
                : (sin(seconds * (1.7 + Double(intensity) * 1.5)) + 1) / 2

            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .stroke(color.opacity(0.34 * wave), lineWidth: 2)
                            .scaleEffect(1 + wave * (0.45 + Double(intensity) * 0.45))
                    }
                Text("\(total)/16 · \(band.title)")
                    .font(Clinical.number(12))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
            }
        }
        .animation(.easeOut(duration: 0.2), value: total)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scalp severity \(total) out of 16, \(band.title)")
    }
}

// MARK: - V5 check-in structure and synthesis

/// A compact orientation cue so the sheet reads as a short guided journey rather than a long
/// clinical form. It deliberately avoids fake completion percentages: every chapter stays editable.
private struct CheckInJourneyHeader: View {
    let onSelect: (String) -> Void

    private let chapters: [(symbol: String, title: String, anchor: String)] = [
        ("waveform.path", "Hair", "checkInHair"),
        ("circle.hexagongrid", "Scalp", "checkInScalp"),
        ("heart.text.square", "Context", "checkInContext"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: "Daily portrait")
                    Text("Notice the day, not just the numbers.")
                        .font(Clinical.headline(18))
                        .foregroundStyle(Clinical.ink)
                }
                Spacer(minLength: 12)
                Text("~2 MIN")
                    .font(Clinical.eyebrow(9))
                    .tracking(0.8)
                    .foregroundStyle(Clinical.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Clinical.accent.opacity(0.09), in: Capsule())
            }

            HStack(spacing: 8) {
                ForEach(chapters, id: \.anchor) { chapter in
                    Button { onSelect(chapter.anchor) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chapter.symbol)
                                .foregroundStyle(Clinical.accent)
                            Text(chapter.title)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Clinical.canvas, in: Capsule())
                        .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.clinicalPressable)
                    .accessibilityHint("Jumps to the \(chapter.title.lowercased()) section")
                }
            }
        }
        .padding(14)
        .background(Clinical.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
        .shadow(color: Clinical.cardShadow.opacity(0.65), radius: 12, y: 5)
    }
}

/// A live, plain-language synthesis immediately before save. It reflects the values already on
/// screen and never generates a diagnosis, score, or recommendation.
private struct CheckInPortraitCard: View {
    let shed: ShedLevel
    let scalpTotal: Int
    let scalpBand: SeverityBand
    let sleepQuality: Int
    let stress: Int

    private var reflection: SheddingReflection { .make(band: shed.rawValue) }
    private var shedProgress: CGFloat { CGFloat(shed.rawValue) / 3 }
    private var scalpProgress: CGFloat { CGFloat(min(max(scalpTotal, 0), 16)) / 16 }
    private var contextProgress: CGFloat {
        let sleep = CGFloat(min(max(sleepQuality, 1), 5) - 1) / 4
        let calm = CGFloat(5 - min(max(stress, 1), 5)) / 4
        return (sleep + calm) / 2
    }
    private var contextTitle: String {
        switch contextProgress {
        case ..<0.26: return "Under strain"
        case ..<0.51: return "Mixed"
        case ..<0.76: return "Steady"
        default: return "Rested"
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CheckInPortraitOrbit(
                values: [shedProgress, scalpProgress, contextProgress],
                colors: [Clinical.accent, Clinical.bandColor(scalpBand), Clinical.sage]
            )
            .frame(width: 148, height: 148)
            .offset(x: 24, y: -28)
            .opacity(0.72)

            LinearGradient(
                colors: [Clinical.surface.opacity(0.97), Clinical.surface.opacity(0.76), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Your check-in portrait")
                    Text(reflection.title)
                        .font(Clinical.headline(27))
                        .foregroundStyle(Clinical.ink)
                        .contentTransition(.opacity)
                    Text(reflection.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Clinical.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 270, alignment: .leading)
                        .contentTransition(.opacity)
                }

                VStack(spacing: 9) {
                    PortraitMetricRow(
                        symbol: "waveform.path",
                        label: "Shedding",
                        value: shed.title,
                        progress: shedProgress,
                        tint: Clinical.accent
                    )
                    PortraitMetricRow(
                        symbol: "circle.hexagongrid",
                        label: "Scalp",
                        value: "\(scalpTotal)/16 · \(scalpBand.title)",
                        progress: scalpProgress,
                        tint: Clinical.bandColor(scalpBand)
                    )
                    PortraitMetricRow(
                        symbol: "heart.text.square",
                        label: "Body context",
                        value: contextTitle,
                        progress: contextProgress,
                        tint: Clinical.sage
                    )
                }

                Label("One day is context. The pattern becomes useful over time.", systemImage: "calendar.badge.clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Clinical.tertiary)
            }
            .padding(18)
        }
        .background(
            LinearGradient(
                colors: [Clinical.surface, Clinical.canvas, Clinical.accent.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Clinical.accent.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Clinical.cardShadow, radius: 14, y: 6)
        .animation(.easeOut(duration: 0.24), value: shed)
        .animation(.easeOut(duration: 0.24), value: scalpTotal)
        .animation(.easeOut(duration: 0.24), value: contextProgress)
    }
}

private struct PortraitMetricRow: View {
    let symbol: String
    let label: String
    let value: String
    let progress: CGFloat
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Clinical.secondary)
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                        .contentTransition(.numericText())
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(Clinical.hairline.opacity(0.72))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(tint)
                                .frame(width: max(5, geo.size.width * min(1, max(0, progress))))
                        }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 43)
        .background(Clinical.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Clinical.hairline.opacity(0.78), lineWidth: 1)
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: progress)
    }
}

/// Three status-driven compass arcs. Arc length carries magnitude; the slow orbit only conveys
/// continuity and freezes to the same data-bearing frame under Reduce Motion.
private struct CheckInPortraitOrbit: View {
    let values: [CGFloat]
    let colors: [Color]

    var body: some View {
        MotionTimeline(cadence: .decorative) { timeline, reduceMotion in
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 60)

                for index in 0..<min(values.count, colors.count) {
                    let radius = min(size.width, size.height) * (0.43 - CGFloat(index) * 0.095)
                    let value = min(1, max(0, values[index]))
                    let rotation = reduceMotion ? 0 : seconds * (0.10 + Double(index) * 0.025)
                    let start = -Double.pi / 2 + rotation
                    let end = start + Double.pi * 2 * Double(max(0.08, value))

                    var track = Path()
                    track.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .radians(start),
                        endAngle: .radians(start + Double.pi * 2),
                        clockwise: false
                    )
                    ctx.stroke(track, with: .color(Clinical.hairline.opacity(0.46)), lineWidth: 2)

                    var arc = Path()
                    arc.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .radians(start),
                        endAngle: .radians(end),
                        clockwise: false
                    )
                    ctx.stroke(
                        arc,
                        with: .color(colors[index].opacity(0.72)),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )

                    let dot = CGPoint(
                        x: center.x + cos(end) * radius,
                        y: center.y + sin(end) * radius
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: dot.x - 2.5, y: dot.y - 2.5, width: 5, height: 5)),
                        with: .color(colors[index])
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
