import Charts
import SwiftData
import SwiftUI

struct TrendsView: View {
    @Query(sort: \DailyEntry.date) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \TriggerEvent.date, order: .reverse) private var triggers: [TriggerEvent]
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \PhotoRecord.createdAt) private var photos: [PhotoRecord]
    @Query(sort: \LabResult.collectedAt) private var labs: [LabResult]

    @State private var showCompare = false
    @State private var showExport = false
    @State private var showBadges = false

    enum Range: String, CaseIterable { case m1 = "1M", m3 = "3M", m6 = "6M"
        var days: Int { self == .m1 ? 30 : (self == .m3 ? 90 : 180) }
    }
    @State private var range: Range = .m3

    private var windowEntries: [DailyEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: .now) ?? .now
        return entries.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollViewReader { proxy in
            scrollContent(proxy: proxy)
        }
    }

    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Longitudinal",
                    title: "Trends",
                    trailing: AnyView(
                        HeaderActionButton(
                            systemName: "square.and.arrow.up",
                            accessibilityLabel: "Export trends",
                            prominent: false
                        ) {
                            showExport = true
                        }
                    )
                )
                .padding(.top, 8)
                // Unboxed brand accent: the sprig bleeds from the screen's top-right behind the
                // header. Background views take no layout space (no horizontal scroll), and the
                // share button stays tappable — the art never hit-tests.
                .background(alignment: .topTrailing) { CornerSprig() }

                ClinicalSegmented(options: Range.allCases, label: { $0.rawValue }, selection: $range)

                trajectoryCard
                    .staggeredEntrance(index: 0)

                JourneyChart(
                    entries: entries,
                    treatments: treatments,
                    doses: doses,
                    triggers: triggers,
                    windowDays: range.days
                )
                .staggeredEntrance(index: 1)

                ConsistencyCard(
                    entries: entries,
                    treatments: treatments,
                    doses: doses,
                    photos: photos,
                    labs: labs,
                    triggers: triggers,
                    showAllBadges: $showBadges
                )
                .staggeredEntrance(index: 2)

                StrandDivider()

                BodySignalsDashboard(
                    snapshots: snapshots,
                    windowDays: range.days,
                    hasTractionRisk: profile?.hasTractionRisk == true,
                    recentTrigger: triggers.first
                )
                .id("body-signals")
                .staggeredEntrance(index: 3)
                compareEntryCard
                    .staggeredEntrance(index: 4)

                if windowEntries.count < 2 {
                    emptyState
                        .staggeredEntrance(index: 5)
                } else {
                    sheddingCard
                        .staggeredEntrance(index: 5)
                    scalpCard
                        .staggeredEntrance(index: 6)
                    adherenceCard
                        .staggeredEntrance(index: 7)
                }

                excludedCard
                    .staggeredEntrance(index: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .clinicalScreen()
        .sheet(isPresented: $showCompare) {
            NavigationStack {
                CompareView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showCompare = false } } }
            }
        }
        .sheet(isPresented: $showExport) { ExportSheet() }
        .sheet(isPresented: $showBadges) {
            AchievementsSheet(
                entries: entries, treatments: treatments, doses: doses,
                photos: photos, labs: labs
            )
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("HC_COMPARE") { showCompare = true }
            if args.contains("HC_EXPORT") { showExport = true }
            if args.contains("HC_BADGES") { showBadges = true }
            if args.contains("HC_BODY") {
                // Give the lazy scroll content one beat to lay out before jumping.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { proxy.scrollTo("body-signals", anchor: .top) }
                }
            }
            #endif
        }
    }

    private var compareEntryCard: some View {
        Button { showCompare = true } label: {
            ClinicalCard(padding: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 16)).foregroundStyle(Clinical.accent)
                        .frame(width: 38, height: 38)
                        .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Compare signals").font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.ink)
                        Text("Overlay a hair-fall variable against a lifestyle statistic.")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
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

    // MARK: Baseline context

    private var profile: Profile? { profiles.first }

    // MARK: At-a-glance trajectory

    /// Plain-language orientation before the denser timeline. The chart remains the evidence
    /// surface; this card makes direction and data coverage understandable in a few seconds.
    private var trajectoryCard: some View {
        let summary = TrajectorySummary(entries: windowEntries)
        return ClinicalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: summary.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(summary.tint)
                        .frame(width: 42, height: 42)
                        .background(
                            summary.tint.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "At a glance")
                        Text(summary.headline)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Clinical.ink)
                        Text(summary.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if let average = summary.currentAverage {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(average.formatted(.number.precision(.fractionLength(1))))
                                .font(Clinical.number(22))
                                .foregroundStyle(Clinical.ink)
                                .contentTransition(.numericText())
                            Text("7D AVG")
                                .font(Clinical.eyebrow(8))
                                .foregroundStyle(Clinical.tertiary)
                        }
                    }
                }

                Divider()
                    .overlay(Clinical.hairline)
                    .padding(.vertical, 11)

                HStack(spacing: 14) {
                    Label(summary.coverageLabel, systemImage: "calendar.badge.checkmark")
                    Spacer(minLength: 4)
                    Label(summary.confidenceLabel, systemImage: "waveform.path.ecg")
                }
                .font(Clinical.eyebrow(9))
                .foregroundStyle(Clinical.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    // MARK: Explicitly-not-tracked (honesty made visible)

    private var excludedCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Explicitly not tracked")
                Text("Left out on purpose — the evidence doesn't support them.")
                    .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                ForEach(ExcludedMyth.allCases) { myth in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle").font(.system(size: 12)).foregroundStyle(Clinical.tertiary).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(myth.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Clinical.ink)
                            Text(myth.reason).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Shedding trend

    private var sheddingCard: some View {
        let raw = windowEntries.map { Double($0.shed.rawValue) }
        let smoothed = ChartMath.rollingMean(raw, window: 7)
        let dir = HairAnalytics.direction(raw)
        let points = Array(zip(windowEntries.map(\.date), smoothed))
        let rawPoints = Array(zip(windowEntries.map(\.date), raw))
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Shedding")
                    Spacer()
                    directionTag(dir, invert: true)
                }
                Chart {
                    // Faint raw daily values behind the trend — the honest reality.
                    ForEach(rawPoints, id: \.0) { date, value in
                        PointMark(x: .value("Date", date), y: .value("Shed", value))
                            .symbolSize(12)
                            .foregroundStyle(Clinical.accent.opacity(0.25))
                    }
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
        let raw = windowEntries.map { Double($0.scalpTotal) }
        let smoothed = ChartMath.rollingMean(raw, window: 7)
        let dir = HairAnalytics.direction(raw)
        let points = Array(zip(windowEntries.map(\.date), smoothed))
        let rawPoints = Array(zip(windowEntries.map(\.date), raw))
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
                    // Faint raw daily values behind the trend — the honest reality.
                    ForEach(rawPoints, id: \.0) { date, value in
                        PointMark(x: .value("Date", date), y: .value("Score", value))
                            .symbolSize(12)
                            .foregroundStyle(Clinical.ink.opacity(0.25))
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
        // "Daily" is schedule-driven (not class-driven), so `.other`-class items with slots count.
        let daily = treatments.filter { !$0.slots.isEmpty && $0.isActive }
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "14-day adherence")
                if daily.isEmpty {
                    Text("Add a daily treatment in Care to track adherence.")
                        .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                } else {
                    ForEach(daily) { t in
                        let dates = doses.filter { $0.treatment?.persistentModelID == t.persistentModelID }.map(\.loggedAt)
                        let pct = HairAnalytics.adherence(doseDates: dates, expectedPerDay: t.slots.count) ?? 0
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

/// A small, deterministic interpretation of recent self-reported shedding. It compares two
/// adjacent seven-day calendar windows and keeps thin-data language explicit.
private struct TrajectorySummary {
    let currentAverage: Double?
    let currentCount: Int
    let previousCount: Int
    let delta: Double?

    init(entries: [DailyEntry], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let currentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today

        let current = entries.filter { $0.date >= currentStart && $0.date < tomorrow }
        let previous = entries.filter { $0.date >= previousStart && $0.date < currentStart }

        currentCount = current.count
        previousCount = previous.count
        currentAverage = Self.average(current)
        if let currentAverage, let previousAverage = Self.average(previous) {
            delta = currentAverage - previousAverage
        } else {
            delta = nil
        }
    }

    var headline: String {
        guard currentAverage != nil else { return "No recent check-ins yet" }
        guard let delta, currentCount >= 2, previousCount >= 2 else {
            return "Your recent baseline is forming"
        }
        if delta <= -0.15 { return "Shedding has been lower this week" }
        if delta >= 0.15 { return "Shedding has been higher this week" }
        return "Shedding has been steady this week"
    }

    var detail: String {
        guard currentAverage != nil else {
            return "Log today to start a seven-day view of your pattern."
        }
        guard let delta, currentCount >= 2, previousCount >= 2 else {
            return "Keep logging to compare this week with the seven days before it."
        }
        let magnitude = abs(delta).formatted(.number.precision(.fractionLength(1)))
        if abs(delta) < 0.15 {
            return "The seven-day average is very close to the prior week."
        }
        return "A \(magnitude)-band change versus the previous seven-day average."
    }

    var symbol: String {
        guard let delta, currentCount >= 2, previousCount >= 2 else {
            return "chart.line.uptrend.xyaxis"
        }
        if delta <= -0.15 { return "arrow.down.right" }
        if delta >= 0.15 { return "arrow.up.right" }
        return "arrow.right"
    }

    var tint: Color {
        guard let delta, currentCount >= 2, previousCount >= 2 else { return Clinical.accent }
        if delta <= -0.15 { return Clinical.positive }
        if delta >= 0.15 { return Clinical.warning }
        return Clinical.sage
    }

    var coverageLabel: String { "\(min(currentCount, 7)) of 7 days logged" }

    var confidenceLabel: String {
        switch currentCount {
        case 5...: return "Good coverage"
        case 3...4: return "Building coverage"
        default: return "Limited coverage"
        }
    }

    var accessibilityLabel: String {
        "At a glance. \(headline). \(detail) \(coverageLabel). \(confidenceLabel)."
    }

    private static func average(_ entries: [DailyEntry]) -> Double? {
        guard !entries.isEmpty else { return nil }
        return entries.reduce(0) { $0 + Double($1.shed.rawValue) } / Double(entries.count)
    }
}
