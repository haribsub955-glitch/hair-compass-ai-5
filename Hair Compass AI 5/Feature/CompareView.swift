import Charts
import SwiftData
import SwiftUI

/// Explore an outcome against recorded context or around a dated event. Comparisons remain
/// descriptive, and missing observations never become symptom-free or missed-dose days.
struct CompareView: View {
    var initialEventID: String? = nil
    enum Mode: String, CaseIterable { case signals = "Signals", event = "Around a change" }
    @State private var mode: Mode = .signals
    @State private var selectedEventID: String?
    @State private var eventDays = 28
    @State private var sideEffectType: SideEffectType?
    @Query private var procedures: [ProcedureAppointment]
    @Query private var missedDoses: [MissedDoseRecord]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \DailyEntry.date) private var entries: [DailyEntry]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]

    // The rest of the record, queried only to build the chat's AIContext snapshot on demand
    // (same pattern as DeepAnalysisSheet).
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query(sort: \TriggerEvent.date) private var triggers: [TriggerEvent]
    @Query(sort: \LabResult.collectedAt) private var labs: [LabResult]
    @Query private var sideEffects: [SideEffectLog]
    @Query(sort: \PhotoRecord.createdAt) private var photos: [PhotoRecord]
    @Query private var profiles: [Profile]
    @Query(sort: \ProgressCheckIn.date) private var progressCheckIns: [ProgressCheckIn]

    @State private var hairID = "shed"
    @State private var overlayID = "sleepQuality"
    @State private var window: Window = .m3
    @State private var lag: Lag = .none

    @State private var showChat = false
    @State private var chatDetent: PresentationDetent = .large
    @State private var chatContext = ""

    enum Window: String, CaseIterable { case m1 = "1M", m3 = "3M", m6 = "6M", y1 = "1Y", all = "All"
        var days: Int { switch self { case .m1: return 30; case .m3: return 90; case .m6: return 180; case .y1: return 365; case .all: return 3650 } }
    }
    enum Lag: String, CaseIterable { case none = "0", w2 = "2wk", w6 = "6wk", m3 = "3mo"
        var days: Int { switch self { case .none: return 0; case .w2: return 14; case .w6: return 42; case .m3: return 90 } }
    }

    private var outcomes: [ChartMetric] {
        ChartMetric.hairFall + [ChartMetric(id: "sideEffects", title: "Side effects", group: .hairFall, unit: "severity 1–3")]
    }
    private var hair: ChartMetric { outcomes.first { $0.id == hairID } ?? ChartMetric.hairFall[0] }
    private var overlay: ChartMetric { ChartMetric[overlayID] ?? treatmentMetrics.first { $0.id == overlayID } ?? ChartMetric.lifestyle[0] }

    // Keep archived items available and use persistent identity, so renaming or adding an item
    // cannot silently select a different medication. Every plan item has an event comparison.
    private var trackedTreatments: [Treatment] { treatments.sorted { $0.startDate < $1.startDate } }
    private func metricID(_ treatment: Treatment) -> String { "tx.\(TrendContext.recordKey(treatment))" }
    private var treatmentMetrics: [ChartMetric] {
        trackedTreatments.map { treatment in
            ChartMetric(id: metricID(treatment), title: treatment.name.isEmpty ? treatment.treatmentClass.title : treatment.name,
                        group: .treatment, unit: "logged doses/day")
        }
    }
    private func treatment(forMetricID id: String) -> Treatment? {
        trackedTreatments.first { metricID($0) == id }
    }

    private var highlights: [TrendHighlight] {
        TrendContext.highlights(treatments: treatments, procedures: procedures, photos: photos,
                                progress: progressCheckIns, sideEffects: sideEffects,
                                triggers: triggers, entries: entries, start: .distantPast, end: .now)
    }
    private var selectedEvent: TrendHighlight? {
        highlights.first { $0.id == selectedEventID } ?? highlights.first { $0.kind == .start } ?? highlights.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: "Explore relationships", title: "Compare").padding(.top, 8)
                Text("Choose an outcome, then compare daily signals or look around a dated change.")
                    .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                ClinicalSegmented(options: Mode.allCases, label: { $0.rawValue }, selection: $mode)
                outcomePicker
                if mode == .signals {
                    presets
                    medicationMenu
                    pickers
                    ClinicalSegmented(options: Window.allCases, label: { $0.rawValue }, selection: $window)
                    chartCard
                    lagCard
                    readCard
                } else {
                    eventComparison
                }
                TrendHighlightsCard(highlights: visibleHighlights) { item in
                    selectedEventID = item.id
                    mode = .event
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .clinicalScreen()
        .sheet(isPresented: $showChat) {
            HairChatSheet(contextJSON: chatContext, focus: focusLine)
                .presentationDetents([.medium, .large], selection: $chatDetent)
        }
        .onAppear {
            if let initialEventID { selectedEventID = initialEventID; mode = .event }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_CHAT") { openChat() }
            #endif
        }
    }

    private var outcomePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Outcome")
            Picker("Outcome", selection: $hairID) {
                ForEach(outcomes) { outcome in Text(outcome.title).tag(outcome.id) }
            }
            .pickerStyle(.menu).tint(Clinical.accent)
            .accessibilityIdentifier("comparisonOutcome")
            if hairID == "sideEffects" {
                Picker("Side-effect type", selection: $sideEffectType) {
                    Text("All reported types").tag(Optional<SideEffectType>.none)
                    ForEach(SideEffectType.allCases) { type in Text(type.title).tag(Optional(type)) }
                }
                .pickerStyle(.menu).tint(Clinical.accent)
                .accessibilityIdentifier("comparisonSideEffectType")
            }
        }
    }

    private var recordingNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hairID == "sideEffects" {
                Text("Only days with a side-effect report are compared. Blank days are unknown, so this cannot show how often you were symptom-free.")
            }
            if treatment(forMetricID: overlayID) != nil && mode == .signals {
                Text("Plan points use recorded doses and explicitly missed doses. Unlogged days stay unknown. Use Around a change to explore when you added or stopped an item.")
            }
            if overlay.group == .body && mode == .signals {
                Text("Apple Health values come from your synced record. Missing Health readings are left blank.")
            }
        }
        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
    }

    @ViewBuilder
    private var eventComparison: some View {
        if let event = selectedEvent {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Plan change or highlight")
                    Menu {
                        ForEach(TrendHighlight.Kind.allCases) { kind in
                            let items = highlights.filter { $0.kind == kind }
                            if !items.isEmpty {
                                Section(kind.rawValue) {
                                    ForEach(items) { item in
                                        Button("\(item.title) · \(item.date.formatted(date: .abbreviated, time: .omitted))") {
                                            selectedEventID = item.id
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title).font(Clinical.body(16, weight: .semibold))
                                Text(event.date.formatted(date: .abbreviated, time: .omitted)).font(Clinical.caption(12))
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .foregroundStyle(Clinical.accent)
                    }
                    .accessibilityIdentifier("comparisonEvent")
                    ClinicalSegmented(options: [14, 28, 56], label: { "\($0) days" }, selection: $eventDays)
                    Text("The selected number of days on each side of this date.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.secondary)
                }
            }
            EventObservationCard(event: event, points: series(for: hairID), title: hair.title,
                                 unit: hair.unit, days: eventDays, isSideEffect: hairID == "sideEffects")
            recordingNote
            let otherChanges = visibleHighlights.filter { $0.id != event.id && [.start, .stop, .procedure, .trigger].contains($0.kind) }
            if !otherChanges.isEmpty {
                Text("\(otherChanges.count) other plan or life event\(otherChanges.count == 1 ? "" : "s") occurred in this period. You can inspect them in Highlights below.")
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
            }
            askWrenChip
        } else {
            ClinicalCard {
                Text("Add a medication or care item to your plan, record a procedure, or save a photo. Its date will appear here for a before-and-after comparison.")
                    .font(Clinical.body(14)).foregroundStyle(Clinical.secondary)
            }
        }
    }

    // MARK: Selection

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                presetChip("Shedding vs Sleep", "shed", "sleepQuality")
                presetChip("Shedding vs Stress", "shed", "stress")
                presetChip("Side effects vs Sleep", "sideEffects", "sleepHours")
                presetChip("Shedding vs Weight", "shed", "bodyMass")
                if !trackedTreatments.isEmpty {
                    presetChip(
                        "Shedding vs \(trackedTreatments[0].name.isEmpty ? trackedTreatments[0].treatmentClass.title : trackedTreatments[0].name)",
                        "shed", metricID(trackedTreatments[0])
                    )
                }
            }
        }
    }

    private func presetChip(_ title: String, _ h: String, _ o: String) -> some View {
        let on = hairID == h && overlayID == o
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { hairID = h; overlayID = o }
        } label: {
            Text(title)
                .font(Clinical.body(12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? Clinical.accent : Clinical.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
        }
        .buttonStyle(.clinicalPressable)
    }

    /// Direct access to all recorded plan items, including those the user has stopped.
    @ViewBuilder
    private var medicationMenu: some View {
        if !trackedTreatments.isEmpty {
            Menu {
                ForEach(trackedTreatments, id: \.persistentModelID) { t in
                    Button {
                        overlayID = metricID(t)
                    } label: {
                        Label(
                            t.name.isEmpty ? t.treatmentClass.title : t.name,
                            systemImage: overlayID == metricID(t) ? "checkmark" : t.treatmentClass.symbol
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pills.fill").font(Clinical.caption(11))
                    Text(selectedTreatmentTitle ?? "Compare a plan item")
                        .font(Clinical.body(12, weight: selectedTreatmentTitle == nil ? .regular : .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(Clinical.body(9, weight: .semibold))
                }
                .foregroundStyle(selectedTreatmentTitle == nil ? Clinical.accent : Clinical.surface)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selectedTreatmentTitle == nil ? Clinical.accentSoft : Clinical.accent)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(selectedTreatmentTitle == nil ? Clinical.accent.opacity(0.35) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.clinicalPressable)
        }
    }

    /// Keep the plan picker label in sync with the selected persistent treatment.
    private var selectedTreatmentTitle: String? {
        guard let t = treatment(forMetricID: overlayID) else { return nil }
        return t.name.isEmpty ? t.treatmentClass.title : t.name
    }

    private var pickers: some View {
        ClinicalCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Compare with")
                Picker("Compare with", selection: $overlayID) {
                    ForEach([MetricGroup.lifestyle, .body, .treatment]) { group in
                        Section(group == .body ? "Apple Health" : group.rawValue) {
                            ForEach((ChartMetric.lifestyle + treatmentMetrics).filter { $0.group == group }) { metric in
                                Text(metric.title).tag(metric.id)
                            }
                        }
                    }
                }
                .pickerStyle(.menu).tint(Clinical.sage)
                .accessibilityIdentifier("comparisonContext")
            }
        }
    }

    // MARK: Chart

    /// Overlapping days needed before the real chart replaces the illustrative preview — matches
    /// `previewLocked`'s copy and `ChartMath.association`'s honesty gate is separate (8 pairs) but
    /// deliberately close, so a comparison that's just unlocked the chart is also close to a read.
    private static let readyThreshold = 7

    private var chartCard: some View {
        let hairPts = series(for: hairID)
        let overlayPts = alignedOverlay
        let overlapDays = ChartMath.pairWithLag(
            hair: hairPts, lifestyle: overlayPts, lagDays: 0, tolerance: 0
        ).hair.count
        let ready = overlapDays >= Self.readyThreshold
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                legend(hairPts: hairPts, overlayPts: overlayPts)
                if !ready {
                    previewLocked(daysLogged: overlapDays)
                } else {
                    Chart {
                        // Side-effect reports are discrete observations; gaps remain unscored.
                        if hairID == "sideEffects" {
                            ForEach(normalizedMarks(hairPts, name: hair.title), id: \.0) { date, value, _ in
                                PointMark(x: .value("Date", date), y: .value("Level", value))
                                    .foregroundStyle(Clinical.ink).symbolSize(36)
                            }
                        } else {
                            // Faint daily reality behind the trend — kept visible for honesty.
                            ForEach(normalizedMarks(hairPts, name: hair.title + " (daily)"), id: \.0) { date, v, name in
                                LineMark(x: .value("Date", date), y: .value("Level", v), series: .value("s", name))
                                    .interpolationMethod(.monotone).lineStyle(.init(lineWidth: 1))
                                    .foregroundStyle(Clinical.ink.opacity(0.22))
                            }
                        }
                        ForEach(normalizedMarks(overlayPts, name: overlay.title + " (daily)"), id: \.0) { date, v, name in
                            LineMark(x: .value("Date", date), y: .value("Level", v), series: .value("s", name))
                                .interpolationMethod(.monotone).lineStyle(.init(lineWidth: 1))
                                .foregroundStyle(Clinical.sage.opacity(0.22))
                        }
                        // Smoothed rolling-mean trend on top — this is the line to read.
                        if hairID != "sideEffects" {
                            ForEach(smoothedMarks(hairPts, name: hair.title), id: \.0) { date, v, name in
                                LineMark(x: .value("Date", date), y: .value("Level", v), series: .value("s", name))
                                    .interpolationMethod(.monotone).lineStyle(.init(lineWidth: 2.5))
                                    .foregroundStyle(Clinical.ink)
                            }
                        }
                        ForEach(smoothedMarks(overlayPts, name: overlay.title), id: \.0) { date, v, name in
                            LineMark(x: .value("Date", date), y: .value("Level", v), series: .value("s", name))
                                .interpolationMethod(.monotone).lineStyle(.init(lineWidth: 2.5))
                                .foregroundStyle(Clinical.sage)
                        }
                    }
                    .frame(height: 170)
                    .chartYScale(domain: 0...1)
                    .chartXScale(domain: cutoff...Date.now)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: window == .m1 ? .weekOfYear : (window == .all ? .year : .month))) { value in
                            AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                            AxisValueLabel {
                                if let d = value.as(Date.self) {
                                    Text(d.formatted(window == .m1 ? .dateTime.month(.abbreviated).day() : (window == .all ? .dateTime.year() : .dateTime.month(.abbreviated)))).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                                }
                            }
                        }
                    }
                    Text("Each signal uses its own range. Lines show a trailing \(smoothWindow)-day average; side-effect dots show the highest severity reported that day. \(lag.days == 0 ? "Dates align on the same day." : "Context is shifted forward \(lag.days) days to align with the later outcome.")")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
    }

    // MARK: Faded illustrative preview (< 7 overlapping days)

    /// Honest "not enough data yet" state: the shared shaded placeholder at the real chart's
    /// height, so nothing visually jumps the moment the comparison crosses the 7-day threshold.
    private func previewLocked(daysLogged: Int) -> some View {
        ChartPlaceholder(required: Self.readyThreshold, have: daysLogged, unit: .days, height: 170)
    }

    private func legend(hairPts: [(day: Date, value: Double)], overlayPts: [(day: Date, value: Double)]) -> some View {
        HStack(spacing: 16) {
            legendItem(color: Clinical.ink, title: hair.title, pts: hairPts, unit: hair.unit)
            legendItem(color: Clinical.sage, title: overlay.title, pts: overlayPts, unit: overlay.unit)
            Spacer()
        }
    }

    private func legendItem(color: Color, title: String, pts: [(day: Date, value: Double)], unit: String) -> some View {
        let range: String = {
            guard let lo = pts.map(\.value).min(), let hi = pts.map(\.value).max() else { return "—" }
            return lo == hi ? fmt(lo) : "\(fmt(lo))–\(fmt(hi))"
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Clinical.body(12, weight: .medium)).foregroundStyle(Clinical.ink)
                Text("\(range) \(unit)").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    private var lagCard: some View {
        ClinicalCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Time lag")
                Text("Explore whether the two patterns line up on the same day or after a delay. This cannot establish cause and effect.")
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                ClinicalSegmented(options: Lag.allCases, label: { $0.rawValue }, selection: $lag)
                    // Spring the copper pill between lag options; Reduce Motion keeps the
                    // segmented control's stock quick ease.
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.3, dampingFraction: 0.75),
                        value: lag
                    )
            }
        }
    }

    @ViewBuilder
    private var readCard: some View {
        let paired = ChartMath.pairWithLag(hair: series(for: hairID), lifestyle: alignedOverlay, lagDays: 0, tolerance: 0)
        let assoc = ChartMath.association(hair: paired.hair, lifestyle: paired.lifestyle)
        if case .insufficient(let need) = assoc {
            // Short of pairs: the same pill every locked chart shows, on the bare canvas — the
            // pill already carries its own chrome, so a card around it would be a box in a box.
            VStack(alignment: .leading, spacing: 12) {
                ChartPlaceholderPill(required: need, have: paired.hair.count, unit: .pairedDays)
                recordingNote
                askWrenChip
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkle.magnifyingglass").font(Clinical.caption(15)).foregroundStyle(Clinical.accent)
                        Text(ChartMath.phrasing(assoc, hairTitle: hair.title, lifestyleTitle: overlay.title, lagDays: lag.days))
                            .font(Clinical.caption(14)).foregroundStyle(Clinical.ink)
                    }
                    recordingNote
                    askWrenChip
                }
            }
        }
    }

    // MARK: Chat entry point

    /// Same chip language as the presets above: a capsule action that opens the restricted
    /// hair-science chat over the comparison on screen.
    private var askWrenChip: some View {
        Button { openChat() } label: {
            Label("Ask \(Companion.name) about this", systemImage: "bubble.left.and.text.bubble.right")
                .font(Clinical.body(12, weight: .semibold))
                .foregroundStyle(Clinical.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Clinical.accentSoft)
                .clipShape(Capsule())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel("Ask \(Companion.name) about this comparison")
    }

    /// One line telling the chat what's on screen, so answers land on it.
    private var focusLine: String {
        let lagText = lag == .none ? "no time lag" : "context from \(lag.days) days earlier"
        if mode == .event, let selectedEvent {
            return "User is viewing recorded \(hair.title) before and after \(selectedEvent.title) on \(selectedEvent.date), \(eventDays)-day windows. Descriptive observations only; no causal or efficacy inference."
        }
        return "User is comparing recorded \(hair.title) vs \(overlay.title), \(window.rawValue) window, \(lagText). Missing reports are unknown. Association is not causation."
    }

    /// Snapshot the canonical AIContext at open time — the chat consumes the same versioned
    /// JSON record as the deep analysis. Text only; photo METADATA in the context, never pixels.
    private func openChat() {
        chatContext = AIContext.build(
            entries: entries, treatments: treatments, doses: doses,
            snapshots: snapshots, triggers: triggers,
            labs: labs, sideEffects: sideEffects, photos: photos,
            profile: profiles.first, progressCheckIns: progressCheckIns, now: .now
        ).jsonString()
        showChat = true
    }

    // MARK: Data

    private var cutoff: Date {
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .day, value: -(window.days - 1), to: today) ?? today
    }
    private var visibleHighlights: [TrendHighlight] {
        if mode == .event, let event = selectedEvent {
            let comparison = TrendContext.compare(points: [], event: event.date, days: eventDays)
            return highlights.filter { $0.date >= comparison.beforeStart && $0.date < comparison.afterEnd }
        }
        return highlights.filter { $0.date >= cutoff }
    }
    private var alignedOverlay: [(day: Date, value: Double)] {
        TrendContext.aligned(series(for: overlayID), lagDays: lag.days, start: cutoff, end: .now)
    }

    private func series(for id: String) -> [(day: Date, value: Double)] {
        let start: Date = mode == .event ? .distantPast :
            (id == overlayID ? Calendar.current.date(byAdding: .day, value: -lag.days, to: cutoff) ?? cutoff : cutoff)
        let e = entries.filter { $0.date >= start && $0.date <= .now }
        let s = snapshots.filter { $0.date >= start && $0.date <= .now }
        let pairs: [(Date, Double)]
        switch id {
        case "sideEffects":
            return TrendContext.sideEffectSeries(sideEffects, type: sideEffectType, start: start, end: .now)
        case "shed": pairs = e.filter { $0.hasRecorded(.shedding) }.map { ($0.date, Double($0.shed.rawValue)) }
        case "scalp": pairs = e.filter(\.hasCompleteScalpRecording).map { ($0.date, Double($0.scalpTotal)) }
        case "oiliness": pairs = e.filter { $0.hasRecorded(.oiliness) }.map { ($0.date, Double($0.oiliness)) }
        case "sleepQuality": pairs = e.filter { $0.hasRecorded(.sleepQuality) }.map { ($0.date, Double($0.sleepQuality)) }
        case "stress": pairs = e.filter { $0.hasRecorded(.stress) }.map { ($0.date, Double($0.stress)) }
        case "cigarettes": pairs = e.filter { $0.hasRecorded(.cigarettes) }.map { ($0.date, Double($0.cigarettes)) }
        case "alcohol": pairs = e.filter { $0.hasRecorded(.alcohol) }.map { ($0.date, Double($0.alcoholDrinks)) }
        case "sleepHours": pairs = s.compactMap { snap in snap.sleepHours.map { (snap.date, $0) } }
        case "hrv": pairs = s.compactMap { snap in snap.hrvSDNN.map { (snap.date, $0) } }
        case "restingHR": pairs = s.compactMap { snap in snap.restingHR.map { (snap.date, $0) } }
        case "bodyMass": pairs = s.compactMap { snap in snap.bodyMassKg.map { (snap.date, $0) } }
        case "protein": pairs = s.compactMap { snap in snap.dietaryProteinG.map { (snap.date, $0) } }
        case let id where id.hasPrefix("tx."):
            if let t = treatment(forMetricID: id) {
                pairs = TrendContext.doseSeries(treatment: t, doses: doses, missed: missedDoses, start: start, end: .now).map { ($0.day, $0.value) }
            } else {
                pairs = []
            }
        default: pairs = []
        }
        return ChartMath.dailyAverages(pairs.map { (day: $0.0, value: $0.1) })
    }

    private func normalizedMarks(_ pts: [(day: Date, value: Double)], name: String) -> [(Date, Double, String)] {
        let norm = ChartMath.normalize(pts.map(\.value))
        return zip(pts, norm).map { ($0.0.day, $0.1, name) }
    }

    /// Rolling-mean window for the smoothed trend — wider for the longer chart windows.
    private var smoothWindow: Int { window == .m1 ? 5 : 7 }

    /// The smoothed display series: trailing calendar mean of daily values, then normalized to
    /// 0…1 by its own range. Missing days stay missing and no future value leaks backward.
    private func smoothedMarks(_ pts: [(day: Date, value: Double)], name: String) -> [(Date, Double, String)] {
        let trailing = ChartMath.trailingCalendarMean(pts, windowDays: smoothWindow)
        let lo = pts.map(\.value).min() ?? 0
        let hi = pts.map(\.value).max() ?? 0
        let smooth = trailing.map { hi > lo ? ($0.value - lo) / (hi - lo) : 0.5 }
        return zip(trailing, smooth).map { ($0.0.day, $0.1, name) }
    }

    private func fmt(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)))
    }
}
