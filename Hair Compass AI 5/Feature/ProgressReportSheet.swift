import Charts
import SwiftUI

/// The full periodic progress report: trajectory mini-charts (faint raw points under the 7-day
/// smoothed trend, JourneyChart-lite), adherence with its weakest stretch, tolerability with
/// severity dots, labs with flags, and the honest read — shareable as plain text. Everything
/// shown is derived by the pure `ProgressReport.build`; this view only renders it.
struct ProgressReportSheet: View {
    let report: ProgressReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let shed = report.shedTrend {
                        trendCard(eyebrow: "Shedding trajectory", trend: shed,
                                  unitLabel: "0–3 self-report · 7-day smoothed trend over faint daily points")
                    }
                    if let scalp = report.scalpTrend {
                        trendCard(eyebrow: "Scalp severity", trend: scalp,
                                  unitLabel: "0–16 seborrheic-dermatitis total · 7-day smoothed")
                    }
                    if let adherence = report.adherence { adherenceCard(adherence) }
                    tolerabilityCard
                    if !report.labs.isEmpty { labsCard }
                    StrandDivider()
                    honestReadCard
                    Text("A self-tracked record for your own clinician conversations — not medical advice.")
                        .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Progress report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: report.plainText()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Clinical.accent)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Header — serif week headline + period line

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Eyebrow(text: report.treatmentTitle ?? "Your tracking")
                if report.isMilestoneWeek { milestoneBadge }
            }
            Text("Week \(report.weekNumber) report")
                .font(Clinical.headline(28)).foregroundStyle(Clinical.ink)
            Text("\(report.periodStart.formatted(date: .abbreviated, time: .omitted)) – \(report.periodEnd.formatted(date: .abbreviated, time: .omitted)) · \(report.entryCount) daily log\(report.entryCount == 1 ? "" : "s")")
                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Unboxed sprig bleeding from the sheet's top-right, behind the week headline.
        .background(alignment: .topTrailing) { CornerSprig(width: 160, opacity: 0.4) }
    }

    private var milestoneBadge: some View {
        Text("MILESTONE")
            .font(Clinical.eyebrow(9)).tracking(0.8)
            .foregroundStyle(Clinical.gold)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Clinical.gold.opacity(0.14), in: Capsule())
    }

    // MARK: Trajectory cards

    private func trendCard(eyebrow: String, trend: ProgressReport.Trend, unitLabel: String) -> some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: eyebrow)
                    Spacer()
                    verdictChip(trend.verdict)
                }
                miniChart(trend)
                HStack(spacing: 16) {
                    StatBlock(value: fmt(trend.firstWindowMean), label: "First 4 wks avg")
                    StatBlock(value: fmt(trend.lastWindowMean), label: "Last 4 wks avg")
                }
                Text(unitLabel).font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    private func verdictChip(_ verdict: ProgressReport.TrendVerdict) -> some View {
        let (tint, symbol): (Color, String) = {
            switch verdict {
            case .improving: return (Clinical.positive, "arrow.down.right")
            case .stable: return (Clinical.secondary, "arrow.right")
            case .worsening: return (Clinical.warning, "arrow.up.right")
            }
        }()
        return Label(verdict.title, systemImage: symbol)
            .font(Clinical.eyebrow(10)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    /// JourneyChart-lite: faint raw daily points under the 7-day smoothed line, one hue.
    private func miniChart(_ trend: ProgressReport.Trend) -> some View {
        Chart {
            ForEach(trend.raw) { p in
                PointMark(x: .value("Date", p.date), y: .value("Level", p.value))
                    .symbolSize(10)
                    .foregroundStyle(Clinical.accent.opacity(0.2))
            }
            ForEach(trend.smoothed) { p in
                LineMark(x: .value("Date", p.date), y: .value("Level", p.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Clinical.accent)
            }
        }
        .frame(height: 110)
        .chartYScale(domain: 0...trend.scaleMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, trend.scaleMax]) { value in
                AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(fmt(v)).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d.formatted(.dateTime.month(.abbreviated)))
                            .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                    }
                }
            }
        }
    }

    // MARK: Adherence

    private func adherenceCard(_ adherence: ProgressReport.AdherenceSummary) -> some View {
        let good = adherence.overall >= 0.8
        let tint = good ? Clinical.positive : Clinical.warning
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Adherence")
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int((adherence.overall * 100).rounded()))%")
                        .font(Clinical.number(28)).foregroundStyle(tint)
                    Spacer()
                    Text("of expected doses · last \(adherence.windowDays) days")
                        .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                }
                ProgressBar(value: adherence.overall, tint: tint).frame(height: 8)
                if let weak = adherence.weakest {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 12)).foregroundStyle(Clinical.warning)
                        Text("Weakest stretch: \(weak.start.formatted(date: .abbreviated, time: .omitted)) – \(weak.end.formatted(date: .abbreviated, time: .omitted)) at \(Int((weak.rate * 100).rounded()))%.")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Tolerability

    private var tolerabilityCard: some View {
        let tolerability = report.tolerability
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Tolerability")
                    Spacer()
                    if tolerability.hasSevere {
                        Label("Severe on record", systemImage: "exclamationmark.bubble")
                            .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.critical)
                    }
                }
                if tolerability.total == 0 {
                    Text("Nothing logged this period.")
                        .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                } else {
                    HStack(spacing: 16) {
                        StatBlock(value: "\(tolerability.mild)", label: "Mild")
                        StatBlock(value: "\(tolerability.moderate)", label: "Moderate")
                        StatBlock(value: "\(tolerability.severe)", label: "Severe",
                                  accent: tolerability.hasSevere ? Clinical.critical : Clinical.ink)
                    }
                    ForEach(tolerability.items.prefix(4)) { item in
                        HStack(spacing: 8) {
                            severityDots(item.severity)
                            Text(item.title).font(.system(size: 13)).foregroundStyle(Clinical.ink)
                            Spacer()
                            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                }
            }
        }
    }

    /// Three pips, filled to the severity, colored by band (mild sage · moderate ochre · severe brick).
    private func severityDots(_ severity: Int) -> some View {
        let clamped = min(max(severity, 1), 3)
        let band = SeverityBand(rawValue: clamped - 1) ?? .mild
        return HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i <= clamped ? Clinical.bandColor(band) : Clinical.hairline)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("\(band.title) severity")
    }

    // MARK: Labs

    private var labsCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Labs · latest per test")
                ForEach(report.labs) { lab in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lab.title)
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                            Text(lab.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                        }
                        Spacer()
                        Text("\(fmt(lab.value)) \(lab.unit)")
                            .font(Clinical.number(14)).foregroundStyle(Clinical.ink)
                        Text(lab.flag.title)
                            .font(Clinical.eyebrow(9)).tracking(0.5)
                            .foregroundStyle(Clinical.flagColor(lab.flag))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Clinical.flagColor(lab.flag).opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: The honest read

    private var honestReadCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "The honest read", color: Clinical.accent)
                Text(report.honestRead)
                    .font(.system(size: 14)).foregroundStyle(Clinical.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !report.triggerLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(report.triggerLines, id: \.self) { line in
                            Label(line, systemImage: "calendar.badge.exclamationmark")
                                .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Formatting

    private func fmt(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
