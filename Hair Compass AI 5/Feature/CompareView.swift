import Charts
import SwiftData
import SwiftUI

/// The Compare builder: overlay one hair-fall variable against one lifestyle statistic, with a lag
/// control (shedding follows lifestyle by weeks) and an honest, hedged read — never a coefficient,
/// never a causal claim. Ephemeral: pick and view, nothing saved.
struct CompareView: View {
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

    @State private var hairID = "shed"
    @State private var overlayID = "sleepQuality"
    @State private var window: Window = .m3
    @State private var lag: Lag = .none

    @State private var showChat = false
    @State private var chatDetent: PresentationDetent = .large
    @State private var chatContext = ""

    enum Window: String, CaseIterable { case m1 = "1M", m3 = "3M", m6 = "6M"
        var days: Int { self == .m1 ? 30 : (self == .m3 ? 90 : 180) }
    }
    enum Lag: String, CaseIterable { case none = "0", w2 = "2wk", w6 = "6wk", m3 = "3mo"
        var days: Int { switch self { case .none: return 0; case .w2: return 14; case .w6: return 42; case .m3: return 90 } }
    }

    private var hair: ChartMetric { ChartMetric[hairID] ?? ChartMetric.hairFall[0] }
    private var overlay: ChartMetric { ChartMetric[overlayID] ?? ChartMetric.lifestyle[0] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: "Build a chart", title: "Compare").padding(.top, 8)

                presets
                    .staggeredEntrance(index: 0)
                pickers
                    .staggeredEntrance(index: 1)

                ClinicalSegmented(options: Window.allCases, label: { $0.rawValue }, selection: $window)
                    .staggeredEntrance(index: 2)

                chartCard
                    .staggeredEntrance(index: 3)
                lagCard
                    .staggeredEntrance(index: 4)
                readCard
                    .staggeredEntrance(index: 5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .clinicalScreen()
        .sheet(isPresented: $showChat) {
            HairChatSheet(contextJSON: chatContext, focus: focusLine)
                .presentationDetents([.medium, .large], selection: $chatDetent)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_CHAT") { openChat() }
            #endif
        }
    }

    // MARK: Selection

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                presetChip("Shedding vs Sleep", "shed", "sleepQuality")
                presetChip("Shedding vs Stress", "shed", "stress")
                presetChip("Scalp vs Sleep", "scalp", "sleepHours")
                presetChip("Shedding vs Weight", "shed", "bodyMass")
            }
        }
    }

    private func presetChip(_ title: String, _ h: String, _ o: String) -> some View {
        let on = hairID == h && overlayID == o
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { hairID = h; overlayID = o }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? Clinical.accent : Clinical.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
        }
        .buttonStyle(.clinicalPressable)
    }

    /// Two stacked scrub-strips — drag across a strip and the sparkline preview (and the chart
    /// behind) re-draws live with the metric under your finger; lifting/tapping selects it.
    private var pickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricScrubber(title: "Hair fall", options: ChartMetric.hairFall, selectionID: $hairID,
                           tint: Clinical.ink,
                           normalizedSeries: { ChartMath.normalize(series(for: $0.id).map(\.value)) })
            HStack(spacing: 10) {
                Rectangle().fill(Clinical.hairline).frame(height: 1)
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                Rectangle().fill(Clinical.hairline).frame(height: 1)
            }
            MetricScrubber(title: "Lifestyle", options: ChartMetric.lifestyle, selectionID: $overlayID,
                           tint: Clinical.sage,
                           normalizedSeries: { ChartMath.normalize(series(for: $0.id).map(\.value)) })
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        let hairPts = series(for: hairID)
        let overlayPts = series(for: overlayID)
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                legend(hairPts: hairPts, overlayPts: overlayPts)
                if hairPts.count < 2 || overlayPts.count < 2 {
                    Text("Not enough data in this window yet — keep logging and connect Health for the auto signals.")
                        .font(.system(size: 13)).foregroundStyle(Clinical.secondary).frame(height: 120, alignment: .center)
                } else {
                    Chart {
                        // Faint daily reality behind the trend — kept visible for honesty.
                        ForEach(normalizedMarks(hairPts, name: hair.title + " (daily)"), id: \.0) { date, v, name in
                            LineMark(x: .value("Date", date), y: .value("Level", v), series: .value("s", name))
                                .interpolationMethod(.monotone).lineStyle(.init(lineWidth: 1))
                                .foregroundStyle(Clinical.ink.opacity(0.22))
                        }
                        ForEach(normalizedMarks(overlayPts, name: overlay.title + " (daily)"), id: \.0) { date, v, name in
                            LineMark(x: .value("Date", date), y: .value("Level", v), series: .value("s", name))
                                .interpolationMethod(.monotone).lineStyle(.init(lineWidth: 1))
                                .foregroundStyle(Clinical.sage.opacity(0.22))
                        }
                        // Smoothed rolling-mean trend on top — this is the line to read.
                        ForEach(smoothedMarks(hairPts, name: hair.title), id: \.0) { date, v, name in
                            LineMark(x: .value("Date", date), y: .value("Level", v), series: .value("s", name))
                                .interpolationMethod(.monotone).lineStyle(.init(lineWidth: 2.5))
                                .foregroundStyle(Clinical.ink)
                        }
                        ForEach(smoothedMarks(overlayPts, name: overlay.title), id: \.0) { date, v, name in
                            LineMark(x: .value("Date", date), y: .value("Level", v), series: .value("s", name))
                                .interpolationMethod(.monotone).lineStyle(.init(lineWidth: 2.5))
                                .foregroundStyle(Clinical.sage)
                        }
                    }
                    .frame(height: 170)
                    .chartYScale(domain: 0...1)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: window == .m1 ? .weekOfYear : .month)) { value in
                            AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                            AxisValueLabel {
                                if let d = value.as(Date.self) {
                                    Text(d.formatted(.dateTime.month(.abbreviated))).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                                }
                            }
                        }
                    }
                    Text("Bold lines are a \(smoothWindow)-day smoothed trend over the faint daily values. Each signal is scaled to its own range, so this shows shape and timing — not absolute levels.")
                        .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
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
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Clinical.ink)
                Text("\(range) \(unit)").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    private var lagCard: some View {
        ClinicalCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Time lag")
                Text("Lifestyle affects shedding weeks later — shift the comparison to line them up.")
                    .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
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

    private var readCard: some View {
        let paired = ChartMath.pairWithLag(hair: series(for: hairID), lifestyle: series(for: overlayID), lagDays: lag.days)
        let assoc = ChartMath.association(hair: paired.hair, lifestyle: paired.lifestyle)
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass").font(.system(size: 15)).foregroundStyle(Clinical.accent)
                    Text(ChartMath.phrasing(assoc, hairTitle: hair.title, lifestyleTitle: overlay.title, lagDays: lag.days))
                        .font(.system(size: 14)).foregroundStyle(Clinical.ink)
                }
                askAIChip
            }
        }
    }

    // MARK: Chat entry point

    /// Same chip language as the presets above: a capsule action that opens the restricted
    /// hair-science chat over the comparison on screen.
    private var askAIChip: some View {
        Button { openChat() } label: {
            Label("Ask AI about this", systemImage: "bubble.left.and.text.bubble.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Clinical.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Clinical.accentSoft)
                .clipShape(Capsule())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel("Ask AI about this comparison")
    }

    /// One line telling the chat what's on screen, so answers land on it.
    private var focusLine: String {
        let lagText = lag == .none ? "no time lag" : "lifestyle shifted \(lag.rawValue) earlier"
        return "User is currently comparing: \(hair.title) (hair fall) vs \(overlay.title) (lifestyle), \(window.rawValue) window, \(lagText)."
    }

    /// Snapshot the canonical AIContext at open time — the chat consumes the same versioned
    /// JSON record as the deep analysis. Text only; photo METADATA in the context, never pixels.
    private func openChat() {
        chatContext = AIContext.build(
            entries: entries, treatments: treatments, doses: doses,
            snapshots: snapshots, triggers: triggers,
            labs: labs, sideEffects: sideEffects, photos: photos,
            profile: profiles.first, now: .now
        ).jsonString()
        showChat = true
    }

    // MARK: Data

    private var cutoff: Date { Calendar.current.date(byAdding: .day, value: -window.days, to: .now) ?? .now }

    private func series(for id: String) -> [(day: Date, value: Double)] {
        let e = entries.filter { $0.date >= cutoff }
        let s = snapshots.filter { $0.date >= cutoff }
        let pairs: [(Date, Double)]
        switch id {
        case "shed": pairs = e.map { ($0.date, Double($0.shed.rawValue)) }
        case "scalp": pairs = e.map { ($0.date, Double($0.scalpTotal)) }
        case "oiliness": pairs = e.map { ($0.date, Double($0.oiliness)) }
        case "sleepQuality": pairs = e.map { ($0.date, Double($0.sleepQuality)) }
        case "stress": pairs = e.map { ($0.date, Double($0.stress)) }
        case "cigarettes": pairs = e.map { ($0.date, Double($0.cigarettes)) }
        case "alcohol": pairs = e.map { ($0.date, Double($0.alcoholDrinks)) }
        case "sleepHours": pairs = s.compactMap { snap in snap.sleepHours.map { (snap.date, $0) } }
        case "hrv": pairs = s.compactMap { snap in snap.hrvSDNN.map { (snap.date, $0) } }
        case "restingHR": pairs = s.compactMap { snap in snap.restingHR.map { (snap.date, $0) } }
        case "bodyMass": pairs = s.compactMap { snap in snap.bodyMassKg.map { (snap.date, $0) } }
        case "protein": pairs = s.compactMap { snap in snap.dietaryProteinG.map { (snap.date, $0) } }
        default: pairs = []
        }
        return pairs.sorted { $0.0 < $1.0 }.map { (day: $0.0, value: $0.1) }
    }

    private func normalizedMarks(_ pts: [(day: Date, value: Double)], name: String) -> [(Date, Double, String)] {
        let norm = ChartMath.normalize(pts.map(\.value))
        return zip(pts, norm).map { ($0.0.day, $0.1, name) }
    }

    /// Rolling-mean window for the smoothed trend — wider for the longer chart windows.
    private var smoothWindow: Int { window == .m1 ? 5 : 7 }

    /// The smoothed display series: centered rolling mean of the RAW values, then normalized to
    /// 0…1 by its own range. Smoothing only — no invented data.
    private func smoothedMarks(_ pts: [(day: Date, value: Double)], name: String) -> [(Date, Double, String)] {
        let smooth = ChartMath.normalize(ChartMath.rollingMean(pts.map(\.value), window: smoothWindow))
        return zip(pts, smooth).map { ($0.0.day, $0.1, name) }
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
