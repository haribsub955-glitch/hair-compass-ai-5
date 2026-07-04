import Foundation
import SwiftData

// The gamification engine — XP, a botanical level ladder, and badges.
//
// HARD RULE (evidence-honest): every point and every badge here derives ONLY from the
// tracking *process* — logging, dosing, photographing, labs, streaks, time milestones.
// Nothing is ever awarded for shedding going down or severity improving, and nothing is
// ever taken away when a condition worsens. A hard week costs no XP.
//
// Everything is PURE and replayable: plain model arrays in, values out, `now` injected for
// testability. No schema changes — the only persisted gamification state is the
// "seenAchievements" set in UserDefaults (UI layer), used purely to know which badges are
// newly earned since the user last looked.

// MARK: - XP awards

enum XP {

    /// +10 for each calendar day that has a daily log. One entry per day counts once —
    /// the reward is for showing up, not for typing more.
    static let dailyLog = 10

    /// +3 per logged treatment dose, with at most `doseCountCapPerDay` doses counted per
    /// calendar day — so a twice-daily regimen is fully rewarded but bulk-tapping isn't.
    static let doseLogged = 3

    /// Maximum doses that earn XP on any single calendar day.
    static let doseCountCapPerDay = 2

    /// +15 per photo session — a unique (calendar day, region) pair. Re-shooting the same
    /// region on the same day counts once.
    static let photoSession = 15

    /// +20 per lab result on record — the rarest, highest-effort artifact in the app.
    static let labResult = 20

    /// +5 per dated trigger event — recording context is effort worth acknowledging.
    static let triggerLogged = 5

    /// Streak bonus: day k of an unbroken run of daily logs earns an extra
    /// `2 × (k − 1)` XP, capped at +20 for any single day. Day 1 of a run earns no bonus;
    /// day 2 earns +2, day 3 +4, … day 11 and beyond +20. Breaking a streak never removes
    /// XP already earned — a lapse just restarts the bonus curve, it is never a punishment.
    static let streakBonusPerDay = 2
    static let streakBonusDailyCap = 20

    /// Total XP — a pure, deterministic fold over the data arrays. Replaying the same
    /// history always yields the same number. Events dated after `now` are ignored.
    static func total(
        entries: [DailyEntry],
        doses: [TreatmentDose],
        photos: [PhotoRecord],
        labs: [LabResult],
        triggers: [TriggerEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let entryDays = loggedDays(entries: entries, now: now, calendar: calendar)
        var xp = entryDays.count * dailyLog
        xp += streakBonus(days: entryDays, calendar: calendar)

        // Doses, capped per calendar day.
        let dosesByDay = Dictionary(grouping: doses.filter { $0.loggedAt <= now }) {
            calendar.startOfDay(for: $0.loggedAt)
        }
        xp += dosesByDay.values.reduce(0) { $0 + min($1.count, doseCountCapPerDay) } * doseLogged

        // Photos: unique (day, region) sessions.
        var sessions = Set<String>()
        for photo in photos where photo.createdAt <= now {
            let day = calendar.startOfDay(for: photo.createdAt)
            sessions.insert("\(day.timeIntervalSinceReferenceDate)|\(photo.regionRaw)")
        }
        xp += sessions.count * photoSession

        xp += labs.filter { $0.collectedAt <= now }.count * labResult
        xp += triggers.filter { $0.date <= now }.count * triggerLogged
        return xp
    }

    /// Unique logged calendar days (start-of-day), excluding future-dated entries.
    static func loggedDays(entries: [DailyEntry], now: Date, calendar: Calendar) -> Set<Date> {
        Set(entries.filter { $0.date <= now }.map { calendar.startOfDay(for: $0.date) })
    }

    /// Sum of the streak bonuses over every run in the history (see `streakBonusPerDay`).
    static func streakBonus(days: Set<Date>, calendar: Calendar = .current) -> Int {
        var bonus = 0
        var runLength = 0
        var previous: Date?
        for day in days.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                runLength += 1
            } else {
                runLength = 1
            }
            previous = day
            bonus += min(streakBonusDailyCap, streakBonusPerDay * (runLength - 1))
        }
        return bonus
    }
}

// MARK: - Level ladder

/// The botanical growth ladder — Seed to Evergreen. Thresholds are cumulative XP; the names
/// deliberately describe the *record* growing, never the hair.
struct GamificationLevel: Equatable {
    let index: Int          // 1-based, for "Level N"
    let name: String
    let threshold: Int      // XP at which this level begins

    static let ladder: [GamificationLevel] = [
        GamificationLevel(index: 1, name: "Seed", threshold: 0),
        GamificationLevel(index: 2, name: "Seedling", threshold: 150),
        GamificationLevel(index: 3, name: "Sprout", threshold: 400),
        GamificationLevel(index: 4, name: "Sapling", threshold: 900),
        GamificationLevel(index: 5, name: "Grove", threshold: 1800),
        GamificationLevel(index: 6, name: "Canopy", threshold: 3200),
        GamificationLevel(index: 7, name: "Evergreen", threshold: 5000),
    ]

    /// The highest rung whose threshold the XP has reached.
    static func level(for xp: Int) -> GamificationLevel {
        ladder.last { xp >= $0.threshold } ?? ladder[0]
    }

    /// Progress from the current rung toward the next: 0…1 fraction, XP remaining, and the
    /// next rung (nil at the top — Evergreen reads as complete, fraction 1).
    static func progressToNext(xp: Int) -> (fraction: Double, remaining: Int, next: GamificationLevel?) {
        let current = level(for: xp)
        guard let nextIndex = ladder.firstIndex(of: current).map({ $0 + 1 }),
              nextIndex < ladder.count
        else { return (1, 0, nil) }
        let next = ladder[nextIndex]
        let span = next.threshold - current.threshold
        let into = xp - current.threshold
        let fraction = span > 0 ? min(1, max(0, Double(into) / Double(span))) : 1
        return (fraction, max(0, next.threshold - xp), next)
    }
}

// MARK: - Achievements

/// Effort badges. Each one is earned by *doing the work of tracking* — never by an outcome.
/// `earnedDate` is evaluated purely from the data arrays, so a badge is deterministic and
/// survives reinstalls; once the history contains the qualifying moment, it stays earned
/// (a broken streak does not un-earn `streak7`).
enum Achievement: String, CaseIterable, Identifiable {
    case firstLog
    case streak7
    case streak30
    case streak90
    case entryCount30
    case firstPhoto
    case fullPhotoSet
    case firstLab
    case firstTreatment
    case adherence4w90
    case sideEffectAware
    case week12
    case week24

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstLog: return "First seed"
        case .streak7: return "A week of tending"
        case .streak30: return "A month, unbroken"
        case .streak90: return "A season of care"
        case .entryCount30: return "Thirty days of showing up"
        case .firstPhoto: return "First light"
        case .fullPhotoSet: return "Every angle"
        case .firstLab: return "Grounded in numbers"
        case .firstTreatment: return "A plan takes root"
        case .adherence4w90: return "Steady hands"
        case .sideEffectAware: return "An honest record"
        case .week12: return "Twelve weeks in"
        case .week24: return "The long view"
        }
    }

    var caption: String {
        switch self {
        case .firstLog: return "Your first daily log — every record starts here."
        case .streak7: return "Seven consecutive days logged."
        case .streak30: return "Thirty consecutive days logged."
        case .streak90: return "Ninety consecutive days logged."
        case .entryCount30: return "Thirty daily logs in total — gaps and all."
        case .firstPhoto: return "Your first progress photo."
        case .fullPhotoSet: return "All five regions photographed at least once."
        case .firstLab: return "Your first lab result on record."
        case .firstTreatment: return "Your first treatment on record."
        case .adherence4w90: return "Nine in ten doses logged across four weeks."
        case .sideEffectAware: return "You noted how a treatment actually felt."
        case .week12: return "Twelve weeks of keeping the record — a review milestone."
        case .week24: return "Twenty-four weeks — the honest assessment window opens."
        }
    }

    var symbol: String {
        switch self {
        case .firstLog: return "leaf"
        case .streak7: return "flame"
        case .streak30: return "flame.fill"
        case .streak90: return "laurel.leading"
        case .entryCount30: return "calendar"
        case .firstPhoto: return "camera"
        case .fullPhotoSet: return "camera.viewfinder"
        case .firstLab: return "testtube.2"
        case .firstTreatment: return "pills"
        case .adherence4w90: return "calendar.badge.checkmark"
        case .sideEffectAware: return "heart.text.square"
        case .week12: return "hourglass"
        case .week24: return "tree"
        }
    }

    /// The moment this badge was earned, or nil if it hasn't been. Pure — arrays in,
    /// a date out; events after `now` are ignored so the result is replayable.
    func earnedDate(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        photos: [PhotoRecord],
        labs: [LabResult],
        sideEffects: [SideEffectLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        switch self {
        case .firstLog:
            return entries.map(\.date).filter { $0 <= now }.min()

        case .streak7, .streak30, .streak90:
            let target = self == .streak7 ? 7 : (self == .streak30 ? 30 : 90)
            let days = XP.loggedDays(entries: entries, now: now, calendar: calendar)
            return Self.dayStreakFirstReached(target, days: days, calendar: calendar)

        case .entryCount30:
            let days = XP.loggedDays(entries: entries, now: now, calendar: calendar).sorted()
            return days.count >= 30 ? days[29] : nil

        case .firstPhoto:
            return photos.map(\.createdAt).filter { $0 <= now }.min()

        case .fullPhotoSet:
            let inTime = photos.filter { $0.createdAt <= now }
            var firstPerRegion: [Date] = []
            for region in PhotoRegion.allCases {
                guard let first = inTime.filter({ $0.region == region }).map(\.createdAt).min()
                else { return nil }
                firstPerRegion.append(first)
            }
            return firstPerRegion.max()   // the day the set was completed

        case .firstLab:
            return labs.map(\.collectedAt).filter { $0 <= now }.min()

        case .firstTreatment:
            return treatments.map(\.startDate).filter { $0 <= now }.min()

        case .adherence4w90:
            return Self.adherenceWindowFirstMet(
                treatments: treatments, doses: doses, now: now, calendar: calendar
            )

        case .sideEffectAware:
            return sideEffects.map(\.date).filter { $0 <= now }.min()

        case .week12, .week24:
            // Anchored to the start of the record (first entry or first treatment start);
            // the weeks-4/12/24 cadence mirrors ProgressReport.isMilestone.
            let weeks = self == .week12 ? 12 : 24
            let anchors = (entries.map(\.date) + treatments.map(\.startDate)).filter { $0 <= now }
            guard let anchor = anchors.min(),
                  HairAnalytics.weeksElapsed(since: anchor, now: now, calendar: calendar) >= weeks
            else { return nil }
            return calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: anchor))
        }
    }

    /// Every earned badge with its date, oldest first.
    static func earnedList(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        photos: [PhotoRecord],
        labs: [LabResult],
        sideEffects: [SideEffectLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(achievement: Achievement, date: Date)] {
        allCases.compactMap { badge in
            badge.earnedDate(
                entries: entries, treatments: treatments, doses: doses,
                photos: photos, labs: labs, sideEffects: sideEffects,
                now: now, calendar: calendar
            ).map { (badge, $0) }
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: Helpers

    /// The first calendar day on which an unbroken run of logged days reached `target`.
    /// Once reached it stays reached — later gaps never revoke it.
    static func dayStreakFirstReached(_ target: Int, days: Set<Date>, calendar: Calendar = .current) -> Date? {
        guard target > 0 else { return nil }
        var runLength = 0
        var previous: Date?
        for day in days.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                runLength += 1
            } else {
                runLength = 1
            }
            previous = day
            if runLength == target { return day }
        }
        return nil
    }

    /// End of the first 28-day window in which the earliest active daily treatment had
    /// ≥ 90% of expected doses logged. nil when there is no active daily treatment —
    /// the badge simply doesn't apply, it is never shown as "failed".
    static func adherenceWindowFirstMet(
        treatments: [Treatment],
        doses: [TreatmentDose],
        windowDays: Int = 28,
        threshold: Double = 0.9,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard let primary = treatments
            .filter({ $0.isActive && $0.treatmentClass.isDaily })
            .min(by: { $0.startDate < $1.startDate })
        else { return nil }

        let expectedPerDay = primary.treatmentClass.defaultDailyCount
        guard expectedPerDay > 0 else { return nil }
        let expected = Double(expectedPerDay * windowDays)

        let start = calendar.startOfDay(for: primary.startDate)
        guard let totalDays = calendar.dateComponents([.day], from: start, to: now).day,
              totalDays + 1 >= windowDays
        else { return nil }

        // Bucket this treatment's doses by day offset from start, then slide the window.
        var countsByOffset = [Int](repeating: 0, count: totalDays + 1)
        for dose in doses
        where dose.treatment?.persistentModelID == primary.persistentModelID && dose.loggedAt <= now {
            if let offset = calendar.dateComponents(
                [.day], from: start, to: calendar.startOfDay(for: dose.loggedAt)
            ).day, offset >= 0, offset <= totalDays {
                countsByOffset[offset] += 1
            }
        }
        var windowCount = countsByOffset.prefix(windowDays).reduce(0, +)
        var lastDayOffset = windowDays - 1
        while true {
            if Double(windowCount) / expected >= threshold {
                return calendar.date(byAdding: .day, value: lastDayOffset, to: start)
            }
            lastDayOffset += 1
            guard lastDayOffset <= totalDays else { return nil }
            windowCount += countsByOffset[lastDayOffset] - countsByOffset[lastDayOffset - windowDays]
        }
    }
}
