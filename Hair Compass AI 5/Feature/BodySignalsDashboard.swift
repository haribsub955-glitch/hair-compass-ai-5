import Charts
import SwiftData
import SwiftUI
import UIKit

// MARK: - The five signals

/// The evidence-meaningful Health metrics — the only ones this dashboard will ever show.
/// Order is display order. No steps, no calories: if it doesn't bear on hair, it isn't here.
enum BodySignal: String, CaseIterable, Identifiable {
    case sleep, hrv, restingHR, weight, protein

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .hrv: return "HRV"
        case .restingHR: return "Resting HR"
        case .weight: return "Weight"
        case .protein: return "Protein"
        }
    }

    /// The one honest line on why this signal earns a place — the app's tiered voice, never
    /// dressed up as a hair-loss predictor.
    var why: String {
        switch self {
        case .sleep:
            return "Short sleep raises stress load — an indirect but consistent shedding correlate."
        case .hrv:
            return "A recovery/stress proxy — chronic stress is a known telogen-effluvium trigger."
        case .restingHR:
            return "Trends with stress and overtraining; context for HRV, not a hair metric itself."
        case .weight:
            return "Rapid loss (>5% in 3 months) is a classic TE trigger — the app watches this for you."
        case .protein:
            return "Hair is protein — sustained low intake is a documented shedding factor."
        }
    }

    var keyPath: KeyPath<HealthSnapshot, Double?> {
        switch self {
        case .sleep: return \.sleepHours
        case .hrv: return \.hrvSDNN
        case .restingHR: return \.restingHR
        case .weight: return \.bodyMassKg
        case .protein: return \.dietaryProteinG
        }
    }

    /// One tint per metric so every sparkline is identifiable at a glance.
    var tint: Color {
        switch self {
        case .sleep: return Clinical.ink
        case .hrv: return Clinical.sage
        case .restingHR: return Clinical.secondary
        case .weight: return Clinical.accent
        case .protein: return Clinical.gold
        }
    }

    /// Sleep and weight read at one decimal; the rest as whole numbers.
    var usesDecimal: Bool { self == .sleep || self == .weight }

    /// The change below which a delta reads as "no change" — half the display precision,
    /// so a chip never shows a tinted "+0.0".
    var deltaEpsilon: Double { usesDecimal ? 0.05 : 0.5 }

    /// "7.2h" · "48 ms" · "62 bpm" · "77.5 kg" · "112 g"
    func format(_ value: Double) -> String {
        switch self {
        case .sleep: return value.formatted(.number.precision(.fractionLength(1))) + "h"
        case .hrv: return "\(Int(value.rounded())) ms"
        case .restingHR: return "\(Int(value.rounded())) bpm"
        case .weight: return value.formatted(.number.precision(.fractionLength(1))) + " kg"
        case .protein: return "\(Int(value.rounded())) g"
        }
    }

    /// Signed delta in the same unit language: "+0.4h", "−3 ms".
    func formatDelta(_ delta: Double) -> String {
        let sign = delta < 0 ? "−" : "+"
        let magnitude = abs(delta)
        let number = usesDecimal
            ? magnitude.formatted(.number.precision(.fractionLength(1)))
            : magnitude.formatted(.number.precision(.fractionLength(0)))
        let unit: String
        switch self {
        case .sleep: unit = "h"
        case .hrv: unit = " ms"
        case .restingHR: unit = " bpm"
        case .weight: unit = " kg"
        case .protein: unit = " g"
        }
        return sign + number + unit
    }
}

// MARK: - Pure math (unit-tested)

/// Series/delta math for the dashboard. Pure and deterministic — takes plain dated samples,
/// never SwiftData models or views, so BodySignalsTests covers it directly.
enum BodySignalsMath {

    /// How a delta should be read for a given signal — drives the chip tint only.
    enum DeltaTone { case favorable, unfavorable, neutral }

    /// The dated non-nil readings inside the trailing `windowDays`, sorted ascending.
    /// nil is "not available" and is skipped — never coerced to zero.
    static func windowedSeries(
        _ samples: [(date: Date, value: Double?)],
        windowDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [MetricPoint] {
        let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        return samples
            .compactMap { sample in sample.value.map { MetricPoint(date: sample.date, value: $0) } }
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    /// Mean of the current window minus the mean of the previous same-length window.
    /// nil when either side has no readings — no delta beats a fake zero.
    static func delta(
        _ samples: [(date: Date, value: Double?)],
        windowDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let previousCutoff = calendar.date(byAdding: .day, value: -windowDays * 2, to: now) ?? now
        let valued = samples.compactMap { sample in
            sample.value.map { (date: sample.date, value: $0) }
        }
        let current = valued.filter { $0.date >= cutoff }.map(\.value)
        let previous = valued.filter { $0.date >= previousCutoff && $0.date < cutoff }.map(\.value)
        guard current.count >= 3, previous.count >= 3 else { return nil }
        return ChartMath.mean(current) - ChartMath.mean(previous)
    }

    /// Desirability of a delta: more sleep/HRV/protein is favorable, a rising resting HR is
    /// unfavorable, and weight stays neutral — no diet-culture judgment — unless rapid loss
    /// fires, which flips it to a warning. Sub-precision wiggle reads as no change.
    static func tone(for signal: BodySignal, delta: Double, rapidLossActive: Bool = false) -> DeltaTone {
        switch signal {
        case .weight:
            return rapidLossActive ? .unfavorable : .neutral
        case .restingHR:
            guard abs(delta) >= signal.deltaEpsilon else { return .neutral }
            return delta > 0 ? .unfavorable : .favorable
        case .sleep, .hrv, .protein:
            guard abs(delta) >= signal.deltaEpsilon else { return .neutral }
            return delta > 0 ? .favorable : .unfavorable
        }
    }

    /// "−N% in 90d — TE watch" when the rapid-weight-loss rule (>5% in 90 days) fires, else nil.
    static func rapidLossChip(
        massSamples: [(date: Date, massKg: Double)],
        now: Date = .now
    ) -> String? {
        guard let pct = HairAnalytics.rapidWeightLossPercent(samples: massSamples, now: now) else { return nil }
        return "−\(Int(pct.rounded()))% in 90d — TE watch"
    }
}

// MARK: - Dashboard

/// "Body signals" — one card of the evidence-meaningful Apple Health metrics, each row with
/// its latest value, a sparkline of the windowed trend, a delta against the previous
/// same-length window, and one honest line on why it matters for hair.
///
/// A metric renders only when it has ≥3 readings in the window — no empty boxes. With no data
/// at all: authorized shows a quiet one-liner, not-authorized keeps the Connect CTA. The
/// traction-risk and trigger-lag context notes from the old lifestyle card live below the rows.
struct BodySignalsDashboard: View {
    let snapshots: [HealthSnapshot]
    let windowDays: Int
    var hasTractionRisk: Bool = false
    var recentTrigger: TriggerEvent? = nil

    @Environment(HealthKitService.self) private var healthKit
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var connecting = false
    @State private var refreshing = false
    /// Round-8: which signal rows have their "why it matters" sentence disclosed. Previously
    /// every row appended its static educational sentence permanently — four unchanging lines
    /// padding the fold on every visit. Now it's marginalia you invite with a tap, not a
    /// standing lesson; VoiceOver still hears it via the row's accessibility label regardless.
    @State private var expandedSignals: Set<BodySignal> = []

    /// Round-5: dissolved out of its `ClinicalCard` — the largest remaining boxed dashboard
    /// module in the app — into the same un-boxed, hairline-ruled ledger language as Today's
    /// signal ledger and Labs' lab ledger. Same rows, same data, no card edge.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            signalContent
            refreshRow
            contextNotes
        }
    }

    // MARK: Header

    /// One eyebrow line instead of the old display-serif headline ("What your body's saying")
    /// over its own sub-eyebrow — "BODY SIGNALS · from Apple Health" says the same thing once,
    /// matching the margin-ink caption every other screen's section header now uses.
    private var header: some View {
        HStack {
            Eyebrow(text: "Body signals")
            if !visibleSignals.isEmpty || healthKit.authorization.isQueryable {
                Text("·").foregroundStyle(Clinical.tertiary)
                Text("from Apple Health")
                    .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.tertiary)
            }
            Spacer()
        }
    }

    // MARK: Data plumbing

    private func samples(for signal: BodySignal) -> [(date: Date, value: Double?)] {
        snapshots.map { (date: $0.date, value: $0[keyPath: signal.keyPath]) }
    }

    private func series(for signal: BodySignal) -> [MetricPoint] {
        BodySignalsMath.windowedSeries(samples(for: signal), windowDays: windowDays)
    }

    private var seriesCache: [BodySignal: [MetricPoint]] {
        Dictionary(uniqueKeysWithValues: BodySignal.allCases.map { signal in
            (signal, series(for: signal))
        })
    }

    /// Only metrics with enough readings to draw a trend — the rest simply don't appear.
    private var visibleSignals: [BodySignal] {
        let cache = seriesCache
        return BodySignal.allCases.filter { (cache[$0]?.count ?? 0) >= 3 }
    }

    private var massSamples: [(date: Date, massKg: Double)] {
        snapshots.compactMap { s in s.bodyMassKg.map { (date: s.date, massKg: $0) } }
    }

    // MARK: States — rows · quiet · unavailable · connect

    @ViewBuilder
    private var signalContent: some View {
        // Built once per body pass and reused below — `seriesCache` walks every `BodySignal`
        // through `BodySignalsMath.windowedSeries`, so calling it more than once here would
        // redo that work for no reason.
        let cache = seriesCache
        let visible = BodySignal.allCases.filter { (cache[$0]?.count ?? 0) >= 3 }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider().overlay(Clinical.hairline)
                ForEach(visible) { signal in
                    signalRow(signal)
                        .rowFadeIn(reduceMotion: reduceMotion)
                    Divider().overlay(Clinical.hairline)
                }
            }
        } else {
            switch healthKit.authorization {
            case .requestedQueryable:
                // Health has answered and nothing can draw yet: the same shaded placeholder as
                // every other Trends chart, with the most-populated metric's progress, above the
                // existing explanation of why there is no in-app retry for a denied request.
                VStack(alignment: .leading, spacing: 12) {
                    ChartPlaceholder(
                        required: 3,
                        have: cache.values.map(\.count).max() ?? 0,
                        unit: .readings,
                        height: 110
                    )
                    requestedEmptyPrompt
                }
            case .unavailable:
                Text("Apple Health isn't available on this device — lifestyle factors stay manual.")
                    .font(Clinical.caption(14)).foregroundStyle(Clinical.secondary)
            default:
                connectPrompt
            }
        }
    }

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Apple Health to auto-fill sleep, body weight, and a recovery (HRV) stress proxy — no manual entry.")
                .font(Clinical.caption(14)).foregroundStyle(Clinical.secondary)
            Button(connecting ? "Connecting…" : "Connect Apple Health") {
                connecting = true
                Task {
                    await healthKit.requestAuthorization()
                    // Refresh immediately on grant so Trends has data without waiting for the
                    // next launch. A no-op when authorization didn't succeed.
                    await healthKit.refreshSnapshot(context: context)
                    connecting = false
                }
            }
            .buttonStyle(ClinicalButtonStyle(filled: false))
            .disabled(connecting)
        }
    }

    /// iOS never re-presents the system permission sheet once a person has answered it, so a
    /// denied request has no in-app retry — only Settings can change it. Shown instead of the
    /// connect button so tapping never feels like a dead end.
    private var requestedEmptyPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No matching Apple Health samples were found. You may not have recorded these signals yet, or some data types may not be shared with Hair Compass.")
                .font(Clinical.caption(14)).foregroundStyle(Clinical.secondary)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(ClinicalButtonStyle(filled: false))
            .accessibilityIdentifier("trendsHealthOpenSettings")
        }
    }

    /// A quiet manual-refresh affordance shown once Health is authorized — last-updated
    /// timestamp plus a one-tap "Update from Health", so data doesn't only ever arrive passively.
    @ViewBuilder
    private var refreshRow: some View {
        if healthKit.authorization == .requestedQueryable {
            HStack(spacing: 10) {
                Text(healthKit.lastSuccessfulSampleRetrieval.map {
                    "Samples found \($0.formatted(.relative(presentation: .named)))"
                } ?? healthKit.lastRefresh.map { _ in "Last query found no samples" } ?? "Not yet queried")
                    .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                Spacer(minLength: 8)
                Button(refreshing ? "Updating…" : "Update from Health") {
                    refreshing = true
                    Task {
                        await healthKit.refreshSnapshot(context: context)
                        refreshing = false
                    }
                }
                .font(Clinical.body(13, weight: .medium))
                .foregroundStyle(Clinical.accent)
                .disabled(refreshing)
                .accessibilityIdentifier("trendsHealthRefresh")
            }
        }
    }

    // MARK: Signal row

    /// Tapping the row discloses `signal.why` in place with a soft spring (a plain opacity
    /// fade under Reduce Motion) instead of showing it permanently — the numbers stay the row's
    /// focal object and the education becomes marginalia you invite, matching the ledger pattern
    /// everywhere else in the app.
    private func signalRow(_ signal: BodySignal) -> some View {
        let series = seriesCache[signal] ?? []
        let latest = series.last?.value
        let delta = BodySignalsMath.delta(samples(for: signal), windowDays: windowDays)
        let rapidChip = signal == .weight ? BodySignalsMath.rapidLossChip(massSamples: massSamples) : nil
        let expanded = expandedSignals.contains(signal)

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if reduceMotion {
                toggle(signal)
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { toggle(signal) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(signal.title.uppercased())
                            .font(Clinical.eyebrow(10)).tracking(1.2)
                            .foregroundStyle(Clinical.tertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(latest.map(signal.format) ?? "—")
                                .font(Clinical.number(22)).foregroundStyle(Clinical.ink)
                            if let delta {
                                deltaChip(signal: signal, delta: delta, rapidLossActive: rapidChip != nil)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    SignalSparkline(series: series, tint: signal.tint)
                        .frame(width: 116, height: 44)
                }
                if let rapidChip { warningChip(rapidChip) }
                if expanded {
                    Text(signal.why)
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDetail(signal: signal, latest: latest, delta: delta, rapidChip: rapidChip))
        .accessibilityHint(expanded ? "Collapses why it matters" : "Shows why it matters")
    }

    /// The row's full VoiceOver text — value, trend, the rapid-loss warning when active, and the
    /// "why it matters" sentence always, even while it's visually collapsed, so disclosing it on
    /// tap costs sighted users a line of copy but costs VoiceOver users nothing.
    private func accessibilityDetail(signal: BodySignal, latest: Double?, delta: Double?, rapidChip: String?) -> String {
        var parts = [signal.title, latest.map(signal.format) ?? "No reading"]
        if let delta { parts.append(signal.formatDelta(delta)) }
        if let rapidChip { parts.append(rapidChip) }
        parts.append(signal.why)
        return parts.joined(separator: ". ")
    }

    private func toggle(_ signal: BodySignal) {
        if expandedSignals.contains(signal) {
            expandedSignals.remove(signal)
        } else {
            expandedSignals.insert(signal)
        }
    }

    private func deltaChip(signal: BodySignal, delta: Double, rapidLossActive: Bool) -> some View {
        // Ordinary Health deltas are context, not hair outcomes. Only the explicit rapid-loss
        // rule earns warning color; everything else stays neutral numerical language.
        let color: Color = rapidLossActive ? Clinical.warning : Clinical.tertiary
        return Text(signal.formatDelta(delta))
            .font(Clinical.number(12))
            .foregroundStyle(color)
    }

    private func warningChip(_ text: String) -> some View {
        Label(text, systemImage: "arrow.down.right.circle")
            .font(Clinical.eyebrow(10)).tracking(0.4)
            .foregroundStyle(Clinical.warning)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Clinical.warning.opacity(0.12), in: Capsule())
    }

    // MARK: Preserved context notes (traction risk + trigger lag)

    @ViewBuilder
    private var contextNotes: some View {
        if hasTractionRisk {
            contextNote(
                icon: "exclamationmark.triangle",
                color: Clinical.warning,
                text: "Your baseline notes tight styling, heat or chemical treatment. Sustained tension is a preventable cause of traction loss."
            )
        }
        if let recentTrigger {
            contextNote(
                icon: recentTrigger.type.symbol,
                color: Clinical.tertiary,
                text: "\(recentTrigger.type.title), \(recentTrigger.weeksElapsed()) weeks ago. Diffuse shedding often follows a trigger by 2–3 months."
            )
        }
    }

    private func contextNote(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(Clinical.caption(13)).foregroundStyle(color)
            Text(text).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
        }
        .padding(.top, 2)
    }
}

// MARK: - Row entrance

private extension View {
    /// Round-5: each un-boxed signal row fades and softens as it crosses into view while
    /// scrolling, then settles fully sharp/opaque once past the threshold — a quiet "the ledger
    /// writes itself as you read down the page" cue in place of the card's old static reveal.
    /// Reduce Motion drops this entirely: rows are simply visible, no transition at all.
    @ViewBuilder
    func rowFadeIn(reduceMotion: Bool) -> some View {
        if reduceMotion {
            self
        } else {
            self.scrollTransition(axis: .vertical) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.35)
                    .blur(radius: phase.isIdentity ? 0 : 2)
            }
        }
    }
}

// MARK: - Sparkline

/// A tiny single-tint trend: faint raw points under a 7-point smoothed line, axes hidden,
/// y-domain fit to the observed range so weekly-density data still shows its shape.
private struct SignalSparkline: View {
    let series: [MetricPoint]
    let tint: Color

    var body: some View {
        let values = series.map(\.value)
        let smoothed = ChartMath.trailingCalendarMean(
            series.map { (day: $0.date, value: $0.value) }, windowDays: 7
        ).map { MetricPoint(date: $0.day, value: $0.value) }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, 0.001)
        Chart {
            ForEach(series) { point in
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .symbolSize(8)
                    .foregroundStyle(tint.opacity(0.25))
            }
            ForEach(smoothed) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(tint)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .accessibilityHidden(true)
    }
}
