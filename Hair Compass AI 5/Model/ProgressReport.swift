import Foundation
import SwiftData

/// The periodic progress report — the app's promise delivered in one place. It gathers the
/// shedding trajectory, scalp trend, adherence, tolerability, labs and dated triggers into a
/// single honest synthesis, scheduled around the 24-week assessment clock (review milestones
/// at weeks 4 · 12 · 24, then every 12).
///
/// `build` is PURE — plain arrays in, a value struct out, no ModelContext — so every rule here
/// is unit-testable. All math reuses the verified helpers in `HairAnalytics` / `ChartMath`;
/// nothing new is invented. The voice is the app's: non-prescriptive, never "it's working",
/// never "stop taking".
struct ProgressReport {

    // MARK: - Section types

    /// Honest phrasing of a smoothed change. Lower is better for both shed (0–3) and the
    /// scalp SD total (0–16), so a negative delta reads as improving.
    enum TrendVerdict: String {
        case improving, stable, worsening
        var title: String {
            switch self {
            case .improving: return "Improving"
            case .stable: return "Stable"
            case .worsening: return "Worsening"
            }
        }
    }

    /// First-4-weeks vs last-4-weeks means of the 7-day rolling-smoothed series, plus the
    /// points that back the mini-chart. When the logged span is shorter than 8 weeks the two
    /// windows overlap, which pulls the delta toward zero — an honest "too early to call".
    struct Trend {
        let firstWindowMean: Double
        let lastWindowMean: Double
        let delta: Double            // lastWindowMean - firstWindowMean; negative = improving
        let verdict: TrendVerdict
        let scaleMax: Double         // 3 for shed, 16 for the scalp SD total
        let raw: [MetricPoint]       // faint honest reality behind the smoothing
        let smoothed: [MetricPoint]  // 7-day centered rolling mean (ChartMath.rollingMean)
    }

    /// A 14-day dosing window weak enough to blur what the trend can say (< 60%).
    struct WeakStretch: Equatable {
        let start: Date
        let end: Date        // inclusive last day of the 14-day window
        let rate: Double     // 0…1
    }

    struct AdherenceSummary {
        let overall: Double  // 0…1 since treatment start (existing HairAnalytics.adherence)
        let windowDays: Int
        let weakest: WeakStretch?
    }

    struct Tolerability {
        struct Item: Identifiable {
            let id: Int
            let title: String
            let severity: Int    // 1 mild · 2 moderate · 3 severe
            let date: Date
        }
        let mild: Int
        let moderate: Int
        let severe: Int
        let items: [Item]        // newest first
        var total: Int { mild + moderate + severe }
        var hasSevere: Bool { severe > 0 }
    }

    /// Latest value + flag per test present — context for a clinician, never a diagnosis.
    struct LabLine: Identifiable {
        let id: String
        let title: String
        let value: Double
        let unit: String
        let flag: LabFlag
        let date: Date
        var isFlagged: Bool { flag != .normal }
    }

    // MARK: - The report

    let treatment: Treatment?      // primary = earliest active daily treatment, if any
    let treatmentTitle: String?
    let weekNumber: Int            // weeks since the primary treatment start, else first entry
    let periodStart: Date
    let periodEnd: Date
    let entryCount: Int
    let shedTrend: Trend?
    let scalpTrend: Trend?
    let adherence: AdherenceSummary?   // nil when there is no active daily treatment
    let tolerability: Tolerability
    let labs: [LabLine]
    let triggerLines: [String]
    let honestRead: String

    var isMilestoneWeek: Bool { Self.isMilestone(week: weekNumber) }
    var nextMilestoneWeek: Int { Self.nextMilestone(after: weekNumber) }

    // MARK: - Tuning constants (documented, tested)

    /// A report needs something to report on: an active daily treatment, or ≥ 8 weeks of logs.
    static let minimumEntryWeeks = 8

    /// Verdict deadbands — a smoothed first-vs-last-4-weeks change smaller than this reads as
    /// noise, not a trend. Shed is a 0–3 self-report: 0.25 is a quarter step (~8% of scale).
    /// The scalp SD total is 0–16: 1.0 is one point (~6% of scale). Both are deliberately
    /// small-but-real: a change must clear ordinary day-to-day wobble before the report will
    /// call it a direction.
    static let shedDeadband = 0.25
    static let scalpDeadband = 1.0

    /// A two-week dosing stretch below this blurs the trend enough to be worth naming.
    static let weakStretchThreshold = 0.6

    // MARK: - Milestones (weeks 4 · 12 · 24, then every 12: 36, 48, …)

    static func isMilestone(week: Int) -> Bool {
        week == 4 || week == 12 || (week >= 24 && (week - 24) % 12 == 0)
    }

    static func nextMilestone(after week: Int) -> Int {
        if week < 4 { return 4 }
        if week < 12 { return 12 }
        if week < 24 { return 24 }
        return ((week - 24) / 12 + 1) * 12 + 24
    }

    // MARK: - Verdict

    /// Sign-with-deadband read of a smoothed change (same spirit as `HairAnalytics.direction`):
    /// at or beyond the deadband in either direction is a called trend, inside it is "stable".
    /// Lower is better for both tracked scales, so negative = improving.
    static func verdict(delta: Double, deadband: Double) -> TrendVerdict {
        if delta <= -deadband { return .improving }
        if delta >= deadband { return .worsening }
        return .stable
    }

    // MARK: - Builder (pure)

    static func build(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        labs: [LabResult],
        sideEffects: [SideEffectLog],
        triggers: [TriggerEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ProgressReport? {
        let primary = treatments
            .filter { $0.isActive && !$0.slots.isEmpty }   // schedule-driven, so `.other` daily items count
            .min { $0.startDate < $1.startDate }
        let sorted = entries.sorted { $0.date < $1.date }
        let entryWeeks = sorted.first.map {
            HairAnalytics.weeksElapsed(since: $0.date, now: now, calendar: calendar)
        } ?? 0
        // Nothing to report on: no active daily treatment AND under 8 weeks of entries.
        guard primary != nil || entryWeeks >= minimumEntryWeeks else { return nil }

        let periodStart = primary?.startDate ?? sorted.first?.date ?? now
        let weekNumber = HairAnalytics.weeksElapsed(since: periodStart, now: now, calendar: calendar)
        let inPeriod = sorted.filter { $0.date >= periodStart && $0.date <= now }

        let shedTrend = trend(
            dates: inPeriod.map(\.date),
            values: inPeriod.map { Double($0.shed.rawValue) },
            deadband: shedDeadband, scaleMax: 3, calendar: calendar
        )
        let scalpTrend = trend(
            dates: inPeriod.map(\.date),
            values: inPeriod.map { Double($0.scalpTotal) },
            deadband: scalpDeadband, scaleMax: 16, calendar: calendar
        )

        // Adherence since treatment start (existing helper; windowDays = weeks × 7).
        var adherenceSummary: AdherenceSummary?
        if let primary {
            let expectedPerDay = primary.slots.count
            let primaryDoses = doses
                .filter { $0.treatment?.persistentModelID == primary.persistentModelID }
                .map(\.loggedAt)
            let windowDays = max(7, weekNumber * 7)
            if let overall = HairAnalytics.adherence(
                doseDates: primaryDoses, expectedPerDay: expectedPerDay,
                windowDays: windowDays, now: now, calendar: calendar
            ) {
                adherenceSummary = AdherenceSummary(
                    overall: overall,
                    windowDays: windowDays,
                    weakest: weakestStretch(
                        doseDates: primaryDoses, expectedPerDay: expectedPerDay,
                        start: primary.startDate, now: now, calendar: calendar
                    )
                )
            }
        }

        // Tolerability inside the period, counted by severity band.
        let periodEffects = sideEffects
            .filter { $0.date >= periodStart && $0.date <= now }
            .sorted { $0.date > $1.date }
        var mild = 0, moderate = 0, severe = 0
        for log in periodEffects {
            switch min(max(log.severity, 1), 3) {
            case 1: mild += 1
            case 2: moderate += 1
            default: severe += 1
            }
        }
        let tolerability = Tolerability(
            mild: mild, moderate: moderate, severe: severe,
            items: periodEffects.enumerated().map { index, log in
                Tolerability.Item(id: index, title: log.type.title, severity: log.severity, date: log.date)
            }
        )

        // Labs: latest value + flag per test present.
        let labLines = Dictionary(grouping: labs, by: \.testRaw)
            .compactMapValues { $0.max { $0.collectedAt < $1.collectedAt } }
            .values
            .sorted {
                $0.collectedAt != $1.collectedAt
                    ? $0.collectedAt > $1.collectedAt
                    : $0.test.title < $1.test.title
            }
            .map {
                LabLine(id: $0.testRaw, title: $0.test.title, value: $0.value,
                        unit: $0.test.unit, flag: $0.flag, date: $0.collectedAt)
            }

        // Dated triggers inside the period — context the shedding trend should be read against.
        let triggerLines = triggers
            .filter { $0.date >= periodStart && $0.date <= now }
            .sorted { $0.date < $1.date }
            .map { "\($0.type.title) — \(dayString($0.date))" }

        let honest = honestRead(
            weekNumber: weekNumber, hasTreatment: primary != nil,
            shed: shedTrend, scalp: scalpTrend, adherence: adherenceSummary,
            tolerability: tolerability, labs: labLines, hasTrigger: !triggerLines.isEmpty
        )

        return ProgressReport(
            treatment: primary,
            treatmentTitle: primary.map { $0.name.isEmpty ? $0.treatmentClass.title : $0.name },
            weekNumber: weekNumber,
            periodStart: periodStart,
            periodEnd: now,
            entryCount: inPeriod.count,
            shedTrend: shedTrend,
            scalpTrend: scalpTrend,
            adherence: adherenceSummary,
            tolerability: tolerability,
            labs: labLines,
            triggerLines: triggerLines,
            honestRead: honest
        )
    }

    // MARK: - Trend building

    /// First-4-weeks vs last-4-weeks means of the 7-day rolling-smoothed series. The windows
    /// are anchored to the observed entry dates, so each window always contains data.
    private static func trend(
        dates: [Date],
        values: [Double],
        deadband: Double,
        scaleMax: Double,
        calendar: Calendar
    ) -> Trend? {
        guard dates.count >= 2, dates.count == values.count,
              let firstDate = dates.first, let lastDate = dates.last,
              let firstCut = calendar.date(byAdding: .day, value: 28, to: firstDate),
              let lastCut = calendar.date(byAdding: .day, value: -28, to: lastDate)
        else { return nil }

        let smoothedValues = ChartMath.rollingMean(values, window: 7)
        let pairs = Array(zip(dates, smoothedValues))
        let firstWindow = pairs.filter { $0.0 < firstCut }.map(\.1)
        let lastWindow = pairs.filter { $0.0 >= lastCut }.map(\.1)
        let firstMean = HairAnalytics.mean(firstWindow)
        let lastMean = HairAnalytics.mean(lastWindow)
        let delta = lastMean - firstMean

        return Trend(
            firstWindowMean: firstMean,
            lastWindowMean: lastMean,
            delta: delta,
            verdict: verdict(delta: delta, deadband: deadband),
            scaleMax: scaleMax,
            raw: pairs.indices.map { MetricPoint(date: dates[$0], value: values[$0]) },
            smoothed: pairs.map { MetricPoint(date: $0.0, value: $0.1) }
        )
    }

    // MARK: - Weakest 2-week stretch

    /// Slides a 14-day window (7-day steps) across the treatment span and returns the worst
    /// one — but only when it fell below the 60% threshold; a steady regimen returns nil.
    static func weakestStretch(
        doseDates: [Date],
        expectedPerDay: Int,
        start: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeakStretch? {
        guard expectedPerDay > 0 else { return nil }
        let dayStart = calendar.startOfDay(for: start)
        guard let totalDays = calendar.dateComponents([.day], from: dayStart, to: now).day,
              totalDays >= 14
        else { return nil }

        let expected = Double(expectedPerDay * 14)
        var weakest: WeakStretch?
        var offset = 0
        while offset + 14 <= totalDays + 1 {
            guard let winStart = calendar.date(byAdding: .day, value: offset, to: dayStart),
                  let winEnd = calendar.date(byAdding: .day, value: 14, to: winStart),
                  let winLast = calendar.date(byAdding: .day, value: 13, to: winStart)
            else { break }
            let logged = doseDates.filter { $0 >= winStart && $0 < winEnd }.count
            let rate = min(1, Double(logged) / expected)
            if weakest.map({ rate < $0.rate }) ?? true {
                weakest = WeakStretch(start: winStart, end: winLast, rate: rate)
            }
            offset += 7
        }
        guard let weakest, weakest.rate < weakStretchThreshold else { return nil }
        return weakest
    }

    // MARK: - The honest read

    /// The synthesized paragraph, in the app's non-prescriptive voice. Describes trajectories
    /// and records — never a verdict on the treatment, never "it's working" or "stop taking".
    private static func honestRead(
        weekNumber: Int,
        hasTreatment: Bool,
        shed: Trend?,
        scalp: Trend?,
        adherence: AdherenceSummary?,
        tolerability: Tolerability,
        labs: [LabLine],
        hasTrigger: Bool
    ) -> String {
        var sentences: [String] = []
        let ready = HairAnalytics.outcomeReady(weeksElapsed: weekNumber)

        if !hasTreatment {
            sentences.append("Week \(weekNumber) of tracking — no active daily treatment on record, so this report reads your baseline pattern.")
        } else if ready {
            sentences.append("Week \(weekNumber): the assessment window is open — this is the evidence to weigh with your clinician.")
        } else {
            sentences.append("Week \(weekNumber) of \(HairAnalytics.outcomeWindowWeeks) — too early to judge, here's the trajectory so far.")
        }

        if let shed {
            let numbers = "(\(fmt(shed.firstWindowMean)) → \(fmt(shed.lastWindowMean)) of \(fmt(shed.scaleMax)))"
            switch shed.verdict {
            case .improving:
                sentences.append("Smoothed shedding has trended down across the period \(numbers).")
            case .stable:
                sentences.append("Smoothed shedding has held roughly steady \(numbers).")
            case .worsening:
                sentences.append("Smoothed shedding has trended up across the period \(numbers) — worth reading alongside adherence and any dated triggers.")
            }
        }

        if let scalp, scalp.verdict != .stable {
            let numbers = "(\(fmt(scalp.firstWindowMean)) → \(fmt(scalp.lastWindowMean)) of \(fmt(scalp.scaleMax)))"
            sentences.append(scalp.verdict == .improving
                ? "Scalp severity has eased \(numbers)."
                : "Scalp severity has risen \(numbers).")
        }

        if let adherence {
            sentences.append("You logged \(pct(adherence.overall)) of expected doses since the start.")
            if let weak = adherence.weakest {
                sentences.append("The weakest two-week stretch dipped to \(pct(weak.rate)) — patchy stretches blur what a trend can tell you.")
            }
        }

        if tolerability.hasSevere {
            sentences.append("A severe side effect is on record — worth discussing with your prescriber.")
        }

        let flagged = labs.filter(\.isFlagged).count
        if flagged > 0 {
            sentences.append("\(flagged) lab value\(flagged == 1 ? " sits" : "s sit") outside the reference range — context for a clinician, not a diagnosis.")
        }

        if hasTrigger {
            sentences.append("A dated trigger sits inside this window — shedding often lags a trigger by two to three months.")
        }

        if !hasTreatment {
            sentences.append("A steady baseline makes any future treatment easier to judge.")
        } else if ready {
            sentences.append("Nothing here is a verdict on its own — bring it to that conversation.")
        } else {
            sentences.append("Keep logging — the picture sharpens by week \(HairAnalytics.outcomeWindowWeeks).")
        }

        return sentences.joined(separator: " ")
    }

    // MARK: - Plain-text rendering (for ShareLink / clinician conversations)

    func plainText() -> String {
        var out = "HAIR COMPASS — WEEK \(weekNumber) PROGRESS REPORT\n"
        let dates = "\(Self.dayString(periodStart)) – \(Self.dayString(periodEnd))"
        out += treatmentTitle.map { "\($0) · \(dates)\n" } ?? "\(dates)\n"
        out += "A self-tracked record for your own review — not a diagnosis.\n\n"

        if let shedTrend {
            out += "SHEDDING TRAJECTORY\n"
            out += "• First 4 weeks: \(Self.fmt(shedTrend.firstWindowMean))/\(Self.fmt(shedTrend.scaleMax)) · Last 4 weeks: \(Self.fmt(shedTrend.lastWindowMean))/\(Self.fmt(shedTrend.scaleMax)) — \(shedTrend.verdict.rawValue)\n\n"
        }
        if let scalpTrend {
            out += "SCALP SEVERITY\n"
            out += "• First 4 weeks: \(Self.fmt(scalpTrend.firstWindowMean))/\(Self.fmt(scalpTrend.scaleMax)) · Last 4 weeks: \(Self.fmt(scalpTrend.lastWindowMean))/\(Self.fmt(scalpTrend.scaleMax)) — \(scalpTrend.verdict.rawValue)\n\n"
        }
        if let adherence {
            out += "ADHERENCE\n"
            out += "• \(Self.pct(adherence.overall)) of expected doses over the last \(adherence.windowDays) days\n"
            if let weak = adherence.weakest {
                out += "• Weakest 2-week stretch: \(Self.dayString(weak.start)) – \(Self.dayString(weak.end)) at \(Self.pct(weak.rate))\n"
            }
            out += "\n"
        }

        out += "TOLERABILITY\n"
        out += tolerability.total == 0
            ? "• Nothing logged this period\n\n"
            : "• \(tolerability.mild) mild · \(tolerability.moderate) moderate · \(tolerability.severe) severe\n\n"

        if !labs.isEmpty {
            out += "LABS (latest per test)\n"
            for lab in labs {
                out += "• \(lab.title): \(Self.fmt(lab.value)) \(lab.unit) [\(lab.flag.title)] — \(Self.dayString(lab.date))\n"
            }
            out += "\n"
        }
        if !triggerLines.isEmpty {
            out += "TRIGGER EVENTS\n"
            for line in triggerLines { out += "• \(line)\n" }
            out += "\n"
        }

        out += "THE HONEST READ\n\(honestRead)\n\n"
        out += "Hair-density change is judged at 24 weeks in clinical trials — resist judging sooner."
        return out
    }

    // MARK: - Formatting helpers

    private static func fmt(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    private static func pct(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }

    private static func dayString(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
