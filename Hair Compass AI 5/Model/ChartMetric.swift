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

    static func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count) }

    /// Collapse duplicate observations onto calendar days before any smoothing or matching.
    /// This prevents two same-day edits/imports from receiving twice the weight of another day.
    static func dailyAverages(
        _ points: [(day: Date, value: Double)],
        calendar: Calendar = .current
    ) -> [(day: Date, value: Double)] {
        let grouped = Dictionary(grouping: points) { calendar.startOfDay(for: $0.day) }
        return grouped.map { day, values in
            (day: day, value: mean(values.map(\.value)))
        }
        .sorted { $0.day < $1.day }
    }

    /// A trailing calendar-day mean. Unlike `rollingMean`, sparse logging does not turn seven
    /// observations spread across several weeks into something labelled a seven-day trend, and
    /// future observations never influence an earlier point.
    static func trailingCalendarMean(
        _ points: [(day: Date, value: Double)],
        windowDays: Int,
        calendar: Calendar = .current
    ) -> [(day: Date, value: Double)] {
        let daily = dailyAverages(points, calendar: calendar)
        guard windowDays > 1 else { return daily }
        return daily.map { point in
            let lower = calendar.date(
                byAdding: .day,
                value: -(windowDays - 1),
                to: point.day
            ) ?? point.day
            let values = daily.lazy
                .filter { $0.day >= lower && $0.day <= point.day }
                .map(\.value)
            return (day: point.day, value: mean(Array(values)))
        }
    }

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

    /// Spearman rank correlation, including average ranks for ties. Daily self-report bands are
    /// ordinal rather than continuous measurements, so their ordering is more defensible than
    /// assuming equal numeric distance between every label.
    static func rankCorrelation(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 2 else { return nil }
        return correlation(ranks(a), ranks(b))
    }

    /// The honest read: sign + clarity only, gated behind `minPairs` overlapping days.
    static func association(hair: [Double], lifestyle: [Double], minPairs: Int = 8) -> Association {
        guard hair.count == lifestyle.count else { return .insufficient(need: minPairs) }
        guard hair.count >= minPairs else { return .insufficient(need: minPairs) }
        guard let r = rankCorrelation(hair, lifestyle) else { return .unclear }
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

    /// Pair a hair-fall day series with a lifestyle series shifted `lagDays` earlier — i.e. compare
    /// today's shedding against lifestyle from `lagDays` ago (within a ±`tolerance`-day match).
    /// Both inputs are first collapsed to one value per day, and a lifestyle day can be used only
    /// once, preventing sparse context samples from being repeated into an inflated pair count.
    static func pairWithLag(
        hair: [(day: Date, value: Double)],
        lifestyle: [(day: Date, value: Double)],
        lagDays: Int,
        tolerance: Int = 3,
        calendar: Calendar = .current
    ) -> (hair: [Double], lifestyle: [Double]) {
        let dailyHair = dailyAverages(hair, calendar: calendar)
        let dailyLifestyle = dailyAverages(lifestyle, calendar: calendar)
        let lifeByDay = Dictionary(uniqueKeysWithValues: dailyLifestyle.map { ($0.day, $0.value) })
        var usedLifestyleDays: Set<Date> = []
        var h: [Double] = [], l: [Double] = []
        for hp in dailyHair {
            let target = calendar.date(byAdding: .day, value: -lagDays, to: calendar.startOfDay(for: hp.day)) ?? hp.day
            var matched: (day: Date, value: Double)?
            for offset in 0...tolerance {
                for sign in (offset == 0 ? [0] : [-offset, offset]) {
                    if let day = calendar.date(byAdding: .day, value: sign, to: target),
                       !usedLifestyleDays.contains(day), let value = lifeByDay[day] {
                        matched = (day, value); break
                    }
                }
                if matched != nil { break }
            }
            if let matched {
                usedLifestyleDays.insert(matched.day)
                h.append(hp.value)
                l.append(matched.value)
            }
        }
        return (h, l)
    }

    /// The hedged sentence shown to the user — always framed as a noticed pattern, never proof.
    static func phrasing(_ association: Association, hairTitle: String, lifestyleTitle: String, lagDays: Int) -> String {
        let when = lagDays == 0 ? "the same day" : "about \(lagLabel(lagDays)) later"
        switch association {
        case .insufficient:
            // Unreachable from Compare today: `CompareView.readCard` checks `.insufficient`
            // itself and renders `ChartPlaceholderPill` before ever calling `phrasing`. Retained
            // (not deleted) for any future caller that wants the sentence form of this state.
            return "Not enough overlapping days yet to see a pattern. Keep logging."
        case .unclear:
            return "No clear pattern between \(lifestyleTitle.lowercased()) and \(hairTitle.lowercased()) in this window."
        case .together:
            return "When your \(lifestyleTitle.lowercased()) was higher, \(hairTitle.lowercased()) tended to be higher \(when) — a pattern you're noticing, not proof. Many things affect hair."
        case .opposite:
            return "When your \(lifestyleTitle.lowercased()) was higher, \(hairTitle.lowercased()) tended to be lower \(when) — a pattern you're noticing, not proof. Many things affect hair."
        }
    }

    private static func lagLabel(_ days: Int) -> String {
        switch days {
        case 0: return "same day"
        case 1..<14: return "\(days) days"
        case 14..<30: return "\(days / 7) weeks"
        default: return "\(Int((Double(days) / 30).rounded())) months"
        }
    }

    private static func ranks(_ values: [Double]) -> [Double] {
        let sorted = values.enumerated().sorted {
            $0.element == $1.element ? $0.offset < $1.offset : $0.element < $1.element
        }
        var result = Array(repeating: 0.0, count: values.count)
        var index = 0
        while index < sorted.count {
            var end = index + 1
            while end < sorted.count && sorted[end].element == sorted[index].element { end += 1 }
            let averageRank = (Double(index + 1) + Double(end)) / 2
            for rankedIndex in index..<end { result[sorted[rankedIndex].offset] = averageRank }
            index = end
        }
        return result
    }
}
