import Foundation
import SwiftData

/// The reward moment for saving a daily check-in — a pure diff of the gamification engine
/// (`Gamification.swift`) before and after the save. No new constants live here: XP, the
/// level ladder and the badge rules are all the existing engine, replayed over two snapshots.
///
/// Effort-only, like everything gamified in this app: the diff can only ever grow from the
/// *act* of logging. A hard hair day earns exactly the same reward as a great one.
struct CheckInReward {
    let xpGained: Int
    let totalXP: Int
    let level: GamificationLevel
    let progressToNext: (fraction: Double, remaining: Int, next: GamificationLevel?)
    let leveledUp: Bool
    let streak: Int
    let newBadges: [Achievement]

    /// The no-celebrate-on-pure-edit rule: editing an already-logged day changes no XP and
    /// earns no badge, so the moment stays quiet — the same day is never celebrated twice.
    /// Only a save that actually earned something (a new logged day, a fresh badge) shows.
    var isWorthCelebrating: Bool { xpGained > 0 || !newBadges.isEmpty }

    /// Everything the XP and badge engines read, captured at one instant. Trivially built
    /// from `@Query` arrays or from `FetchDescriptor` fetches (see `init(context:)`).
    ///
    /// The model classes are reference types, but a before-capture stays valid across the
    /// check-in upsert because the engines only fold fields the save never mutates (entry
    /// dates, dose/photo/lab/trigger timestamps) — and a newly inserted entry simply isn't
    /// in the before arrays.
    struct Snapshot {
        var entries: [DailyEntry] = []
        var treatments: [Treatment] = []
        var doses: [TreatmentDose] = []
        var photos: [PhotoRecord] = []
        var labs: [LabResult] = []
        var triggers: [TriggerEvent] = []

        var sideEffects: [SideEffectLog] { treatments.flatMap(\.sideEffects) }

        func xp(now: Date, calendar: Calendar) -> Int {
            XP.total(entries: entries, doses: doses, photos: photos,
                     labs: labs, triggers: triggers, now: now, calendar: calendar)
        }

        func earnedBadges(now: Date, calendar: Calendar) -> [Achievement] {
            Achievement.earnedList(
                entries: entries, treatments: treatments, doses: doses,
                photos: photos, labs: labs, sideEffects: sideEffects,
                now: now, calendar: calendar
            ).map(\.achievement)
        }
    }

    /// Pure and replayable: two snapshots in, one reward out. `xpGained` is clamped ≥ 0
    /// (the engine is monotonic over a save, but the reward must never read as a penalty).
    static func build(
        before: Snapshot,
        after: Snapshot,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CheckInReward {
        let xpBefore = before.xp(now: now, calendar: calendar)
        let xpAfter = after.xp(now: now, calendar: calendar)
        let levelBefore = GamificationLevel.level(for: xpBefore)
        let levelAfter = GamificationLevel.level(for: xpAfter)
        let earnedBefore = Set(before.earnedBadges(now: now, calendar: calendar))
        let newBadges = after.earnedBadges(now: now, calendar: calendar)
            .filter { !earnedBefore.contains($0) }

        return CheckInReward(
            xpGained: max(0, xpAfter - xpBefore),
            totalXP: xpAfter,
            level: levelAfter,
            progressToNext: GamificationLevel.progressToNext(xp: xpAfter),
            leveledUp: levelAfter.index > levelBefore.index,
            // Shielded, not raw — so the celebration's streak matches what the Today hero shows.
            // XP itself never reads this; only the displayed number does (see shieldedStreak doc).
            streak: HairAnalytics.shieldedStreak(
                entryDates: after.entries.map(\.date), now: now, calendar: calendar
            ).streak,
            newBadges: newBadges
        )
    }
}

extension CheckInReward.Snapshot {
    /// Captures the full record from a live context. Predicate-free FetchDescriptors fetch
    /// everything, which is fine at this app's scale (a few hundred small rows at most) —
    /// and pending, unsaved inserts are included, so an after-capture sees the new entry.
    init(context: ModelContext) {
        self.init(
            entries: (try? context.fetch(FetchDescriptor<DailyEntry>())) ?? [],
            treatments: (try? context.fetch(FetchDescriptor<Treatment>())) ?? [],
            doses: (try? context.fetch(FetchDescriptor<TreatmentDose>())) ?? [],
            photos: (try? context.fetch(FetchDescriptor<PhotoRecord>())) ?? [],
            labs: (try? context.fetch(FetchDescriptor<LabResult>())) ?? [],
            triggers: (try? context.fetch(FetchDescriptor<TriggerEvent>())) ?? []
        )
    }
}
