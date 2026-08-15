import Foundation

/// The free tier's defining restriction: log forever, see only today.
///
/// A function over already-fetched entries rather than a `@Query` predicate, so the rule stays
/// in one place, reads the same at every call site, and is unit-testable without a
/// `ModelContext`. It is a CONVENTION, not an access control: a view that fetches `DailyEntry`
/// directly still bypasses it, and no client-side check could prevent that anyway. Route every
/// history surface through here.
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
