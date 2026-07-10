import Foundation

/// Pure, deterministic analytics. No SwiftData, no UI — this is the unit-tested core.
/// Every rule here is anchored to docs/TrackingSpec.md.
enum HairAnalytics {

    // MARK: - Seborrheic-dermatitis 16-point scale (Zhang 2023)

    /// Maps the 0–3 self-report flaking band onto the validated 0–10 flaking item.
    static func flakingContribution(_ band: Int) -> Int {
        let clamped = min(max(band, 0), 3)
        return [0, 3, 6, 10][clamped]
    }

    static func scalpTotal(flaking: Int, erythema: Int, itch: Int) -> Int {
        flakingContribution(flaking)
            + min(max(erythema, 0), 3)
            + min(max(itch, 0), 3)
    }

    /// Bands from the paper: 0–5 mild · 6–9 moderate · 10–16 severe.
    static func scalpBand(total: Int) -> SeverityBand {
        switch total {
        case ...5: return .mild
        case 6...9: return .moderate
        default: return .severe
        }
    }

    // MARK: - Labs

    static func flag(for value: Double, test: LabTest) -> LabFlag {
        let range = test.referenceRange
        if value < range.lowerBound { return .low }
        if value > range.upperBound { return .high }
        return .normal
    }

    // MARK: - Treatment adherence & the 24-week outcome gate

    /// Standard AGA RCT endpoint for hair-density change (verified 3-0).
    static let outcomeWindowWeeks = 24

    static func weeksElapsed(since start: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.weekOfYear], from: calendar.startOfDay(for: start), to: now).weekOfYear ?? 0)
    }

    /// True once a treatment has run long enough to judge (≥24 weeks).
    static func outcomeReady(weeksElapsed: Int) -> Bool { weeksElapsed >= outcomeWindowWeeks }

    /// 0…1 progress toward the 24-week judging milestone.
    static func outcomeProgress(weeksElapsed: Int) -> Double {
        min(1, Double(weeksElapsed) / Double(outcomeWindowWeeks))
    }

    /// Adherence over a trailing window for a daily treatment.
    /// - Returns nil for non-daily (periodic) treatments where % adherence is meaningless.
    static func adherence(
        doseDates: [Date],
        expectedPerDay: Int,
        windowDays: Int = 14,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        guard expectedPerDay > 0 else { return nil }
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: now)) ?? now
        let logged = doseDates.filter { $0 >= start }.count
        let expected = expectedPerDay * windowDays
        guard expected > 0 else { return nil }
        return min(1, Double(logged) / Double(expected))
    }

    // MARK: - Refill tracking

    /// Whole days from today until `refillBy`, start-of-day to start-of-day.
    /// nil when unset · 0 = due today · negative = overdue.
    static func daysUntilRefill(
        _ refillBy: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        guard let refillBy else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: refillBy)
        ).day
    }

    /// Bands days-remaining into a display urgency:
    /// nil → none · <0 → overdue · 0…7 → urgent · 8…14 → soon · else ok.
    static func refillUrgency(daysLeft: Int?) -> RefillUrgency {
        guard let daysLeft else { return .none }
        switch daysLeft {
        case ..<0: return .overdue
        case 0...7: return .urgent
        case 8...14: return .soon
        default: return .ok
        }
    }

    // MARK: - Tolerability

    /// True when any log is severity 3 within the trailing window — drives the single calm
    /// "worth discussing with your prescriber" banner. A nudge to talk, never advice.
    static func hasRecentSevereSideEffect(
        logs: [(severity: Int, date: Date)],
        windowDays: Int = 14,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let start = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        return logs.contains { $0.severity >= 3 && $0.date >= start && $0.date <= now }
    }

    // MARK: - Rapid weight loss (telogen-effluvium trigger)

    /// A meaningful weight drop over a short window is a recognized shedding trigger, typically
    /// showing up ~2–3 months later. Given dated body-mass samples (kg), returns the percent
    /// drop from the window's peak to its latest reading if it clears the threshold, else nil.
    /// Pure: takes plain samples, not SwiftData models.
    static func rapidWeightLossPercent(
        samples: [(date: Date, massKg: Double)],
        windowDays: Int = 90,
        thresholdPercent: Double = 5,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        let start = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let window = samples.filter { $0.date >= start && $0.massKg > 0 }.sorted { $0.date < $1.date }
        guard let latest = window.last, let peak = window.map(\.massKg).max(), peak > 0 else { return nil }
        let dropPercent = (peak - latest.massKg) / peak * 100
        return dropPercent >= thresholdPercent ? dropPercent : nil
    }

    // MARK: - Trends

    /// Trailing rolling average that keeps series readable instead of noisy.
    static func rollingAverage(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, values.count > 1 else { return values }
        return values.indices.map { i in
            let lo = max(0, i - window + 1)
            let slice = values[lo...i]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// Signed change between the average of the first and last thirds of a series.
    /// Positive = rising. Used for shedding / severity direction readouts.
    static func direction(_ values: [Double]) -> Double {
        guard values.count >= 3 else { return 0 }
        let third = max(1, values.count / 3)
        let head = values.prefix(third)
        let tail = values.suffix(third)
        let headAvg = head.reduce(0, +) / Double(head.count)
        let tailAvg = tail.reduce(0, +) / Double(tail.count)
        return tailAvg - headAvg
    }

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Calendar-day bounds (one-entry-per-day upsert window)

    /// The half-open window covering one calendar day: startOfDay ..< start of the next day.
    /// Used as the fetch window when upserting a `DailyEntry`, so 00:00:00 through 23:59:59
    /// all belong to the day and the next midnight does not.
    static func dayBounds(for day: Date, calendar: Calendar = .current) -> Range<Date> {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return start..<end
    }

    /// Timestamp to store on a log entry for a chosen calendar day: the real clock time when
    /// the day is today, otherwise noon of that day — a stable, unambiguous position inside
    /// the day so backfilled entries sort predictably.
    static func normalizedLogDate(for day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? start
    }

    // MARK: - Streak

    /// Consecutive days (ending today or yesterday) that have a daily entry.
    static func loggingStreak(entryDates: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(entryDates.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            // Allow the streak to still count if today isn't logged yet.
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            guard days.contains(cursor) else { return 0 }
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    /// Displayed streak with Duolingo-style shields: every 7 consecutive logged days earns one
    /// shield (max 2 held); a single-day gap consumes a shield and the run continues through
    /// it; a gap of 2+ days breaks the run. Deterministic and replayable from history — no
    /// stored state. Shields protect the DISPLAYED streak only; XP never mints from them
    /// (`loggingStreak` above stays untouched for that reason).
    static func shieldedStreak(
        entryDates: [Date], now: Date = .now, calendar: Calendar = .current
    ) -> (streak: Int, shieldsHeld: Int) {
        let days = Array(Set(entryDates.map { calendar.startOfDay(for: $0) })).sorted()
        guard !days.isEmpty else { return (0, 0) }

        var run = 0            // consecutive REAL logged days since the last full break —
                                // this is what earns shields; a bridged gap day never adds to it.
        var shields = 0
        var streakStart = days[0]
        var previous: Date?

        for day in days {
            if let previous {
                let gapDays = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
                switch gapDays {
                case 1:
                    // Back-to-back day — the run continues uninterrupted.
                    run += 1
                case 2:
                    // Exactly one day missing in between. A held shield bridges it — the run's
                    // real-day count grows by one (for the day just logged, not the gap day
                    // itself), and the streak's span keeps its original start so the gap day
                    // still counts toward the displayed streak.
                    if shields > 0 {
                        shields -= 1
                        run += 1
                    } else {
                        streakStart = day
                        run = 1
                        shields = 0
                    }
                default:
                    // Two or more days missing — no shield can cover it, the run breaks fresh.
                    streakStart = day
                    run = 1
                    shields = 0
                }
            } else {
                run = 1
            }

            if run > 0, run % 7 == 0 {
                shields = min(2, shields + 1)
            }
            previous = day
        }

        guard let lastDay = previous else { return (0, 0) }
        let daysSinceLast = calendar.dateComponents(
            [.day], from: lastDay, to: calendar.startOfDay(for: now)
        ).day ?? 0
        let isCurrent = daysSinceLast <= 1   // last covered day is today or yesterday.
        let spanDays = calendar.dateComponents([.day], from: streakStart, to: lastDay).day ?? 0
        let streak = isCurrent ? spanDays + 1 : 0

        return (streak, shields)
    }

    // MARK: - Baseline risk readout (context, not prediction)

    /// Orders baseline risk factors by verified effect size for a plain-language readout.
    /// This is descriptive framing only — it does not forecast an individual's outcome.
    static func baselineRiskNotes(familyHistory: FamilyHistory, condition: HairCondition) -> [String] {
        var notes: [String] = []
        switch familyHistory {
        case .bothParents:
            notes.append("Family history in both parents is the strongest measured risk factor for pattern loss.")
        case .oneParent:
            notes.append("A parent with hair loss meaningfully raises pattern-loss risk.")
        case .extended:
            notes.append("Extended-family history is a mild risk signal.")
        case .none:
            notes.append("No known family history recorded.")
        }
        if condition == .androgenetic {
            notes.append("Judge treatment response at 6 months, not sooner.")
        }
        return notes
    }
}
