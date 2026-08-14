import Foundation

/// The free tier's defining restriction: log forever, see only today.
///
/// This lives as a function over already-fetched entries rather than as a `@Query` predicate
/// because `@Query` predicates are static — a view that wrote its own fetch would silently
/// bypass a predicate-based wall. Every surface that shows history routes through here.
enum HistoryAccess {

    static func visible(
        _ entries: [DailyEntry],
        entitlements: Entitlements,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DailyEntry] {
        guard !entitlements.canAccess(.history) else { return entries }
        return entries.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// How much of their own record is sitting behind the wall. This number is the conversion
    /// mechanic — it grows every day someone stays free, which is why the free tier caps
    /// nothing: a capped check-in would stop this counter climbing.
    static func lockedCount(
        _ entries: [DailyEntry],
        entitlements: Entitlements,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard !entitlements.canAccess(.history) else { return 0 }
        return entries.filter { !calendar.isDate($0.date, inSameDayAs: now) }.count
    }
}
