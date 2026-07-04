import Charts
import SwiftData
import SwiftUI

struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitService.self) private var healthKit
    @Query(sort: \DailyEntry.date) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \TriggerEvent.date, order: .reverse) private var triggers: [TriggerEvent]
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \PhotoRecord.createdAt) private var photos: [PhotoRecord]
    @Query(sort: \LabResult.collectedAt) private var labs: [LabResult]

    @State private var connecting = false
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Longitudinal",
                    title: "Trends",
                    trailing: AnyView(
                        Button { showExport = true } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18)).foregroundStyle(Clinical.ink)
                        }
                    )
                ).padding(.top, 8)

                BrandBanner(art: BrandArt.trends, height: 108)

                ClinicalSegmented(options: Range.allCases, label: { $0.rawValue }, selection: $range)

                JourneyChart(
                    entries: entries,
                    treatments: treatments,
                    doses: doses,
                    triggers: triggers,
                    windowDays: range.days
                )

                ConsistencyCard(
                    entries: entries,
                    treatments: treatments,
                    doses: doses,
                    photos: photos,
                    labs: labs,
                    triggers: triggers,
                    showAllBadges: $showBadges
                )

                lifestyleCard
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
            .padding(.bottom, 110)
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

    // MARK: Lifestyle signals (auto-fetched from Health) + context

    private var latestSnapshot: HealthSnapshot? { snapshots.last }
    private var profile: Profile? { profiles.first }

    private var rapidWeightLossPercent: Double? {
        let samples = snapshots.compactMap { s -> (date: Date, massKg: Double)? in
            guard let m = s.bodyMassKg else { return nil }
            return (s.date, m)
        }
        return HairAnalytics.rapidWeightLossPercent(samples: samples)
    }

    private var lifestyleCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Lifestyle signals")
                    Spacer()
                    if healthKit.authorization.isUsable {
                        Label("Auto from Health", systemImage: "heart.text.square")
                            .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.tertiary)
                    }
                }

                switch healthKit.authorization {
                case .unavailable:
                    Text("Apple Health isn't available on this device — lifestyle factors stay manual.")
                        .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                case .authorized:
                    healthMetrics
                default:
                    connectPrompt
                }

                if let pct = rapidWeightLossPercent {
                    contextNote(
                        icon: "arrow.down.right.circle",
                        color: Clinical.warning,
                        text: "Body weight is down about \(Int(pct.rounded()))% recently. Rapid loss can trigger shedding ~2–3 months later — worth watching."
                    )
                }
                if profile?.hasTractionRisk == true {
                    contextNote(
                        icon: "exclamationmark.triangle",
                        color: Clinical.warning,
                        text: "Your baseline notes tight styling, heat or chemical treatment. Sustained tension is a preventable cause of traction loss."
                    )
                }
                if let recent = triggers.first {
                    contextNote(
                        icon: recent.type.symbol,
                        color: Clinical.tertiary,
                        text: "\(recent.type.title), \(recent.weeksElapsed()) weeks ago. Diffuse shedding often follows a trigger by 2–3 months."
                    )
                }
            }
        }
    }

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Apple Health to auto-fill sleep, body weight, and a recovery (HRV) stress proxy — no manual entry.")
                .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
            Button(connecting ? "Connecting…" : "Connect Apple Health") {
                connecting = true
                Task {
                    await healthKit.requestAuthorization()
                    await healthKit.refreshSnapshot(context: context)
                    connecting = false
                }
            }
            .buttonStyle(ClinicalButtonStyle(filled: false))
            .disabled(connecting)
        }
    }

    private var healthMetrics: some View {
        let s = latestSnapshot
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                metric(s?.sleepHours.map { String(format: "%.1f h", $0) }, "Sleep")
                Divider().frame(height: 34)
                metric(s?.hrvSDNN.map { "\(Int($0.rounded())) ms" }, "HRV")
                Divider().frame(height: 34)
                metric(s?.bodyMassKg.map { String(format: "%.1f kg", $0) }, "Weight")
            }
            if s?.hasAnyValue != true {
                Text("Connected — no readings yet. Values appear once Health has data for today.")
                    .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
            } else {
                Text("HRV is shown as a stress/recovery proxy — there's no evidence it predicts hair loss directly.")
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    private func metric(_ value: String?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value ?? "—")
                .font(Clinical.number(16))
                .foregroundStyle(value == nil ? Clinical.tertiary : Clinical.ink)
            Text(label.uppercased())
                .font(Clinical.eyebrow(9)).tracking(1).foregroundStyle(Clinical.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contextNote(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
        }
        .padding(.top, 2)
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
