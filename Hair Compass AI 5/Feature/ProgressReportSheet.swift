import Charts
import SwiftUI

/// The full periodic progress report: trajectory mini-charts (faint raw points under the 7-day
/// smoothed trend, JourneyChart-lite), adherence with its weakest stretch, tolerability with
/// severity dots, labs with flags, and the honest read — shareable as plain text. Everything
/// shown is derived by the pure `ProgressReport.build`; this view only renders it.
struct ProgressReportSheet: View {
    let report: ProgressReport
    /// Every photo on record — filtered/paired per region via `ProgressReport.photoPair`. Nil
    /// (the default) simply skips the photo section, so existing call sites that predate this
    /// argument keep building.
    var photos: [PhotoRecord] = []
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
                    if !photoPairs.isEmpty { photoCard }
                    StrandDivider()
                    honestReadCard
                    Text("A self-tracked record for your own clinician conversations — not medical advice.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
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
                .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The report's crowning emblem: the laurel medallion sits whole in the header's open
        // trailing space, like a crest on a letterhead — unboxed, behind any long period line.
        // A background takes no layout space, so the headline never gets cramped.
        .background(alignment: .trailing) {
            Image(BrandArt.medallion)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .opacity(0.9)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
                    // Shown only when there's logging before the treatment started — the
                    // baseline habit the app tells users buys them an easier-to-judge future
                    // treatment. A record of change, never a verdict on its own.
                    if let preStart = trend.preStartMean {
                        StatBlock(value: fmt(preStart), label: "Before start")
                    }
                    StatBlock(value: fmt(trend.firstWindowMean), label: "First 4 wks avg")
                    StatBlock(value: fmt(trend.lastWindowMean), label: "Last 4 wks avg")
                }
                Text(unitLabel).font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
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
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                }
                ProgressBar(value: adherence.overall, tint: tint).frame(height: 8)
                if let weak = adherence.weakest {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.warning)
                        Text("Weakest stretch: \(weak.start.formatted(date: .abbreviated, time: .omitted)) – \(weak.end.formatted(date: .abbreviated, time: .omitted)) at \(Int((weak.rate * 100).rounded()))%.")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
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
                        .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
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
                            Text(item.title).font(Clinical.caption(13)).foregroundStyle(Clinical.ink)
                            Spacer()
                            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
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
                                .font(Clinical.body(14, weight: .medium)).foregroundStyle(Clinical.ink)
                            Text(lab.date.formatted(date: .abbreviated, time: .omitted))
                                .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
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

    // MARK: Photo evidence

    /// One baseline/latest pair per region with ≥ 2 captures, via `ProgressReport.photoPair` —
    /// pure reuse of the same selection logic the Visit PDF already uses, anchored to this
    /// report's own window when it has a focus treatment.
    private var photoPairs: [(region: PhotoRegion, baseline: PhotoRecord, latest: PhotoRecord, caveat: String?)] {
        PhotoRegion.allCases.compactMap { region in
            let regionPhotos = photos.filter { $0.region == region }
            guard let pair = report.photoPair(in: regionPhotos) else { return nil }
            return (region, pair.baseline, pair.latest, pair.caveat)
        }
    }

    /// The evidence users and clinicians trust most for hair — shown here so the milestone
    /// moment this report exists to deliver doesn't ask someone to judge 24 weeks of change
    /// without the single most persuasive record they've been diligently building.
    private var photoCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Photo record")
                ForEach(photoPairs, id: \.region) { pair in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pair.region.title)
                            .font(Clinical.body(13, weight: .medium)).foregroundStyle(Clinical.ink)
                        HStack(spacing: 10) {
                            photoThumb(pair.baseline, label: "Baseline")
                            photoThumb(pair.latest, label: "Latest")
                        }
                        if let caveat = pair.caveat {
                            Label(caveat, systemImage: "exclamationmark.triangle")
                                .font(Clinical.body(11, weight: .medium))
                                .foregroundStyle(Clinical.warning)
                        }
                    }
                }
            }
        }
    }

    private func photoThumb(_ record: PhotoRecord, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let image = PhotoStore.shared.loadThumbnail(record.imagePath) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Clinical.canvas)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
            Text("\(label) · \(record.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(Clinical.caption(10)).foregroundStyle(Clinical.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: The honest read

    private var honestReadCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "The honest read", color: Clinical.accent)
                Text(report.honestRead)
                    .font(Clinical.caption(14)).foregroundStyle(Clinical.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !report.triggerLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(report.triggerLines, id: \.self) { line in
                            Label(line, systemImage: "calendar.badge.exclamationmark")
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
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
