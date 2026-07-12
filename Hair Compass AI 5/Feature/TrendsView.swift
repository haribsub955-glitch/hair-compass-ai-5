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
    @Query(sort: \ProgressCheckIn.date) private var progressCheckIns: [ProgressCheckIn]
    @Query(sort: \ProcedureAppointment.date) private var procedureAppointments: [ProcedureAppointment]

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
                        // Solid ink disc — same treatment as the + buttons on Plan/Labs — so
                        // the icon reads clearly on top of the sprig's densest leaf cluster
                        // instead of a bare glyph losing contrast against the artwork.
                        HeaderActionButton(
                            systemName: "square.and.arrow.up",
                            accessibilityLabel: "Export trends"
                        ) {
                            showExport = true
                        }
                    )
                )
                .padding(.top, 8)
                // Unboxed brand accent: the sprig bleeds from the screen's top-right behind the
                // header. Background views take no layout space (no horizontal scroll), and the
                // share button stays tappable — the art never hit-tests. Inset smaller than the
                // other tabs' default so it clears the 1M/3M/6M segmented control just below.
                .background(alignment: .topTrailing) { CornerSprig(width: 150) }

                ClinicalSegmented(options: Range.allCases, label: { $0.rawValue }, selection: $range)

                trajectoryCard

                JourneyChart(
                    entries: entries,
                    treatments: treatments,
                    doses: doses,
                    triggers: triggers,
                    procedures: procedureAppointments,
                    windowDays: range.days
                )

                progressCheckInsCard

                ConsistencyCard(
                    entries: entries,
                    treatments: treatments,
                    doses: doses,
                    photos: photos,
                    labs: labs,
                    triggers: triggers,
                    showAllBadges: $showBadges
                )

                StrandDivider()

                BodySignalsDashboard(
                    snapshots: snapshots,
                    windowDays: range.days,
                    hasTractionRisk: profile?.hasTractionRisk == true,
                    recentTrigger: triggers.first
                )
                .id("body-signals")
                compareEntryCard

                if windowEntries.count < 2 {
                    emptyState
                } else {
                    sheddingCard
                    scalpCard
                    adherenceCard
                }

                excludedCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // Trends is a reference surface, not a motion surface: the user reported chart elements
        // sliding "left and right" on interaction. The outer scroll is width-locked (content ==
        // viewport, verified), so that motion was never a horizontal pan — it was Swift Charts
        // animating mark/domain changes (e.g. tapping 1M/3M/6M) and entrance transitions sliding
        // the plotted line. Nil-ing the transaction animation for this subtree makes every data
        // or range change snap into place instead of interpolating, so nothing drifts on touch.
        .transaction { $0.animation = nil }
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

    // MARK: - Monthly check-ins (slow-moving, self-reported)

    /// The monthly `ProgressCheckIn` answers are collected but were never shown back — this
    /// renders the stored values as-is: a dot per month per question, colored by the trend the
    /// user already picked, plus the latest regrowth level and a prominent scalp-pain flag.
    /// Deterministic, no new math.
    @ViewBuilder
    private var progressCheckInsCard: some View {
        if !progressCheckIns.isEmpty {
            let sorted = progressCheckIns.sorted { $0.date < $1.date }
            ClinicalCard {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Monthly check-ins")
                    Text("Your own answers to the questions a dermatologist asks between visits.")
                        .font(.system(size: 12)).foregroundStyle(Clinical.secondary)

                    if let latest = sorted.last {
                        HStack(spacing: 6) {
                            Text("Latest regrowth").font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                            Text(latest.regrowth.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Clinical.ink)
                            Spacer()
                            Text(latest.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        checkInTrendRow(title: "Density", question: .density, checkIns: sorted)
                        checkInTrendRow(title: "Shedding", question: .shedding, checkIns: sorted)
                        checkInTrendRow(title: "Hairline", question: .hairline, checkIns: sorted)
                        checkInTrendRow(title: "Overall", question: .overall, checkIns: sorted)
                    }

                    // A genuine red flag — persistent scalp pain can mean scarring alopecia.
                    // Surfaced from the most recent check-in that reported it, however long ago.
                    if let pain = sorted.reversed().first(where: { $0.scalpPain }) {
                        Label(
                            "Scalp pain reported \(pain.date.formatted(.dateTime.month(.abbreviated).day())) — worth a prompt dermatology review.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Clinical.warning)
                    }
                }
            }
        }
    }

    private func checkInTrendRow(title: String, question: ProgressTrend.Question, checkIns: [ProgressCheckIn]) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Clinical.ink)
                .frame(width: 64, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(Array(checkIns.enumerated()), id: \.offset) { _, checkIn in
                    Circle()
                        .fill(trendDotColor(Self.trendValue(checkIn, question)))
                        .frame(width: 8, height: 8)
                }
            }
            Spacer(minLength: 8)
            if let last = checkIns.last {
                Text(Self.trendValue(last, question).label(for: question))
                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title): " + checkIns.map { Self.trendValue($0, question).label(for: question) }.joined(separator: ", then ")
        )
    }

    private static func trendValue(_ checkIn: ProgressCheckIn, _ question: ProgressTrend.Question) -> ProgressTrend {
        switch question {
        case .density: return checkIn.density
        case .shedding: return checkIn.shedding
        case .hairline: return checkIn.hairline
        case .overall: return checkIn.overall
        }
    }

    private func trendDotColor(_ trend: ProgressTrend) -> Color {
        switch trend {
        case .worse: return Clinical.warning
        case .same: return Clinical.tertiary
        case .better: return Clinical.sage
        }
    }

    private var emptyState: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 8) {
                // UX audit #9: the fresh-install "no trends yet" card gets the compass-trail
                // vignette instead of reading as bare, unfinished chrome.
                Image("trends-journey-empty")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
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
        // Wash days read heavier for reasons that have nothing to do with a real change — marked
        // hollow on the actual daily reading so the honest reason for a spike stays visible
        // instead of silently blending into "shedding has been higher."
        let washPoints: [(Date, Double)] = windowEntries.compactMap {
            $0.washedHair ? ($0.date, Double($0.shed.rawValue)) : nil
        }
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
                    ForEach(washPoints, id: \.0) { date, value in
                        PointMark(x: .value("Date", date), y: .value("Shed", value))
                            .symbol {
                                Circle()
                                    .strokeBorder(Clinical.ink, lineWidth: 1.3)
                                    .frame(width: 7, height: 7)
                            }
                    }
                }
                .frame(height: 150)
                .chartYScale(domain: 0...3)
                .chartYAxis { yAxis([0, 1, 2, 3], labels: ["Low", "Normal", "High", "Heavy"]) }
                .chartXAxis { xAxis }
                if !washPoints.isEmpty {
                    HStack(spacing: 5) {
                        Circle().strokeBorder(Clinical.ink, lineWidth: 1.2).frame(width: 7, height: 7)
                        Text("Wash day — shed reads heavier, not necessarily worse.")
                            .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                    }
                }
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
                    // Complete words only (no abbreviations that could read as truncated) —
                    // fixedSize + a wide-enough gutter guarantees every label draws in full.
                    Text(labels[idx])
                        .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 44, alignment: .trailing)   // pin gutter — stops horizontal breathing
                }
            }
        }
    }
}

/// A small, deterministic interpretation of recent self-reported shedding. It compares two
/// adjacent seven-day calendar windows and keeps thin-data language explicit.
/// Internal (not file-private) so its wash-day-hedge logic is unit-testable.
struct TrajectorySummary {
    let currentAverage: Double?
    let currentCount: Int
    let previousCount: Int
    let delta: Double?
    /// Wash days logged in each seven-day window — the confound behind a false "shedding rose"
    /// read (shed hair is far more visible on wash days than dry ones).
    let currentWashDays: Int
    let previousWashDays: Int

    init(entries: [DailyEntry], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let currentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today

        let current = entries.filter { $0.date >= currentStart && $0.date < tomorrow }
        let previous = entries.filter { $0.date >= previousStart && $0.date < currentStart }

        currentCount = current.count
        previousCount = previous.count
        currentWashDays = current.filter(\.washedHair).count
        previousWashDays = previous.filter(\.washedHair).count
        currentAverage = Self.average(current)
        if let currentAverage, let previousAverage = Self.average(previous) {
            delta = currentAverage - previousAverage
        } else {
            delta = nil
        }
    }

    /// Only surfaced once a delta is actually being reported, and only when the two windows'
    /// wash-day counts genuinely differ — never new data, just an honest caveat on the claim
    /// already being made.
    var washDayHedge: String? {
        guard let delta, currentCount >= 2, previousCount >= 2, abs(delta) >= 0.15 else { return nil }
        guard currentWashDays != previousWashDays else { return nil }
        return " This week had \(currentWashDays) wash day\(currentWashDays == 1 ? "" : "s") vs \(previousWashDays) last week — wash days show more shed."
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
        return "A \(magnitude)-band change versus the previous seven-day average." + (washDayHedge ?? "")
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
