import Charts
import SwiftUI

/// Descriptive observations around any dated event, with no treatment-efficacy verdict.
struct EventObservationCard: View {
    let event: TrendHighlight
    let points: [(day: Date, value: Double)]
    let title: String
    let unit: String
    let days: Int
    let isSideEffect: Bool

    var body: some View {
        let comparison = TrendContext.compare(points: points, event: event.date, days: days)
        let observed = points.filter { $0.day >= comparison.beforeStart && $0.day < comparison.afterEnd }
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(title) around this date").font(Clinical.headline(21)).foregroundStyle(Clinical.ink)
                Text("\(comparison.beforeStart.formatted(date: .abbreviated, time: .omitted)) – \(min(comparison.afterEnd.addingTimeInterval(-1), .now).formatted(date: .abbreviated, time: .omitted))")
                    .font(Clinical.caption(11)).foregroundStyle(Clinical.secondary)
                if !observed.isEmpty {
                    Chart {
                        RuleMark(x: .value("Event", comparison.afterStart))
                            .foregroundStyle(event.kind.tint).lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                        ForEach(observed, id: \.day) { point in
                            PointMark(x: .value("Date", point.day), y: .value(title, point.value))
                                .foregroundStyle(Clinical.accent).symbolSize(28)
                        }
                    }
                    .frame(height: 160)
                    .chartXScale(domain: comparison.beforeStart...max(comparison.afterStart.addingTimeInterval(1), min(comparison.afterEnd, .now)))
                    .chartYScale(domain: (isSideEffect ? 1.0 : 0.0)...(unit == "0–16" ? 16.0 : 3.0))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                    Text("The dashed line marks the event. Each dot is one recorded day.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        summary("Before", values: comparison.before)
                        summary("After", values: comparison.after)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        summary("Before", values: comparison.before)
                        summary("After", values: comparison.after)
                    }
                }
                if !comparison.hasEnoughDays {
                    Text("A comparison needs at least 5 recorded days on each side. You have \(comparison.before.count) before and \(comparison.after.count) after.")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                }
                Text("These are logged levels around a date. Timing alone cannot tell whether a medication, product, or procedure caused a change.")
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
            }
        }
        .accessibilityIdentifier("eventObservationComparison")
    }

    private func summary(_ label: String, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: label)
            Text(values.count >= 5 ? ChartMath.mean(values).formatted(.number.precision(.fractionLength(1))) : "—")
                .font(Clinical.headline(28)).foregroundStyle(Clinical.ink)
            Text("\(values.count) recorded days").font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
            Text(isSideEffect ? "Mean reported peak severity · 1–3" : "Mean logged level · \(unit)")
                .font(Clinical.caption(10)).foregroundStyle(Clinical.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
