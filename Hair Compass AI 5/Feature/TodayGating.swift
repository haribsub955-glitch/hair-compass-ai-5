import Foundation

/// Today is free by design — it's the one surface a lapsed subscriber keeps. But `.treatments`
/// and `.photos` are hard-gated elsewhere (`CareView`'s `.proGated(.treatments)`,
/// `PhotosView`'s `.proGated(.photos)`), and a lapsed subscriber's treatments/photos are still
/// sitting in SwiftData — so Today must not spell out treatment names or photo-completion state
/// just because they're still on disk. The same read-path problem `WidgetSnapshotBuilder` solved
/// for the Home Screen widget (Service/WidgetBridge.swift), solved the same way here: force the
/// suppressed values back to whatever a genuine "nothing scheduled" day already looks like —
/// `CompassScore`'s existing `care = medsTotal > 0 ? … : nil` branch — rather than inventing a
/// new locked state that would plaster lock icons over a screen with no paywall to tap through.
enum TodayGating {
    /// What Today is entitled to build its routine ledger and Compass rings from.
    struct Visible {
        /// Today's due routine steps (treatment + slot) — empty for a tier that can't see
        /// `.treatments`, even when treatments are still stored, so no treatment name renders
        /// and the ROUTINE section disappears entirely (reading as a plan-less day) instead of
        /// showing a locked, empty header.
        let dailySlots: [(Treatment, String)]
        let medsDone: Int
        let medsTotal: Int
        let hasPhotoThisWeek: Bool
    }

    /// - Parameters:
    ///   - dailySlots: every routine step due today (treatment + slot), unfiltered.
    ///   - medsDone: how many of those steps are already logged, unfiltered.
    ///   - hasPhotoThisWeek: whether a progress photo exists in the current calendar week,
    ///     unfiltered.
    static func visible(
        dailySlots: [(Treatment, String)],
        medsDone: Int,
        hasPhotoThisWeek: Bool,
        entitlements: Entitlements
    ) -> Visible {
        let canSeeTreatments = entitlements.canAccess(.treatments)
        let canSeePhotos = entitlements.canAccess(.photos)
        return Visible(
            dailySlots: canSeeTreatments ? dailySlots : [],
            medsDone: canSeeTreatments ? medsDone : 0,
            // Forcing 0 (rather than filtering `dailySlots` and reading `.count`) is what makes
            // CompassScore treat Care the same way it treats a plan-less day — see the doc
            // comment above.
            medsTotal: canSeeTreatments ? dailySlots.count : 0,
            hasPhotoThisWeek: canSeePhotos && hasPhotoThisWeek
        )
    }
}
