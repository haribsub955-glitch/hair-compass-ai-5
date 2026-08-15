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
    /// What Today is entitled to build its routine ledger, Compass rings, AND its prose (the
    /// daily-insight paragraph, the status caption) from. Every other reader of treatments/doses
    /// on Today — not just the ring/ledger — must go through this, or the same leak reopens
    /// through a different sentence.
    struct Visible {
        /// Today's due routine steps (treatment + slot) — empty for a tier that can't see
        /// `.treatments`, even when treatments are still stored, so no treatment name renders
        /// and the ROUTINE section disappears entirely (reading as a plan-less day) instead of
        /// showing a locked, empty header.
        let dailySlots: [(Treatment, String)]
        let medsDone: Int
        let medsTotal: Int
        let hasPhotoThisWeek: Bool
        /// Entitlement-filtered treatments/doses — feed THIS into anything that turns treatments
        /// into prose (`InsightContext.build`, the status caption's "last entry" timestamp), not
        /// the raw SwiftData query. `InsightEngine`'s deterministic fallback (`RuleBasedInsight
        /// .paragraph`) names a treatment unconditionally for any active one under 24 weeks old —
        /// that guarantee makes it a leak on its own, independent of the rings/ledger fix above.
        let treatments: [Treatment]
        let doses: [TreatmentDose]
    }

    /// - Parameters:
    ///   - dailySlots: every routine step due today (treatment + slot), unfiltered.
    ///   - medsDone: how many of those steps are already logged, unfiltered.
    ///   - hasPhotoThisWeek: whether a progress photo exists in the current calendar week,
    ///     unfiltered.
    ///   - treatments: every treatment on record, unfiltered — feeds `InsightContext.build`.
    ///   - doses: every dose on record, unfiltered — feeds `InsightContext.build` and the status
    ///     caption's freshness readout.
    static func visible(
        dailySlots: [(Treatment, String)],
        medsDone: Int,
        hasPhotoThisWeek: Bool,
        treatments: [Treatment],
        doses: [TreatmentDose],
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
            hasPhotoThisWeek: canSeePhotos && hasPhotoThisWeek,
            treatments: canSeeTreatments ? treatments : [],
            doses: canSeeTreatments ? doses : []
        )
    }
}

extension TodayGating {
    /// Everything the daily-insight paragraph is allowed to be built from, for one tier.
    ///
    /// Takes the RAW queries and does every entitlement decision itself — deliberately, because
    /// the bug this replaces was a call site that routed two of its six inputs through the wall
    /// and left the other four raw. There is no per-argument choice left to get wrong: pass what
    /// SwiftData gave you and the tier, and the mapping is the same at every call site.
    ///
    /// The mapping, and why each input maps where it does:
    /// - `entries` → `.history`. The free tier may see TODAY's own values and the streak count
    ///   (docs/superpowers/specs/2026-08-14-monetization-design.md §4), so today's entry still
    ///   backs `latestShed`/`latestScalpBand`. It may NOT see history or averages — so only
    ///   today's entry is passed, and `describesTrend` drops the direction clause rather than
    ///   letting `HairAnalytics.direction`'s data-starved `0` render as "and steady".
    ///   `entryCount` and `streak` are then restored from the FULL set: both are counts the free
    ///   tier is already shown (the hero's streak, `LockedHistoryCard`'s locked-day count), and a
    ///   count of 1 would both contradict the hero and mislabel a hundred-day free user as
    ///   someone who has "logged for a few days".
    /// - `labs` → `.labs`. `RuleBasedInsight.labNote` otherwise reads a ferritin value straight
    ///   out of the locked lab panel, and `facts()` hands the whole panel to the on-device model.
    /// - `snapshots` → `.bodySignals`. HealthKit sleep/HRV/body-mass; the rapid-weight-loss
    ///   sentence is derived entirely from them.
    /// - `progressCheckIns`, `sideEffects` → `.reports`. Neither has a free surface (Plan's
    ///   check-in section and severe-side-effect banner are inside `.proGated(.treatments)`, the
    ///   monthly card is inside `.trends`), but what actually leaks is `ClinicianReviewFlags` —
    ///   a clinician-facing synthesis, which is precisely what `.reports` sells ("A summary you
    ///   can read or hand to a clinician"). So the gate that governs the OUTPUT governs the input.
    /// - `treatments`, `doses` → `.treatments`, as `visible(_:)` above already established.
    /// - `triggers` → deliberately unfiltered. A dated life event is the one record the free tier
    ///   can still create (LogSheet's "Anything notable happen recently?"), and the free-write
    ///   decision on `TriggerEvent` is the owner's, recorded as out of scope. Revisit here if
    ///   that changes.
    /// - `profile` → unfiltered; the baseline is editable on every tier.
    @MainActor
    static func insightContext(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        snapshots: [HealthSnapshot],
        triggers: [TriggerEvent],
        labs: [LabResult],
        profile: Profile?,
        progressCheckIns: [ProgressCheckIn],
        sideEffects: [SideEffectLog],
        entitlements: Entitlements,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> InsightContext {
        let canSeeHistory = entitlements.canAccess(.history)
        let canSeeTreatments = entitlements.canAccess(.treatments)
        let canSeeReports = entitlements.canAccess(.reports)
        var context = InsightContext.build(
            entries: HistoryAccess.visible(entries, entitlements: entitlements, now: now, calendar: calendar),
            treatments: canSeeTreatments ? treatments : [],
            doses: canSeeTreatments ? doses : [],
            snapshots: entitlements.canAccess(.bodySignals) ? snapshots : [],
            triggers: triggers,
            labs: entitlements.canAccess(.labs) ? labs : [],
            profile: profile,
            progressCheckIns: canSeeReports ? progressCheckIns : [],
            sideEffects: canSeeReports ? sideEffects : [],
            describesTrend: canSeeHistory
        )
        // The two numbers the free tier is already shown, restored from the unfiltered record —
        // see the `entries` note above. Both are strictly less than the locked-day count on
        // `LockedHistoryCard` directly above this paragraph.
        context.entryCount = entries.count
        context.streak = HairAnalytics.loggingStreak(entryDates: entries.map(\.date))
        return context
    }
}
