import Charts
import SwiftData
import SwiftUI

struct TrendsView: View {
    @Query(sort: \DailyEntry.date) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]

    enum Range: String, CaseIterable { case m1 = "1M", m3 = "3M", m6 = "6M"
        var days: Int { self == .m1 ? 30 : (self == .m3 ? 90 : 180) }
    }
    @State private var range: Range = .m3

    private var windowEntries: [DailyEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: .now) ?? .now
        return entries.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Longitudinal", title: "Trends").padding(.top, 8)

                ClinicalSegmented(options: Range.allCases, label: { $0.rawValue }, selection: $range)

                if windowEntries.count < 2 {
                    emptyState
                } else {
                    sheddingCard
                    scalpCard
                    adherenceCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .clinicalScreen()
    }

    private var emptyState: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Not enough data")
                Text("Trends appear after two or more daily logs in this window.")
                    .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
            }
        }
    }

    // MARK: Shedding trend

    private var sheddingCard: some View {
        let smoothed = HairAnalytics.rollingAverage(windowEntries.map { Double($0.shed.rawValue) }, window: 5)
        let dir = HairAnalytics.direction(windowEntries.map { Double($0.shed.rawValue) })
        let points = Array(zip(windowEntries.map(\.date), smoothed))
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Shedding")
                    Spacer()
                    directionTag(dir, invert: true)
                }
                Chart {
                    ForEach(points, id: \.0) { date, value in
                        AreaMark(x: .value("Date", date), y: .value("Shed", value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [Clinical.accent.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", date), y: .value("Shed", value))
                            .interpolationMethod(.monotone)
                            .lineStyle(.init(lineWidth: 2))
                            .foregroundStyle(Clinical.accent)
                    }
                }
                .frame(height: 150)
                .chartYScale(domain: 0...3)
                .chartYAxis { yAxis([0, 1, 2, 3], labels: ["Min", "Norm", "Elev", "Heavy"]) }
                .chartXAxis { xAxis }
            }
        }
    }

    // MARK: Scalp severity trend

    private var scalpCard: some View {
        let smoothed = HairAnalytics.rollingAverage(windowEntries.map { Double($0.scalpTotal) }, window: 5)
        let dir = HairAnalytics.direction(windowEntries.map { Double($0.scalpTotal) })
        let points = Array(zip(windowEntries.map(\.date), smoothed))
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Scalp severity (0–16)")
                    Spacer()
                    directionTag(dir, invert: true)
                }
                Chart {
                    ForEach([5.5, 9.5], id: \.self) { threshold in
                        RuleMark(y: .value("band", threshold))
                            .lineStyle(.init(lineWidth: 1, dash: [3, 4]))
                            .foregroundStyle(Clinical.hairline)
                    }
                    ForEach(points, id: \.0) { date, value in
                        LineMark(x: .value("Date", date), y: .value("Score", value))
                            .interpolationMethod(.monotone)
                            .lineStyle(.init(lineWidth: 2))
                            .foregroundStyle(Clinical.ink)
                    }
                }
                .frame(height: 150)
                .chartYScale(domain: 0...16)
                .chartYAxis { yAxis([0, 5, 10, 16], labels: ["0", "5", "10", "16"]) }
                .chartXAxis { xAxis }
                Text("Bands: 0–5 mild · 6–9 moderate · 10–16 severe.")
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    // MARK: Adherence

    private var adherenceCard: some View {
        let daily = treatments.filter { $0.treatmentClass.isDaily && $0.isActive }
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "14-day adherence")
                if daily.isEmpty {
                    Text("Add a daily treatment in Care to track adherence.")
                        .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                } else {
                    ForEach(daily) { t in
                        let dates = doses.filter { $0.treatment?.persistentModelID == t.persistentModelID }.map(\.loggedAt)
                        let pct = HairAnalytics.adherence(doseDates: dates, expectedPerDay: t.treatmentClass.defaultDailyCount) ?? 0
                        adherenceRow(t.name, pct: pct)
                    }
                }
            }
        }
    }

    private func adherenceRow(_ name: String, pct: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                Spacer()
                Text("\(Int((pct * 100).rounded()))%").font(Clinical.number(14)).foregroundStyle(Clinical.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Clinical.canvas)
                    Capsule().fill(pct >= 0.8 ? Clinical.positive : Clinical.warning)
                        .frame(width: max(6, geo.size.width * pct))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: chart helpers

    private func directionTag(_ dir: Double, invert: Bool) -> some View {
        let improving = invert ? dir < -0.05 : dir > 0.05
        let worsening = invert ? dir > 0.05 : dir < -0.05
        let (text, color, icon): (String, Color, String) =
            improving ? ("Improving", Clinical.positive, "arrow.down.right")
            : worsening ? ("Rising", Clinical.warning, "arrow.up.right")
            : ("Steady", Clinical.tertiary, "arrow.right")
        return Label(text, systemImage: icon)
            .font(Clinical.eyebrow(11))
            .foregroundStyle(color)
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: .stride(by: range == .m1 ? .weekOfYear : .month)) { value in
            AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
            AxisValueLabel {
                if let d = value.as(Date.self) {
                    Text(d.formatted(range == .m1 ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated)))
                        .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
    }

    private func yAxis(_ values: [Double], labels: [String]) -> some AxisContent {
        AxisMarks(position: .leading, values: values) { value in
            AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
            AxisValueLabel {
                if let v = value.as(Double.self), let idx = values.firstIndex(of: v) {
                    Text(labels[idx]).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
    }
}
