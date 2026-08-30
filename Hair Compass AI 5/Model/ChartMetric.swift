import Foundation

/// The catalog of plottable signals for the Compare builder, plus the pure series/normalization/
/// association math. Correlation is read HONESTLY here — only a sign-and-clarity verdict, never a
/// coefficient, and always gated behind a minimum number of overlapping days.

enum MetricGroup: String, CaseIterable, Identifiable {
    case hairFall = "Hair fall"
    case lifestyle = "Lifestyle"
    case body = "Body & recovery"
    case treatment = "Plan"
    var id: String { rawValue }
}

struct ChartMetric: Identifiable {
    let id: String
    let title: String
    let group: MetricGroup
    let unit: String

    /// Static, hand-authored signals. Treatment metrics (`.treatment` group) are DYNAMIC —
    /// one per active `Treatment`, built per-render by `CompareView.treatmentMetrics` with
    /// ids `"tx.0"`, `"tx.1"`, … — so they are intentionally not listed here.
    static let catalog: [ChartMetric] = [
        // Hair fall
        .init(id: "shed", title: "Shedding", group: .hairFall, unit: "0–3"),
        .init(id: "scalp", title: "Scalp severity", group: .hairFall, unit: "0–16"),
        .init(id: "oiliness", title: "Oiliness", group: .hairFall, unit: "0–3"),
        // Lifestyle (manual)
        .init(id: "sleepQuality", title: "Sleep quality", group: .lifestyle, unit: "1–5"),
        .init(id: "stress", title: "Stress", group: .lifestyle, unit: "1–5"),
        .init(id: "cigarettes", title: "Cigarettes", group: .lifestyle, unit: "count"),
        .init(id: "alcohol", title: "Alcohol", group: .lifestyle, unit: "drinks"),
        // The app's most-taught confound, finally plottable: shed hair is far more visible on
        // wash days, so seeing wash days move with "shedding" is the honest explanation for
        // most day-to-day spikes (same fact `TrajectorySummary.washDayHedge` hedges in prose).
        .init(id: "washDay", title: "Wash day", group: .lifestyle, unit: "washed = 1"),
        // Body & recovery (auto from Health)
        .init(id: "sleepHours", title: "Sleep (hours)", group: .body, unit: "h"),
        .init(id: "hrv", title: "HRV", group: .body, unit: "ms"),
        .init(id: "restingHR", title: "Resting HR", group: .body, unit: "bpm"),
        .init(id: "bodyMass", title: "Body weight", group: .body, unit: "kg"),
        .init(id: "protein", title: "Protein", group: .body, unit: "g"),
    ]

    static subscript(_ id: String) -> ChartMetric? { catalog.first { $0.id == id } }
    static var hairFall: [ChartMetric] { catalog.filter { $0.group == .hairFall } }
    static var lifestyle: [ChartMetric] { catalog.filter { $0.group != .hairFall } }
}

/// A dated value for one metric.
struct MetricPoint: Identifiable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Honest verdict of how two lagged series moved together — no number shown.
enum Association: Equatable {
    case together        // higher lifestyle ↔ higher hair-fall
    case opposite        // higher lifestyle ↔ lower hair-fall
    case unclear         // enough data, but no clear pattern
    case insufficient(need: Int)  // not enough overlapping days
}

enum ChartMath {
    /// Min–max normalize a series to 0…1 by its own observed range (so each line uses full height).
    static func normalize(_ values: [Double]) -> [Double] {
        guard let lo = values.min(), let hi = values.max(), hi > lo else {
            return values.map { _ in 0.5 }
        }
        return values.map { ($0 - lo) / (hi - lo) }
    }

    /// Normalize against explicit shared bounds instead of the series' own range — used to draw
    /// a smoothed trend on the SAME scale as the raw daily values it summarizes. A rolling mean's
    /// own range is always narrower than the raw series', so self-normalizing it re-inflates tiny
    /// wiggles to full chart height and floats the "trend" off the daily cloud it claims to trace.
    static func normalize(_ values: [Double], lo: Double, hi: Double) -> [Double] {
        guard hi > lo else { return values.map { _ in 0.5 } }
        return values.map { min(1, max(0, ($0 - lo) / (hi - lo))) }
    }

    static func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count) }

    /// Centered moving average — smooths daily noise so the trend's shape reads clearly.
    /// For each index the window is `[i-half, i+half]` (half = window/2) clamped to the array
    /// bounds, shrinking at the edges so the ends aren't blank. Same length as the input;
    /// empty input → empty; window ≤ 1 → the input unchanged. Pure and deterministic.
    static func rollingMean(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, !values.isEmpty else { return values }
        let half = window / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            let slice = values[lo...hi]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// Pearson-style correlation on the paired values; used only for its SIGN and MAGNITUDE band.
    static func correlation(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 2 else { return nil }
        let ma = mean(a), mb = mean(b)
        var num = 0.0, da = 0.0, db = 0.0
        for i in a.indices {
            let xa = a[i] - ma, xb = b[i] - mb
            num += xa * xb; da += xa * xa; db += xb * xb
        }
        guard da > 0, db > 0 else { return nil }
        return num / (da * db).squareRoot()
    }

    /// The honest read: sign + clarity only, gated behind `minPairs` overlapping days.
    static func association(hair: [Double], lifestyle: [Double], minPairs: Int = 8) -> Association {
        guard hair.count == lifestyle.count else { return .insufficient(need: minPairs) }
        guard hair.count >= minPairs else { return .insufficient(need: minPairs) }
        guard let r = correlation(hair, lifestyle) else { return .unclear }
        // Scale the clarity gate with sample size. At n=8 a correlation must clear ~0.71 to read as
        // a pattern — |r|=0.25 on a handful of days is indistinguishable from noise, and a worried
        // user anchors on the direction, not the hedge. The bound eases to the 0.25 floor by n≈64.
        if abs(r) < clarityThreshold(pairs: hair.count) { return .unclear }
        return r > 0 ? .together : .opposite
    }

    /// The minimum |correlation| that reads as a directional pattern for a given number of
    /// overlapping day-pairs: an approximate significance-shaped bound `max(0.25, 2/√n)`, never
    /// below the 0.25 floor. Larger samples earn a looser gate; tiny ones must show a strong signal.
    static func clarityThreshold(pairs: Int) -> Double {
        guard pairs > 0 else { return 1 }
        return max(0.25, 2.0 / Double(pairs).squareRoot())
    }

    /// Split a dated (ascending) series into runs of entries no more than `maxGapDays` apart.
    /// Charts draw each run as its own line segment: a connected line across a multi-week
    /// logging gap fabricates a trend where nothing was recorded, and a rolling mean computed
    /// across the gap quietly averages values from before it. Empty input → no segments.
    static func gapSegments(dates: [Date], maxGapDays: Int = 7, calendar: Calendar = .current) -> [Range<Int>] {
        guard !dates.isEmpty else { return [] }
        var segments: [Range<Int>] = []
        var start = 0
        for i in 1..<dates.count {
            let gap = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: dates[i - 1]),
                to: calendar.startOfDay(for: dates[i])
            ).day ?? 0
            if gap > maxGapDays {
                segments.append(start..<i)
                start = i
            }
        }
        segments.append(start..<dates.count)
        return segments
    }

    // MARK: Automatic lag scan

    /// The delays the app teaches (telogen effluvium shows up weeks-to-months after its cause):
    /// same day, 2 weeks, 6 weeks, 3 months. The scan checks all four so nobody has to know to
    /// scrub a lag control to find the one where a real relationship lines up.
    static let scanLags: [Int] = [0, 14, 42, 90]

    /// The clarity gate for the scan. Checking the same two signals at four delays is four looks
    /// at the same data — a Bonferroni-shaped widening (2.5/√n vs the single-look 2/√n, i.e.
    /// roughly α 0.05/4) keeps a lag "discovered" by the scan at least as trustworthy as one the
    /// person picked by hand. Same 0.25 floor as `clarityThreshold`.
    static func scanClarityThreshold(pairs: Int) -> Double {
        guard pairs > 0 else { return 1 }
        return max(0.25, 2.5 / Double(pairs).squareRoot())
    }

    /// What the scan concluded: the delay with the clearest directional pattern (if any), the
    /// verdict at that delay, and how many overlapping days backed it — surfaced to the person
    /// so the read is never a naked claim.
    struct LagScanResult: Equatable {
        let lagDays: Int
        let association: Association
        let pairs: Int
    }

    /// Evaluate the association at every scanned delay and return the clearest one. A delay only
    /// counts when it has `minPairs` overlapping days AND clears `scanClarityThreshold`; among
    /// clear delays the winner is the one with the largest margin over its own gate (not raw |r|,
    /// so a delay with fewer days can't win on an inflated small-sample correlation). With no
    /// clear delay: `.unclear` if at least one delay had enough days to judge, else
    /// `.insufficient` — the same honesty ladder as `association`.
    static func lagScan(
        hair: [(day: Date, value: Double)],
        lifestyle: [(day: Date, value: Double)],
        lags: [Int] = scanLags,
        minPairs: Int = 8,
        calendar: Calendar = .current
    ) -> LagScanResult {
        var best: (lag: Int, margin: Double, association: Association, pairs: Int)?
        var judgeablePairs = 0
        for lag in lags {
            let paired = pairWithLag(hair: hair, lifestyle: lifestyle, lagDays: lag, calendar: calendar)
            let n = paired.hair.count
            guard n >= minPairs else { continue }
            judgeablePairs = max(judgeablePairs, n)
            guard let r = correlation(paired.hair, paired.lifestyle) else { continue }
            let margin = abs(r) - scanClarityThreshold(pairs: n)
            guard margin >= 0 else { continue }
            if best == nil || margin > best!.margin {
                best = (lag, margin, r > 0 ? .together : .opposite, n)
            }
        }
        if let best {
            return LagScanResult(lagDays: best.lag, association: best.association, pairs: best.pairs)
        }
        if judgeablePairs > 0 {
            return LagScanResult(lagDays: 0, association: .unclear, pairs: judgeablePairs)
        }
        return LagScanResult(lagDays: 0, association: .insufficient(need: minPairs), pairs: 0)
    }

    /// The scan's hedged sentence: a found delay reuses the standard phrasing at that delay; an
    /// unclear read says out loud that every delay was checked, so "no pattern" can't be
    /// mistaken for "didn't look".
    static func scanPhrasing(_ result: LagScanResult, hairTitle: String, lifestyleTitle: String) -> String {
        switch result.association {
        case .unclear:
            return "No clear pattern between \(lifestyleTitle.lowercased()) and \(hairTitle.lowercased()) in this window — same-day through 3-month delays all checked."
        case .insufficient, .together, .opposite:
            return phrasing(result.association, hairTitle: hairTitle, lifestyleTitle: lifestyleTitle, lagDays: result.lagDays)
        }
    }

    /// Pair a hair-fall day series with a lifestyle series shifted `lagDays` earlier — i.e. compare
    /// today's shedding against lifestyle from `lagDays` ago (within a ±`tolerance`-day match).
    static func pairWithLag(
        hair: [(day: Date, value: Double)],
        lifestyle: [(day: Date, value: Double)],
        lagDays: Int,
        tolerance: Int = 3,
        calendar: Calendar = .current
    ) -> (hair: [Double], lifestyle: [Double]) {
        var lifeByDay: [Date: Double] = [:]
        for p in lifestyle { lifeByDay[calendar.startOfDay(for: p.day)] = p.value }
        var h: [Double] = [], l: [Double] = []
        for hp in hair {
            let target = calendar.date(byAdding: .day, value: -lagDays, to: calendar.startOfDay(for: hp.day)) ?? hp.day
            var matched: Double?
            for offset in 0...tolerance {
                for sign in (offset == 0 ? [0] : [-offset, offset]) {
                    if let d = calendar.date(byAdding: .day, value: sign, to: target), let v = lifeByDay[d] {
                        matched = v; break
                    }
                }
                if matched != nil { break }
            }
            if let m = matched { h.append(hp.value); l.append(m) }
        }
        return (h, l)
    }

    /// The hedged sentence shown to the user — always framed as a noticed pattern, never proof.
    static func phrasing(_ association: Association, hairTitle: String, lifestyleTitle: String, lagDays: Int) -> String {
        let when = lagDays == 0 ? "the same day" : "about \(lagLabel(lagDays)) later"
        switch association {
        case .insufficient:
            return "Not enough overlapping days yet to see a pattern. Keep logging."
        case .unclear:
            return "No clear pattern between \(lifestyleTitle.lowercased()) and \(hairTitle.lowercased()) in this window."
        case .together:
            return "When your \(lifestyleTitle.lowercased()) was higher, \(hairTitle.lowercased()) tended to be higher \(when) — a pattern you're noticing, not proof. Many things affect hair."
        case .opposite:
            return "When your \(lifestyleTitle.lowercased()) was higher, \(hairTitle.lowercased()) tended to be lower \(when) — a pattern you're noticing, not proof. Many things affect hair."
        }
    }

    /// Human label for a lag in days. Internal (was private) so the Compare focus line can name
    /// the scan's found delay to the chat. 42 days used to fall through to "1 months" — it now
    /// reads "6 weeks", and a true month count pluralizes properly.
    static func lagLabel(_ days: Int) -> String {
        switch days {
        case 0: return "same day"
        case 1..<14: return "\(days) days"
        case 14..<60: return "\(days / 7) weeks"
        default:
            let months = max(1, Int((Double(days) / 30).rounded()))
            return months == 1 ? "1 month" : "\(months) months"
        }
    }
}
