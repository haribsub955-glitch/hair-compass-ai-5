import Charts
import SwiftData
import SwiftUI

/// The app's headline visualization: one time-aligned timeline answering "what happened to my
/// shedding, and what was I doing about it?" A smoothed shed trend with dated event markers
/// (procedures, medication starts, telogen-effluvium triggers) sits above a day-by-day
/// medication-intake lane; both sub-charts share one x domain so cause and effect line up.
struct JourneyChart: View {
    let entries: [DailyEntry]
    let treatments: [Treatment]
    let doses: [TreatmentDose]
    let triggers: [TriggerEvent]
    /// Completed in-office procedures (PRP, microneedling, a transplant, LLLT…) — drawn as
    /// `.procedure` markers. Previously that marker kind could only ever come from a
    /// schedule-less `Treatment` row, which real procedures never are (they're booked through
    /// `ProcedureAppointment`/`AddProcedureSheet`), so the "Procedure" legend key was
    /// effectively dead. Defaults to empty so existing call sites keep compiling.
    var procedures: [ProcedureAppointment] = []
    let windowDays: Int

    private static let shedAxisValues: [Double] = [0, 1, 2, 3]
    // Complete words only — no abbreviations that could read as truncated (the same rule
    // TrendsView.yAxis already follows). "Elevated" is the widest label, so it sets the gutter.
    private static let shedAxisLabels = ShedLevel.allCases.map(\.title)

    /// Measured width of the widest axis label ("Elevated") at the live Dynamic Type size —
    /// replaces a hard-pinned 44pt gutter that broke "Elevated" onto two lines ("Elevate/d") at
    /// default size and every label at accessibility sizes. Seeded at 44 so the very first frame
    /// (before the hidden template below reports its real width) still looks reasonable.
    @State private var gutterWidth: CGFloat = 44
    /// The marker currently disclosed (tap-to-reveal) — any kind, not just notes — reset on
    /// tap-away or re-tap of the same marker. This is where the marker legend's old
    /// Procedure/Med-start/Stopped/Trigger/Note meanings now live, read on demand instead of
    /// permanently spelled out in a five-key legend.
    @State private var selectedMarker: JourneyData.Marker?
    /// Non-nil while a `.trigger` marker's disclosure "Edit" button has opened its source
    /// `TriggerEvent` in `AddTriggerSheet` — the chart's own deep link into the same edit flow
    /// `LifeEventsSheet` uses, so a mis-dated life event never has to be hunted down through
    /// Plan's ledger after being spotted here first.
    @State private var editingTrigger: TriggerEvent?

    var body: some View {
        let end = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -windowDays, to: end) ?? end
        let data = JourneyData(
            entries: entries, treatments: treatments, doses: doses,
            triggers: triggers, procedures: procedures, start: start, end: end
        )
        // Full-bleed on the canvas — the app's headline visualization earns the whole width
        // instead of sitting boxed inside another card. No "Your journey" eyebrow + serif title
        // here anymore: Trends' own page title plus its one-line trajectory annotation above
        // this view already say what the chart is, so this used to be a double heading that
        // pushed the chart itself below the fold's midline.
        VStack(alignment: .leading, spacing: 12) {
            if data.shedPoints.count < 2 {
                thinDataPlaceholder
            } else {
                // Round-9: one `RevealOnce` now drives both halves of the instrument — the shed
                // line inks across the top chart AND the dose rug rises left-to-right beneath it
                // in the same pass, instead of the line animating in while the rug below sat
                // already fully formed. The page's one focal object draws itself in as one
                // gesture, then settles completely still.
                RevealOnce { progress, elapsed in
                    VStack(alignment: .leading, spacing: 6) {
                        shedChart(data: data, domain: start...end, progress: progress, elapsed: elapsed)
                        intakeLane(data: data, domain: start...end, elapsed: elapsed)
                    }
                }
                if !data.echoBands.isEmpty { echoWindowKey }
                if let selectedMarker { markerDisclosure(selectedMarker) }
            }
        }
        .sheet(item: $editingTrigger) { AddTriggerSheet(existing: $0) }
    }

    /// One quiet margin key naming the amber band — said once, in the margin, regardless of how
    /// many echo bands are actually on screen. Round-10: the swatch-plus-caption legend pairing
    /// is gone — that was chart-legend grammar, the one dialect the app had otherwise eliminated.
    /// This is now the same footnote voice as every other margin line (12pt, `Clinical.secondary`);
    /// only the words "Amber band" carry the warning tint, so the color itself still teaches which
    /// band on the chart above is meant, without a separate swatch to look between.
    private var echoWindowKey: some View {
        (Text("Amber band").foregroundStyle(Clinical.warning)
            + Text(" — possible echo window").foregroundStyle(Clinical.secondary))
            .font(Clinical.caption(12))
    }

    // MARK: Top chart — smoothed shed trend + dated event markers

    /// The chart draws itself in once on appear — the shedding line inks across left-to-right
    /// and each event marker pops in as the ink passes its date. Driven by wall-clock elapsed
    /// time (`RevealOnce`, owned by `body` and shared with `intakeLane` below) rather than
    /// SwiftUI's animation/transaction system, since this chart sits inside `TrendsView`'s
    /// `.transaction { $0.animation = nil }` subtree — deliberately applied there so Swift
    /// Charts' own marks never interpolate when the range picker changes. An ordinary
    /// `withAnimation` reveal would be silently cancelled by that ancestor; ticking a plain
    /// elapsed-time value instead sidesteps the transaction system entirely.
    private func shedChart(data: JourneyData, domain: ClosedRange<Date>, progress: CGFloat, elapsed: TimeInterval) -> some View {
        Group {
            Chart {
                // Possible-echo bands — drawn first so every other mark sits above them. Pure
                // calendar math (trigger/stop date + 8…12 weeks) on data already queried;
                // phrased as "possible echo", never a prediction, so the honest 2–3-month causal
                // vocabulary that only ever lived in prose is now visible on the one chart
                // people actually look at when a shed spike worries them. Round-9: the band's own
                // in-plot "Possible echo window" caption is gone — words belong in the journal's
                // margin, not competing with the trend line on the instrument itself. The one
                // sentence that used to print here now lives once, below the chart, as
                // `echoWindowKey` (see `body`).
                ForEach(Array(data.echoBands.enumerated()), id: \.1.id) { _, band in
                    RectangleMark(
                        xStart: .value("Start", band.start),
                        xEnd: .value("End", band.end),
                        yStart: .value("Low", 0.0),
                        yEnd: .value("High", 3.0)
                    )
                    .foregroundStyle(Clinical.warning.opacity(0.08))
                }
                // Faint raw daily levels — the honest reality behind the smoothing. Thins as the
                // window widens: at reading distance (1M) each day is still visible; beyond that
                // the per-day dots at discrete shed levels start fusing into dotted stripes along
                // the gridlines, so they shrink at 3M/6M and drop out entirely at 1Y/All, leaving
                // the smoothed line (below) as the sole carrier of long-range trend. No data is
                // removed from the model — only this raw-dot layer scales back.
                if let rawDotStyle {
                    ForEach(data.shedPoints) { p in
                        PointMark(x: .value("Date", p.date), y: .value("Shed", p.raw))
                            .symbolSize(rawDotStyle.size)
                            .foregroundStyle(Clinical.accent.opacity(rawDotStyle.opacity))
                    }
                }
                // 7-day centered rolling mean — the trend the eye should follow.
                ForEach(data.shedPoints) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Shed", p.smoothed))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Clinical.accent.opacity(0.14), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    LineMark(x: .value("Date", p.date), y: .value("Shed", p.smoothed))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(Clinical.accent)
                }
                // Dashed verticals anchor each dated event to the trend — lightened to 0.35
                // opacity (round-7) now that the marker itself is a tick rather than a heavy dot.
                ForEach(data.markers) { m in
                    RuleMark(x: .value("Date", m.date))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(m.color.opacity(0.35))
                }
                // Event ticks — staggered onto a second row when two events land close together.
                // Meaning is tap-to-reveal only now (see `markerBadge`), so there's no permanent
                // tag label competing with the trend line for attention.
                ForEach(data.markers) { m in
                    PointMark(x: .value("Date", m.date), y: .value("Shed", m.level == 0 ? 2.82 : 2.28))
                        .symbolSize(0)
                        .annotation(
                            position: .overlay,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            markerBadge(m)
                                .modifier(MarkerPop(elapsed: elapsed, delay: markerDelay(m, domain: domain)))
                        }
                }
            }
            .frame(height: 180)
            .chartXScale(domain: domain)
            // Padded past the data's real 0...3 range so the top ("Heavy") and bottom
            // ("Minimal") axis-label text has room to render in full instead of being clipped
            // by the plot's own edge — the data itself (and the echo bands, which still span
            // exactly 0...3) simply sits with a little breathing room inside the frame.
            .chartYScale(domain: -0.3...3.3)
            .chartXAxis(.hidden) // the intake lane below owns the shared time axis
            .chartYAxis {
                AxisMarks(position: .leading, values: Self.shedAxisValues) { value in
                    AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            let i = Int(v)
                            if Self.shedAxisLabels.indices.contains(i) {
                                Text(Self.shedAxisLabels[i])
                                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                                    .lineLimit(1).fixedSize()   // never wrap mid-word
                                    .frame(width: gutterWidth, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: max(0, geo.size.width * progress))
                }
            }
            // The on-plot "SHEDDING" caps label is gone (round-11) — the series was already
            // named twice above the chart (page context + the trajectory sentence), so a third
            // on-plot utterance broke the "said exactly once" rule. VoiceOver still hears what
            // the chart is via this label instead of the removed visual text.
            .accessibilityLabel("Shedding trend, 7-day average")
        }
    }

    /// Normalized 0…1 position of a marker's date within the chart's domain — used both to
    /// stagger its pop-in delay against `RevealOnce`'s reveal duration and (were it needed) to
    /// place it relative to the mask.
    private func markerDelay(_ m: JourneyData.Marker, domain: ClosedRange<Date>) -> Double {
        let total = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard total > 0 else { return 0 }
        let fraction = max(0, min(1, m.date.timeIntervalSince(domain.lowerBound) / total))
        return fraction * RevealTiming.duration
    }

    /// A dose bar's own quick fade-up as the shed line's ink-in front passes its day — the same
    /// elapsed-time/delay/smoothstep shape as `MarkerPop`, just applied to a static per-mark
    /// `.opacity()` (Charts marks don't accept an arbitrary `ViewModifier`, only a scalar value)
    /// so the rug rises left-to-right in the same pass as the line above it. `elapsed` is
    /// `.greatestFiniteMagnitude` once the reveal is done or under Reduce Motion, so every bar
    /// resolves to fully opaque then.
    private func barRevealOpacity(_ bar: JourneyData.DoseBar, domain: ClosedRange<Date>, elapsed: TimeInterval) -> Double {
        let total = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard total > 0 else { return 1 }
        let fraction = max(0, min(1, bar.day.timeIntervalSince(domain.lowerBound) / total))
        let delay = fraction * RevealTiming.duration
        let local = max(0, elapsed - delay)
        let t = max(0, min(1, local / MarkerPop.popDuration))
        return t * t * (3 - 2 * t) // smoothstep, same easing as MarkerPop
    }

    /// Round-5: shrunk from a 20×20 "balloon" (white disc, stroked ring, drop shadow, permanent
    /// tag label) to a small solid glyph dot sitting right on its dashed vertical. Round-7: lightened
    /// further, from that haloed dot to an 8pt tick — the chart's heaviest ink used to mark its
    /// least important events (a tap-to-reveal detail), competing with the trend line itself for
    /// attention. A plain tick still carries its kind's own color (procedure copper, start gold,
    /// stop grey, trigger warning, note sage) since that's real information, not decoration.
    private func markerBadge(_ m: JourneyData.Marker) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedMarker = (selectedMarker?.id == m.id) ? nil : m
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Capsule()
                .fill(m.color)
                .frame(width: 2.5, height: 8)
                .contentShape(Rectangle().inset(by: -10)) // keeps a comfortable tap target
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(markerKindLabel(m)) on \(m.date.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityHint("Double-tap for details")
    }

    /// The disclosed marker's date + meaning, dismissible by re-tapping its badge. Sits below
    /// the legend so nothing about the chart's layout shifts when a marker opens or closes —
    /// this is now where every marker kind's meaning lives (see `markerKindLabel`), not just
    /// notes, since the legend itself dropped its five marker keys. A `.trigger` marker carries
    /// its source `TriggerEvent` (`triggerRef`), so it alone gets a trailing "Edit" affordance —
    /// the one marker kind the app previously had no way to correct once dated wrong.
    private func markerDisclosure(_ marker: JourneyData.Marker) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: marker.symbol)
                .font(Clinical.caption(12)).foregroundStyle(marker.color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(marker.date.formatted(date: .abbreviated, time: .omitted))
                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                Text(markerKindLabel(marker))
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let triggerRef = marker.triggerRef {
                Button("Edit") { editingTrigger = triggerRef }
                    .font(Clinical.body(12, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this life event to edit its date, type, or note")
            }
        }
        .padding(10)
        .background(Clinical.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Plain-language meaning for a marker — what the old five-key legend used to spell out
    /// permanently now lives here, read on tap instead of taking up screen space on every visit.
    private func markerKindLabel(_ m: JourneyData.Marker) -> String {
        switch m.kind {
        case .procedure: return "Procedure — \(m.tag)"
        case .start: return "Started — \(m.tag)"
        case .stop: return "Stopped — \(m.tag)"
        case .trigger: return "Life event — \(m.tag)"
        case .note: return m.noteText ?? "Note"
        }
    }

    // MARK: Bottom lane — day-by-day medication intake

    @ViewBuilder
    private func intakeLane(data: JourneyData, domain: ClosedRange<Date>, elapsed: TimeInterval) -> some View {
        if data.doseBars.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "pills")
                    .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                Text("No medication logged yet")
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Clinical.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            // Round-5: the lane used to color every bar by medication class (a two-color
            // "barcode" competing with the trend chart above it). It's now a single muted ink —
            // the honest record of "doses were taken" — with copper reserved for the current
            // window only (the trailing 7 days), so the eye still finds "am I keeping up right
            // now" without every past week shouting in saturated color.
            let recentCutoff = Calendar.current.date(byAdding: .day, value: -7, to: domain.upperBound) ?? domain.upperBound
            Chart {
                // Round-9: each bar rises in step with the shed line's own ink-in — the reveal
                // front (driven by the same `elapsed` clock `shedChart` uses) passes each bar's
                // x-position and fades it up, so the rug joins the page's one draw-in gesture
                // instead of sitting inert while only the line above it animates.
                ForEach(data.doseBars) { bar in
                    BarMark(
                        x: .value("Day", bar.day, unit: .day),
                        y: .value("Doses", bar.count)
                    )
                    // Round-12: thinned to 0.16 (from 0.25) so the past-window rug recedes to a
                    // watermark under the journey line rather than a second chart competing with
                    // it — the trailing 7 days stay full copper, unchanged.
                    .foregroundStyle(bar.day >= recentCutoff ? Clinical.accent : Clinical.ink.opacity(0.16))
                    .cornerRadius(1)
                    .opacity(barRevealOpacity(bar, domain: domain, elapsed: elapsed))
                }
            }
            // Round-12: 36pt (from 52) — the densest ink patch in the app, quieted to a rug
            // rather than a rival chart.
            .frame(height: 36)
            // The lane names itself in the same quiet margin-ink caption as every other chart
            // label here — replaces the legend row's "Doses" key. Round-12 moved this to the top
            // trailing corner, but that put it directly on the trailing 7-day bars — the rug's
            // only full-copper ink — half-clipped at the screen edge. Round-13: back to the
            // leading gutter, the chart's established home for lane names (Heavy/Elevated/
            // Normal/Minimal already live there on the plot above), right-aligned to the same
            // gutter width so it never sits over a bar in any window.
            .overlay(alignment: .topLeading) {
                Text("Doses")
                    .font(Clinical.eyebrow(8)).tracking(0.6)
                    .foregroundStyle(Clinical.tertiary)
                    .lineLimit(1).fixedSize()
                    .frame(width: gutterWidth, alignment: .trailing)
                    .padding(.trailing, 4)
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...Double(data.intakeCeiling))
            .chartXAxis {
                // Three tiers so a multi-year "All" window doesn't cram monthly ticks into a
                // solid smear: weekly inside a month, monthly inside about a year, quarterly
                // beyond that — with the year folded into the label once month-only ticks would
                // otherwise repeat ("Jan" every year) with nothing to tell them apart.
                AxisMarks(values: .stride(by: axisStride)) { value in
                    AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d.formatted(axisFormat))
                                .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                // Invisible copy of the top chart's widest y label ("Elevated", same monospaced
                // eyebrow font) reserves an identical leading gutter, so both plot areas share
                // the same width and the two time axes stay vertically aligned.
                AxisMarks(position: .leading, values: [0.0]) { _ in
                    AxisValueLabel {
                        Text("Elevated")
                            .font(Clinical.eyebrow(9)).foregroundStyle(.clear)
                            .lineLimit(1).fixedSize()
                            // Measures its own natural (unwrapped) width at the live type size
                            // and grows the shared gutter to fit — never shrinks, so a transient
                            // narrower pass (e.g. mid-rotation) can't ping-pong the layout.
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                                if width > gutterWidth { gutterWidth = width }
                            }
                            .frame(width: gutterWidth, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// Raw-dot size/opacity for the current window, or `nil` to omit the layer entirely. Reading
    /// distance (1M) keeps the full honest-reality dot; 3M/6M thin it so it recedes behind the
    /// trend line instead of striping the gridlines; 1Y/All drop it — the smoothed line and area
    /// carry those journal-length windows alone.
    private var rawDotStyle: (size: CGFloat, opacity: Double)? {
        if windowDays <= 31 { return (12, 0.22) }
        if windowDays <= 200 { return (7, 0.10) }
        return nil
    }

    private var axisStride: Calendar.Component {
        if windowDays <= 31 { return .weekOfYear }
        if windowDays <= 200 { return .month }
        return .quarter
    }

    private var axisFormat: Date.FormatStyle {
        if windowDays <= 31 { return .dateTime.month(.abbreviated).day() }
        if windowDays <= 200 { return .dateTime.month(.abbreviated) }
        return .dateTime.month(.abbreviated).year(.twoDigits)
    }

    // MARK: Thin-data placeholder

    private var thinDataPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(Clinical.caption(16)).foregroundStyle(Clinical.tertiary)
                Text("Keep logging to see your journey")
                    .font(Clinical.body(14, weight: .medium)).foregroundStyle(Clinical.secondary)
            }
            Text("Two or more daily logs in this window unlock the timeline.")
                .font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Draw-in reveal (wall-clock, transaction-proof)

/// Shared timing for the shed-chart reveal and its marker pop-ins.
private enum RevealTiming {
    static let duration: TimeInterval = 0.9
}

/// Reveals `content` once on appear, reporting a 0…1 eased `progress` and the raw `elapsed`
/// seconds since it started. Driven by a `TimelineView` ticking real elapsed time rather than
/// SwiftUI's animation/transaction system — see `JourneyChart.shedChart` for why an ordinary
/// `withAnimation` can't be trusted here. Freezes to a fully-revealed static frame under Reduce
/// Motion, and stops ticking for good once the reveal completes so the chart "settles completely
/// still" instead of burning frames forever.
private struct RevealOnce<Content: View>: View {
    private let content: (_ progress: CGFloat, _ elapsed: TimeInterval) -> Content

    init(@ViewBuilder content: @escaping (_ progress: CGFloat, _ elapsed: TimeInterval) -> Content) {
        self.content = content
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate: Date?
    @State private var done = false

    var body: some View {
        Group {
            if reduceMotion || done {
                content(1, .greatestFiniteMagnitude)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let elapsed = startDate.map { timeline.date.timeIntervalSince($0) } ?? 0
                    let t = max(0, min(1, elapsed / RevealTiming.duration))
                    let eased = 1 - pow(1 - t, 3) // ease-out cubic
                    content(CGFloat(eased), elapsed)
                        .onChange(of: t) { _, new in
                            if new >= 1 { done = true }
                        }
                }
            }
        }
        .onAppear {
            guard startDate == nil else { return }
            if reduceMotion {
                done = true
            } else {
                startDate = .now
            }
        }
    }
}

/// Pops an event-marker badge in once the reveal's elapsed time passes its own delay — a quick
/// smoothstep fade + scale computed directly from elapsed time (no `Animation`/`Transaction`
/// involved, for the same reason `RevealOnce` avoids them). Fully visible immediately once the
/// reveal is done or under Reduce Motion.
private struct MarkerPop: ViewModifier {
    let elapsed: TimeInterval
    let delay: Double
    fileprivate static let popDuration: Double = 0.22

    func body(content: Content) -> some View {
        let local = max(0, elapsed - delay)
        let t = max(0, min(1, local / Self.popDuration))
        let eased = t * t * (3 - 2 * t) // smoothstep
        content
            .opacity(eased)
            .scaleEffect(0.55 + 0.45 * eased)
    }
}

// MARK: - Derived, window-filtered chart data

/// Pure data shaping for the journey timeline — filtering to the window, the 7-day rolling shed
/// trend, event markers with a two-row anti-crowding stagger, and per-class daily dose stacks.
private struct JourneyData {
    struct ShedPoint: Identifiable {
        let date: Date
        let raw: Double
        let smoothed: Double
        var id: Date { date }
    }

    struct Marker: Identifiable, Equatable {
        enum Kind { case procedure, start, stop, trigger, note }
        let id: String
        let kind: Kind
        let date: Date
        let symbol: String
        let tag: String
        var level: Int = 0 // 0 = top badge row, 1 = staggered second row
        /// Full free-text note — set only for `.note` markers, shown by the tap-to-reveal
        /// disclosure. Every other kind uses `tag`'s short canonical label instead.
        var noteText: String? = nil
        /// The actual `TriggerEvent` this marker was built from — set only for `.trigger`
        /// markers, so the disclosure's "Edit" button can deep-link straight to
        /// `AddTriggerSheet(existing:)` instead of sending someone hunting through Plan's ledger
        /// for the one they just tapped on the chart.
        var triggerRef: TriggerEvent? = nil

        var color: Color {
            switch kind {
            case .procedure: return Clinical.accent
            case .start: return Clinical.gold
            // Neutral, not warning — stopping a treatment is the user's own recorded decision,
            // not something the app judges.
            case .stop: return Clinical.tertiary
            case .trigger: return Clinical.warning
            case .note: return Clinical.sage
            }
        }

        static func == (lhs: Marker, rhs: Marker) -> Bool { lhs.id == rhs.id }
    }

    struct DoseBar: Identifiable {
        let id: String
        let day: Date
        let count: Int
        let seriesTitle: String
    }

    struct DoseSeries: Identifiable {
        let title: String
        let color: Color
        var id: String { title }
    }

    /// A shaded "possible echo" window: triggerDate/stopDate + 8…12 weeks, clipped to the chart
    /// domain. Never a prediction — just the honest calendar math behind the app's recurring
    /// "shedding often lags a trigger by 2–3 months" line, finally drawn where the eye already is.
    struct EchoBand: Identifiable {
        let id: String
        let start: Date
        let end: Date
    }

    let shedPoints: [ShedPoint]
    let markers: [Marker]
    let echoBands: [EchoBand]
    let doseBars: [DoseBar]
    let doseSeries: [DoseSeries]
    let intakeCeiling: Int

    init(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        triggers: [TriggerEvent],
        procedures: [ProcedureAppointment] = [],
        start: Date,
        end: Date
    ) {
        let calendar = Calendar.current

        // Shed trend: raw daily 0–3 values plus the shared 7-day centered rolling mean.
        let window = entries
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
        let raw = window.map { Double($0.shed.rawValue) }
        let smoothed = ChartMath.rollingMean(raw, window: 7)
        shedPoints = window.indices.map {
            ShedPoint(date: window[$0].date, raw: raw[$0], smoothed: smoothed[$0])
        }

        // Event markers: procedures, daily-med starts, and TE triggers inside the window.
        var built: [Marker] = []
        for t in treatments where t.startDate >= start && t.startDate <= end {
            if !t.slots.isEmpty {   // schedule-driven: `.other` daily items get a "start" marker too
                built.append(Marker(
                    id: "start-\(t.classRaw)-\(t.startDate.timeIntervalSinceReferenceDate)",
                    kind: .start, date: t.startDate,
                    symbol: t.treatmentClass.symbol,
                    tag: Self.canonicalTag(t.treatmentClass, name: t.name)
                ))
            } else {
                built.append(Marker(
                    id: "proc-\(t.classRaw)-\(t.startDate.timeIntervalSinceReferenceDate)",
                    kind: .procedure, date: t.startDate,
                    symbol: t.treatmentClass.symbol,
                    tag: Self.canonicalTag(t.treatmentClass, name: t.name)
                ))
            }
            // Stop markers: dated the same way a trigger is — a recent stop is exactly the
            // kind of event that can explain a shedding change 2–3 months later.
            if let stopDate = t.endDate, stopDate >= start, stopDate <= end {
                built.append(Marker(
                    id: "stop-\(t.classRaw)-\(stopDate.timeIntervalSinceReferenceDate)",
                    kind: .stop, date: stopDate,
                    symbol: "xmark.circle",
                    tag: Self.canonicalTag(t.treatmentClass, name: t.name)
                ))
            }
        }
        for tr in triggers where tr.date >= start && tr.date <= end {
            built.append(Marker(
                id: "trig-\(tr.typeRaw)-\(tr.date.timeIntervalSinceReferenceDate)",
                kind: .trigger, date: tr.date,
                symbol: tr.type.symbol,
                tag: Self.triggerTag(tr.type),
                triggerRef: tr
            ))
        }
        // Daily-log notes — the richest causal context a person records ("switched shampoo",
        // "started keto", "post-COVID") used to be write-only outside that exact day's log
        // sheet. Surfaced as a tap-to-reveal marker so it finally sits alongside the trend it
        // might explain.
        for e in entries where e.date >= start && e.date <= end {
            let trimmed = e.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            built.append(Marker(
                id: "note-\(e.date.timeIntervalSinceReferenceDate)",
                kind: .note, date: e.date,
                symbol: "text.bubble",
                tag: "Note",
                noteText: trimmed
            ))
        }
        // Completed in-office procedures — dated by when they were actually marked done, which
        // is the moment worth reading a shedding change against.
        for p in procedures where p.isCompleted {
            let date = p.completedAt ?? p.date
            guard date >= start, date <= end else { continue }
            built.append(Marker(
                id: "proc-\(p.persistentModelID.hashValue)",
                kind: .procedure, date: date,
                symbol: p.type.symbol,
                tag: p.type.title
            ))
        }
        built.sort { $0.date < $1.date }

        // Anti-crowding: badges closer than ~1/9 of the window drop to a second row.
        let minGap = end.timeIntervalSince(start) / 9
        var lastAtLevel: [Date?] = [nil, nil]
        for i in built.indices {
            let d = built[i].date
            if let l0 = lastAtLevel[0], d.timeIntervalSince(l0) < minGap {
                built[i].level = 1
                lastAtLevel[1] = d
            } else {
                built[i].level = 0
                lastAtLevel[0] = d
            }
        }
        markers = built

        // Possible-echo bands: 8…12 weeks after each dated trigger and treatment-stop that's
        // itself inside the window — the same source events already drawn as `.trigger`/`.stop`
        // markers above, so a band never appears without the dated event that explains it.
        // Clipped to [start, end] since the band's far edge can fall past `end`.
        let week: TimeInterval = 7 * 24 * 3600
        var bands: [EchoBand] = []
        func addEchoBand(id: String, anchor: Date) {
            let bandStart = anchor.addingTimeInterval(8 * week)
            let bandEnd = anchor.addingTimeInterval(12 * week)
            guard bandEnd >= start, bandStart <= end else { return }
            bands.append(EchoBand(id: id, start: max(bandStart, start), end: min(bandEnd, end)))
        }
        for tr in triggers where tr.date >= start && tr.date <= end {
            addEchoBand(id: "trig-echo-\(tr.typeRaw)-\(tr.date.timeIntervalSinceReferenceDate)", anchor: tr.date)
        }
        for t in treatments {
            guard let stopDate = t.endDate, stopDate >= start, stopDate <= end else { continue }
            addEchoBand(id: "stop-echo-\(t.classRaw)-\(stopDate.timeIntervalSinceReferenceDate)", anchor: stopDate)
        }
        echoBands = bands

        // Intake lane: doses of daily-med classes, grouped per calendar day and stacked by class.
        let dailyOrder: [TreatmentClass] = [.minoxidil, .finasteride, .dutasteride]
        var byClass: [TreatmentClass: [Date: Int]] = [:]
        for dose in doses {
            guard
                let cls = dose.treatment?.treatmentClass, cls.isDaily,
                dose.loggedAt >= start, dose.loggedAt <= end
            else { continue }
            let day = calendar.startOfDay(for: dose.loggedAt)
            byClass[cls, default: [:]][day, default: 0] += 1
        }
        var bars: [DoseBar] = []
        var series: [DoseSeries] = []
        for cls in dailyOrder {
            guard let days = byClass[cls], !days.isEmpty else { continue }
            series.append(DoseSeries(
                title: cls.title,
                color: cls == .minoxidil ? Clinical.accent : Clinical.gold
            ))
            for (day, n) in days.sorted(by: { $0.key < $1.key }) {
                bars.append(DoseBar(
                    id: "\(cls.rawValue)-\(day.timeIntervalSinceReferenceDate)",
                    day: day, count: n, seriesTitle: cls.title
                ))
            }
        }
        doseBars = bars
        doseSeries = series

        // Lane ceiling: a fully adherent day fills the lane; overshoot days still fit.
        let expected = dailyOrder
            .filter { byClass[$0] != nil }
            .reduce(0) { $0 + $1.defaultDailyCount }
        let observedMax = Dictionary(grouping: bars, by: \.day)
            .values
            .map { $0.reduce(0) { $0 + $1.count } }
            .max() ?? 0
        intakeCeiling = max(expected, observedMax, 1)
    }

    /// Short, canonical per-class tag — never the user's free-form treatment name, so length is
    /// bounded and predictable regardless of what someone typed into the name field. `.other`
    /// falls back to the first word of the name (still user-controlled, but rare and short in
    /// practice) or "Other".
    private static func canonicalTag(_ cls: TreatmentClass, name: String) -> String {
        switch cls {
        case .minoxidil: return "Minoxidil"
        case .finasteride: return "Finasteride"
        case .dutasteride: return "Dutasteride"
        case .spironolactone: return "Spironolactone"
        case .microneedling: return "Needling"
        case .prp: return "PRP"
        case .lllt: return "Laser"
        case .shampoo: return "Shampoo"
        case .oil: return "Oil"
        case .supplement: return "Supplement"
        case .other: return name.split(separator: " ").first.map(String.init) ?? "Other"
        }
    }

    private static func triggerTag(_ type: TriggerType) -> String {
        switch type {
        case .crashDiet: return "Diet"
        case .illness: return "Sick"
        case .majorStress: return "Stress"
        case .childbirth: return "Birth"
        case .newMedication: return "New med"
        case .other: return "Trigger"
        }
    }
}
