import Foundation

/// The daily effort score behind the Compass Rings. Built ONLY from controllable inputs —
/// check-in logged, doses done, weekly photo. Shedding/scalp severity never touch it
/// (rewarding outcomes users can't control backfires; see docs/research/2026-07-11).
struct CompassScore: Equatable {
    /// 1 when today's check-in exists.
    let log: Double
    /// Fraction of today's scheduled doses logged; nil when nothing is scheduled today.
    let care: Double?
    /// 1 when a progress photo exists in the current calendar week.
    let lens: Double

    init(hasLoggedToday: Bool, medsDone: Int, medsTotal: Int, hasPhotoThisWeek: Bool) {
        log = hasLoggedToday ? 1 : 0
        care = medsTotal > 0 ? Double(min(medsDone, medsTotal)) / Double(medsTotal) : nil
        lens = hasPhotoThisWeek ? 1 : 0
    }

    /// 0–100. Weights Log 50 / Care 30 / Lens 20; an unavailable ring's weight is
    /// redistributed proportionally across the rings that exist.
    var score: Int {
        var pairs: [(value: Double, weight: Double)] = [(log, 50), (lens, 20)]
        if let care { pairs.append((care, 30)) }
        let totalWeight = pairs.reduce(0) { $0 + $1.weight }
        let weighted = pairs.reduce(0) { $0 + $1.value * $1.weight }
        return Int((weighted / totalWeight * 100).rounded())
    }

    var allClosed: Bool { log >= 1 && lens >= 1 && (care ?? 1) >= 1 }
}
