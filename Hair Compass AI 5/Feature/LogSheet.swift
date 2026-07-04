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

    /// The calendar day this log belongs to. Scrubbable (up to 60 days back) when creating a
    /// new entry; fixed to the entry's own day when editing an existing one.
    @State private var logDate: Date
    /// When creating a new entry and the scrubbed day already has one, that entry — the form
    /// shows its values and save() writes into it instead of inserting a duplicate.
    @State private var matchedEntry: DailyEntry?

    @State private var shed: ShedLevel = .normal
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
                    }

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

                    section("Note") {
                        TextField("Anything worth remembering", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(Clinical.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Clinical.hairline, lineWidth: 1)
                            )
                    }

                    Button(saveButtonTitle, action: save)
                        .buttonStyle(ClinicalButtonStyle())
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .clinicalScreen()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
        Text("\(scalpTotal)/16 · \(scalpBand.title)")
            .font(Clinical.number(12))
            .foregroundStyle(Clinical.bandColor(scalpBand))
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
    }

    private func load(from e: DailyEntry) {
        shed = e.shed
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
