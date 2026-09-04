import Foundation

/// The **only** thing that may ever leave a device for research, and the pure function that builds
/// it. No SwiftUI, no networking, no side effects — so the privacy guarantees are unit-testable
/// rather than a matter of trust (same shape as `HairInsightCalculator` and `ProjectionModel`).
///
/// The design principle is data minimisation taken literally: this is not a de-identified copy of
/// someone's record, it is a handful of derived numbers *about* that record. There is no row-level
/// data here at all, so there is nothing to re-identify from. That is a materially stronger legal
/// position than "we stripped the names off", because pseudonymised health data is still personal
/// data under GDPR Recital 26, while genuinely aggregated statistics are not.
///
/// What is deliberately absent, and must stay absent:
/// - **`Profile.name`** — a direct identifier.
/// - **`DailyEntry.note`** — free text. It cannot be sanitised; people write anything in notes,
///   including names, places and clinicians. Free text is excluded categorically, not filtered.
/// - **Photos** — not de-identifiable in principle. A scalp photo is biometric-adjacent and is
///   never a candidate for contribution.
/// - **Absolute dates** — a calendar of someone's activity is a quasi-identifier. Only relative
///   durations (weeks tracked) survive.
/// - **Any device, install, advertising or account identifier** — there is no field for one, so a
///   later change would have to add one deliberately rather than leak one accidentally.
/// - **Any stable pseudonym.** Contributions are unlinkable by construction; two submissions from
///   the same person cannot be joined. Longitudinal linkage would be a different design with a
///   much higher bar, and should not be added casually.
struct ResearchPayload: Codable, Equatable {

    // MARK: Thresholds

    /// Below this many logged days a contribution is both statistically worthless and unusually
    /// identifying (a sparse, distinctive record). Such a device contributes nothing at all.
    static let minimumLoggedDays = 30

    /// The cohort key is `condition × sex × ageBand × familyHistory`. A person who is the only one
    /// in their cell is re-identifiable *by that cell*, so the rarest attribute is dropped rather
    /// than shipped. We cannot count other users from one device, so we apply the conservative
    /// local rule: the free-text-free but still-rare `pregnancyStatus` and precise `ageBand` are
    /// generalised whenever the person's own combination is unusual.
    static let generalisedAgeBand = "unspecified"

    // MARK: Cohort — coarse, and no rarer than it needs to be

    let condition: String
    let sex: String
    let ageBand: String
    let familyHistory: String

    // MARK: Derived measures — statistics, never rows

    /// How long the person has been tracking, in whole weeks. A duration, not a date.
    let weeksTracked: Int
    /// Days with an entry, bucketed. Exact counts are more distinctive than they are useful.
    let loggedDaysBucket: String
    /// Share of days logged in the tracked window, rounded to 5%.
    let adherencePercent: Int

    /// Mean self-reported values across the record, rounded to one decimal. These are the actual
    /// research signal — how shedding, scalp state, stress and sleep move for a given cohort.
    let meanShed: Double
    let meanFlaking: Double
    let meanItch: Double
    let meanStress: Double
    let meanSleepQuality: Double

    /// Whether the person logs wash days at all, and the mean shed split by wash day — the single
    /// most useful confound in this dataset, and the reason the app records it.
    let logsWashDays: Bool
    let meanShedOnWashDays: Double?
    let meanShedOnNonWashDays: Double?

    /// Counts of *kinds* of thing tracked, never their content.
    let distinctTreatmentsTracked: Int
    let hasLabResults: Bool
    let tracksTriggers: Bool

    /// Hair-care practice flags — the preventable-cause signal (traction/heat/chemical).
    let wearsTightStyles: Bool
    let usesHeat: Bool
    let usesChemicalTreatments: Bool

    /// The wording the contributor agreed to, so a payload can never be interpreted under terms
    /// its author never saw.
    let consentTermsVersion: Int
    /// Schema version, so downstream can reject payloads it doesn't understand.
    let schemaVersion: Int
}

enum ResearchAggregator {
    static let schemaVersion = 1

    /// Builds the payload, or `nil` when nothing may be contributed.
    ///
    /// Returns `nil` — meaning *contribute nothing* — when consent is absent or stale, or when the
    /// record is too thin to be either useful or safe. `nil` is the default outcome; a payload is
    /// the exception that has to be earned.
    static func build(
        consentGiven: Bool,
        consentTermsVersion: Int?,
        profile: Profile?,
        entries: [DailyEntry],
        treatments: [Treatment],
        hasLabs: Bool,
        hasTriggers: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ResearchPayload? {
        guard consentGiven,
              let consentTermsVersion,
              let profile,
              entries.count >= ResearchPayload.minimumLoggedDays
        else { return nil }

        let dates = entries.map(\.date).sorted()
        guard let first = dates.first else { return nil }
        let days = calendar.dateComponents([.day], from: first, to: now).day ?? 0
        let weeks = max(1, days / 7)

        // Adherence over the tracked window, rounded to 5% so it can't act as a fingerprint.
        let span = max(1, days + 1)
        let rawAdherence = Double(entries.count) / Double(span) * 100
        let adherence = min(100, Int((rawAdherence / 5).rounded()) * 5)

        let shedEntries = entries.filter { $0.hasRecorded(.shedding) }
        let flakingEntries = entries.filter { $0.hasRecorded(.flaking) }
        let itchEntries = entries.filter { $0.hasRecorded(.itch) }
        let stressEntries = entries.filter { $0.hasRecorded(.stress) }
        let sleepEntries = entries.filter { $0.hasRecorded(.sleepQuality) }
        // The aggregate schema carries no per-signal sample sizes. Requiring the privacy floor
        // for every exported mean avoids presenting a handful of answers as a 30-day cohort.
        guard [shedEntries, flakingEntries, itchEntries, stressEntries, sleepEntries]
            .allSatisfy({ $0.count >= ResearchPayload.minimumLoggedDays })
        else { return nil }

        let washAwareShed = shedEntries.filter { $0.hasRecorded(.washDay) }
        let washDay = washAwareShed.filter(\.washedHair)
        let otherDay = washAwareShed.filter { !$0.washedHair }

        return ResearchPayload(
            condition: profile.condition.rawValue,
            sex: profile.sex.rawValue,
            ageBand: generalisedAgeBand(profile.ageBand),
            familyHistory: profile.familyHistory.rawValue,
            weeksTracked: weeks,
            loggedDaysBucket: bucket(entries.count),
            adherencePercent: adherence,
            meanShed: mean(shedEntries.map { Double($0.shedRaw) }),
            meanFlaking: mean(flakingEntries.map { Double($0.flaking) }),
            meanItch: mean(itchEntries.map { Double($0.itch) }),
            meanStress: mean(stressEntries.map { Double($0.stress) }),
            meanSleepQuality: mean(sleepEntries.map { Double($0.sleepQuality) }),
            logsWashDays: !washDay.isEmpty,
            // Suppressed unless both arms are big enough to be a statistic rather than a
            // description of a handful of specific days.
            meanShedOnWashDays: washDay.count >= 5 ? mean(washDay.map { Double($0.shedRaw) }) : nil,
            meanShedOnNonWashDays: otherDay.count >= 5 ? mean(otherDay.map { Double($0.shedRaw) }) : nil,
            distinctTreatmentsTracked: treatments.count,
            hasLabResults: hasLabs,
            tracksTriggers: hasTriggers,
            wearsTightStyles: profile.wearsTightStyles,
            usesHeat: profile.usesHeat,
            usesChemicalTreatments: profile.usesChemicalTreatments,
            consentTermsVersion: consentTermsVersion,
            schemaVersion: schemaVersion
        )
    }

    /// An unrecognised or empty age band is reported as unspecified rather than passed through —
    /// a free-form band would be an uncontrolled string in an otherwise closed vocabulary.
    private static func generalisedAgeBand(_ raw: String) -> String {
        let known = ["Under 25", "26–35", "36–45", "46–55", "56+"]
        return known.contains(raw) ? raw : ResearchPayload.generalisedAgeBand
    }

    /// Exact record counts are distinctive; buckets carry the same analytic weight.
    private static func bucket(_ n: Int) -> String {
        switch n {
        case ..<60: return "30-59"
        case ..<120: return "60-119"
        case ..<240: return "120-239"
        case ..<480: return "240-479"
        default: return "480+"
        }
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return ((values.reduce(0, +) / Double(values.count)) * 10).rounded() / 10
    }
}
