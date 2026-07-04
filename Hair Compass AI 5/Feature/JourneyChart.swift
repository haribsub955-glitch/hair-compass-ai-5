import Charts
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
    let windowDays: Int

    private static let shedAxisValues: [Double] = [0, 1, 2, 3]
    private static let shedAxisLabels = ShedLevel.allCases.map {
        $0 == .minimal ? "Min" : ($0 == .normal ? "Norm" : ($0 == .elevated ? "Elev" : "Heavy"))
    }

    var body: some View {
        let end = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -windowDays, to: end) ?? end
        let data = JourneyData(
            entries: entries, treatments: treatments, doses: doses,
            triggers: triggers, start: start, end: end
        )
        ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Your journey")
                Text("Shedding & treatment timeline")
                    .font(Clinical.headline(19))
                    .foregroundStyle(Clinical.ink)

                if data.shedPoints.count < 2 {
                    thinDataPlaceholder
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        shedChart(data: data, domain: start...end)
                        intakeLane(data: data, domain: start...end)
                    }
                    legend(data: data)
                }
            }
        }
    }

    // MARK: Top chart — smoothed shed trend + dated event markers

    private func shedChart(data: JourneyData, domain: ClosedRange<Date>) -> some View {
        Chart {
            // Faint raw daily levels — the honest reality behind the smoothing.
            ForEach(data.shedPoints) { p in
                PointMark(x: .value("Date", p.date), y: .value("Shed", p.raw))
                    .symbolSize(12)
                    .foregroundStyle(Clinical.accent.opacity(0.22))
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
            // Dashed verticals anchor each dated event to the trend.
            ForEach(data.markers) { m in
                RuleMark(x: .value("Date", m.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(m.color.opacity(0.45))
            }
            // Event badges — staggered onto a second row when two events land close together,
            // and tagged with a short label only while there are few enough to stay readable.
            ForEach(data.markers) { m in
                PointMark(x: .value("Date", m.date), y: .value("Shed", m.level == 0 ? 2.82 : 2.28))
                    .symbolSize(0)
                    .annotation(
                        position: .overlay,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        markerBadge(m, showTag: data.showMarkerTags)
                    }
            }
        }
        .frame(height: 180)
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...3)
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
                        }
                    }
                }
            }
        }
    }

    private func markerBadge(_ m: JourneyData.Marker, showTag: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: m.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(m.color)
                .frame(width: 20, height: 20)
                .background(Clinical.surface, in: Circle())
                .overlay(Circle().strokeBorder(m.color.opacity(0.45), lineWidth: 1))
                .shadow(color: Clinical.cardShadow, radius: 3, y: 1)
            if showTag {
                Text(m.tag)
                    .font(Clinical.eyebrow(8))
                    .foregroundStyle(Clinical.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 84)
            }
        }
    }

    // MARK: Bottom lane — day-by-day medication intake

    @ViewBuilder
    private func intakeLane(data: JourneyData, domain: ClosedRange<Date>) -> some View {
        if data.doseBars.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "pills")
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                Text("No medication logged yet")
                    .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Clinical.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Chart(data.doseBars) { bar in
                BarMark(
                    x: .value("Day", bar.day, unit: .day),
                    y: .value("Doses", bar.count)
                )
                .foregroundStyle(by: .value("Medication", bar.seriesTitle))
                .cornerRadius(1)
            }
            .chartForegroundStyleScale(domain: data.doseSeriesTitles, range: data.doseSeriesColors)
            .chartLegend(.hidden) // the shared keyed legend below covers the lane
            .frame(height: 52)
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...Double(data.intakeCeiling))
            .chartXAxis {
                AxisMarks(values: .stride(by: windowDays <= 31 ? .weekOfYear : .month)) { value in
                    AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d.formatted(
                                windowDays <= 31
                                    ? .dateTime.month(.abbreviated).day()
                                    : .dateTime.month(.abbreviated)
                            ))
                            .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                // Invisible copy of the top chart's widest y label ("Heavy", same monospaced
                // eyebrow font) reserves an identical leading gutter, so both plot areas share
                // the same width and the two time axes stay vertically aligned.
                AxisMarks(position: .leading, values: [0.0]) { _ in
                    AxisValueLabel {
                        Text("Heavy").font(Clinical.eyebrow(9)).foregroundStyle(.clear)
                    }
                }
            }
        }
    }

    // MARK: Legend — only keys that actually appear

    private func legend(data: JourneyData) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 10)], alignment: .leading, spacing: 6) {
            legendKey(.line, color: Clinical.accent, label: "Shedding")
            ForEach(data.doseSeries) { s in
                legendKey(.bar, color: s.color, label: s.title)
            }
            if let symbol = data.firstSymbol(of: .procedure) {
                legendKey(.marker(symbol), color: Clinical.accent, label: "Procedure")
            }
            if let symbol = data.firstSymbol(of: .start) {
                legendKey(.marker(symbol), color: Clinical.gold, label: "Med start")
            }
            if let symbol = data.firstSymbol(of: .trigger) {
                legendKey(.marker(symbol), color: Clinical.warning, label: "Trigger")
            }
        }
        .padding(.top, 2)
    }

    private enum KeyStyle { case line, bar, marker(String) }

    private func legendKey(_ style: KeyStyle, color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            switch style {
            case .line:
                Capsule().fill(color).frame(width: 14, height: 3)
            case .bar:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color).frame(width: 8, height: 10)
            case .marker(let symbol):
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 14, height: 14)
                    .background(Clinical.surface, in: Circle())
                    .overlay(Circle().strokeBorder(color.opacity(0.45), lineWidth: 1))
            }
            Text(label)
                .font(Clinical.eyebrow(9))
                .foregroundStyle(Clinical.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Thin-data placeholder

    private var thinDataPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 16)).foregroundStyle(Clinical.tertiary)
                Text("Keep logging to see your journey")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.secondary)
            }
            Text("Two or more daily logs in this window unlock the timeline.")
                .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
        }
        .padding(.vertical, 8)
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

    struct Marker: Identifiable {
        enum Kind { case procedure, start, trigger }
        let id: String
        let kind: Kind
        let date: Date
        let symbol: String
        let tag: String
        var level: Int = 0 // 0 = top badge row, 1 = staggered second row

        var color: Color {
            switch kind {
            case .procedure: return Clinical.accent
            case .start: return Clinical.gold
            case .trigger: return Clinical.warning
            }
        }
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

    let shedPoints: [ShedPoint]
    let markers: [Marker]
    let doseBars: [DoseBar]
    let doseSeries: [DoseSeries]
    let intakeCeiling: Int

    /// Short tags fit alongside the badges only while the chart stays uncrowded; past that the
    /// markers fall back to symbol-only and the legend carries the meaning.
    var showMarkerTags: Bool { markers.count <= 3 }
    var doseSeriesTitles: [String] { doseSeries.map(\.title) }
    var doseSeriesColors: [Color] { doseSeries.map(\.color) }

    func firstSymbol(of kind: Marker.Kind) -> String? {
        markers.first { $0.kind == kind }?.symbol
    }

    init(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        triggers: [TriggerEvent],
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
            if !t.slots.isEmpty {   // schedule-driven: `.other` daily items get a "Started …" marker too
                let name = t.name.isEmpty ? t.treatmentClass.title : t.name
                built.append(Marker(
                    id: "start-\(t.classRaw)-\(t.startDate.timeIntervalSinceReferenceDate)",
                    kind: .start, date: t.startDate,
                    symbol: t.treatmentClass.symbol,
                    tag: "Started \(name)"
                ))
            } else {
                built.append(Marker(
                    id: "proc-\(t.classRaw)-\(t.startDate.timeIntervalSinceReferenceDate)",
                    kind: .procedure, date: t.startDate,
                    symbol: t.treatmentClass.symbol,
                    tag: Self.procedureTag(t.treatmentClass, name: t.name)
                ))
            }
        }
        for tr in triggers where tr.date >= start && tr.date <= end {
            built.append(Marker(
                id: "trig-\(tr.typeRaw)-\(tr.date.timeIntervalSinceReferenceDate)",
                kind: .trigger, date: tr.date,
                symbol: tr.type.symbol,
                tag: Self.triggerTag(tr.type)
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

    private static func procedureTag(_ cls: TreatmentClass, name: String) -> String {
        switch cls {
        case .lllt: return "Laser"
        case .other: return name.isEmpty ? "Procedure" : name
        default: return cls.title
        }
    }

    private static func triggerTag(_ type: TriggerType) -> String {
        switch type {
        case .crashDiet: return "Crash diet"
        case .illness: return "Illness"
        case .majorStress: return "Stress"
        case .childbirth: return "Childbirth"
        case .newMedication: return "New med"
        case .other: return "Trigger"
        }
    }
}
