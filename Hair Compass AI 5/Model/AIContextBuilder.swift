import Foundation
import SwiftData

/// The canonical, versioned, machine-readable context every AI feature consumes — today the
/// cloud deep analysis, next the chat feature. One JSON shape over all the SwiftData models,
/// so a model never sees ad-hoc prose where structure will do.
///
/// Rules of the shape:
/// - Versioned: `schemaVersion` bumps whenever a field changes meaning, so downstream prompts
///   can say exactly what they were built against.
/// - Pure: `build` takes `now`/`calendar` explicitly — no `Date.now` inside, so tests are
///   deterministic and two builds over the same data are byte-identical.
/// - No direct identifiers: the profile section deliberately has NO name field. Photo data is
///   metadata only (count/regions/dates) — never image bytes.
/// - All math is reused from the deterministic core (`HairAnalytics`, `ChartMath`,
///   `BodySignalsMath`); nothing is recomputed here with different formulas.
/// - Encoding uses `.sortedKeys`, so output is stable for tests and prompt caching.
struct AIContext: Codable, Equatable, Sendable {

    /// Bump on any change to field names or semantics. v1: the initial shape. v2: adds
    /// `progressCheckIns` (self-reported regrowth/density/shedding/hairline/overall + scalp-pain).
    static let currentSchemaVersion = 3

    var schemaVersion: Int = AIContext.currentSchemaVersion
    /// ISO8601 (UTC, whole seconds) timestamp of the `now` the context was built against.
    var generatedAt: String
    var profile: ProfileFacts
    var dailySeries: DailySeries
    var treatments: [TreatmentFacts]
    var labs: [LabFacts]
    var triggers: [TriggerFacts]
    var progressCheckIns: [ProgressCheckInFacts]
    var bodySignals: BodySignals
    var meta: Meta

    /// Days of daily-log history shipped to the model, and the cap on the series length.
    static let dailyWindowDays = 120
    /// Hard prompt budget. The builder's caps and string normalization keep compact JSON below
    /// this value even for a deliberately adversarial local record.
    static let maximumEncodedBytes = 24_000
    static let maximumTreatments = 12
    static let maximumLabs = 12
    static let maximumTriggers = 12
    static let maximumProgressCheckIns = 6
    static let maximumSideEffectsPerTreatment = 6

    // MARK: - Sections

    /// Baseline context. Deliberately excludes the person's name — no direct identifiers
    /// ever enter an AI payload.
    struct ProfileFacts: Codable, Equatable, Sendable {
        var condition: String        // HairCondition title, e.g. "Androgenetic"
        var conditionCode: String    // short label, e.g. "AGA"
        var sex: String?             // BiologicalSex rawValue; nil when no profile
        var ageBand: String?         // nil when not recorded
        var familyHistory: String?   // FamilyHistory rawValue; nil when no profile
        var baselineStage: String?   // e.g. "Norwood 3"; nil when not recorded
        var tractionRisk: Bool       // tight styles / heat / chemical treatment at baseline
    }

    /// The last `dailyWindowDays` of daily logs, oldest first, plus precomputed trend stats
    /// so the model never has to do arithmetic.
    struct DailySeries: Codable, Equatable, Sendable {
        struct Day: Codable, Equatable, Sendable {
            var date: String         // "yyyy-MM-dd"
            var shed: Int?           // 0–3 (ShedLevel)
            var scalpTotal: Int?     // 0–16 self-reported score adapted from Zhang 2023
            var sleepQuality: Int?   // 1–5 subjective
            var stress: Int?         // 1–5
            var oiliness: Int?       // 0–3
        }
        var days: [Day]
        /// Endpoint of the 7-day rolling mean of shed (ChartMath.rollingMean); nil with no data.
        var shed7d: Double?
        /// HairAnalytics.direction over the windowed shed series (positive = rising);
        /// nil when fewer than 3 days.
        var shedDirection: Double?
        var scalp7d: Double?
        var scalpDirection: Double?
    }

    struct TreatmentFacts: Codable, Equatable, Sendable {
        struct SideEffect: Codable, Equatable, Sendable {
            var name: String         // SideEffectType title
            var severity: Int        // 1 mild · 2 moderate · 3 severe
        }
        var name: String
        var treatmentClass: String   // TreatmentClass rawValue, encoded as "class"
        var dose: String?
        var slots: [String]          // e.g. ["08:00", "21:00"]; empty = periodic
        var isActive: Bool
        var startDate: String        // "yyyy-MM-dd"
        var weeksElapsed: Int
        var outcomeReady: Bool       // past the 24-week judging point
        var adherencePercent: Int?   // trailing-window %; nil for periodic classes
        var refillBy: String?        // "yyyy-MM-dd" when supply tracking is on
        var recentSideEffects: [SideEffect]   // last 30 days only

        enum CodingKeys: String, CodingKey {
            case name, dose, slots, isActive, startDate, weeksElapsed, outcomeReady
            case adherencePercent, refillBy, recentSideEffects
            case treatmentClass = "class"
        }
    }

    struct LabFacts: Codable, Equatable, Sendable {
        var test: String             // LabTest rawValue
        var title: String
        var value: Double
        var unit: String
        var flag: String             // "low" | "normal" | "high"
        var collectedAt: String      // "yyyy-MM-dd"
        var referenceLow: Double
        var referenceHigh: Double
    }

    struct TriggerFacts: Codable, Equatable, Sendable {
        var type: String             // TriggerType rawValue
        var title: String
        var date: String             // "yyyy-MM-dd"
        var weeksAgo: Int
    }

    /// A self-reported periodic answer to the between-visit questions a dermatologist asks.
    /// Context only, never a measurement or diagnosis — `scalpPain` is a safety flag the model
    /// may surface as "worth mentioning to your clinician," never as a claim a treatment worked.
    struct ProgressCheckInFacts: Codable, Equatable, Sendable {
        var date: String             // "yyyy-MM-dd"
        var regrowth: String         // RegrowthLevel title, e.g. "Clearly visible"
        var density: String          // ProgressTrend.clinicianPhrase(for: .density)
        var shedding: String         // ProgressTrend.clinicianPhrase(for: .shedding)
        var hairline: String         // ProgressTrend.clinicianPhrase(for: .hairline)
        var overall: String          // ProgressTrend.clinicianPhrase(for: .overall)
        var scalpPain: Bool          // safety flag, not a diagnosis
        var note: String
    }

    /// Latest reading + 30d-vs-previous-30d delta per HealthKit signal (BodySignalsMath).
    /// A signal with no reading in the window is simply absent — never a fake zero.
    struct BodySignals: Codable, Equatable, Sendable {
        struct Signal: Codable, Equatable, Sendable {
            var id: String           // BodySignal rawValue: sleep/hrv/restingHR/weight/protein
            var latest: Double
            var delta30d: Double?    // current 30d mean − previous 30d mean
        }
        var signals: [Signal]
        /// Set only when the rapid-weight-loss rule (>5% in 90 days) fires — a TE trigger watch.
        var rapidWeightLossPercent: Double?
    }

    struct Meta: Codable, Equatable, Sendable {
        struct PhotoSummary: Codable, Equatable, Sendable {
            var count: Int
            var regions: [String]    // distinct PhotoRegion rawValues, sorted
            var firstDate: String?   // "yyyy-MM-dd"
            var lastDate: String?
        }
        var entryCount: Int
        var streak: Int
        var photos: PhotoSummary     // metadata only — image data never enters the context
        var longTerm: LongTermAggregates
        /// Counts excluded by the explicit prompt budget. These keep absence distinguishable
        /// from truncation without sending another unbounded list to the model.
        var omitted: OmittedCounts

        struct OmittedCounts: Codable, Equatable, Sendable {
            var dailyEntries: Int
            var treatments: Int
            var labs: Int
            var triggers: Int
            var progressCheckIns: Int
            var sideEffects: Int
        }

        struct LongTermAggregates: Codable, Equatable, Sendable {
            var firstEntryDate: String?
            var lastEntryDate: String?
            var averageShed: Double?
            var averageScalpTotal: Double?
        }
    }

    // MARK: - Build (SwiftData models → pure context)

    /// Snapshot the current SwiftData state into the versioned context. Same input shape as
    /// `InsightContext.build`, plus labs, side effects, and photo metadata. `now`/`calendar`
    /// are explicit so the result is fully deterministic.
    @MainActor
    static func build(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        snapshots: [HealthSnapshot],
        triggers: [TriggerEvent],
        labs: [LabResult],
        sideEffects: [SideEffectLog],
        photos: [PhotoRecord],
        profile: Profile?,
        progressCheckIns: [ProgressCheckIn] = [],
        now: Date,
        calendar: Calendar = .current
    ) -> AIContext {

        // Profile — condition/stage/risk context, never the name.
        let condition = profile?.condition ?? .unsure
        let profileFacts = ProfileFacts(
            condition: condition.title,
            conditionCode: condition.shortLabel,
            sex: profile?.sex.rawValue,
            ageBand: nonEmpty(profile?.ageBand).map { bounded($0) },
            familyHistory: profile?.familyHistory.rawValue,
            baselineStage: nonEmpty(profile?.baselineStage).map { bounded($0) },
            tractionRisk: profile?.hasTractionRisk ?? false
        )

        // Daily series — ascending, within the horizon, hard-capped at dailyWindowDays points.
        let horizonStart = calendar.date(
            byAdding: .day, value: -(dailyWindowDays - 1), to: calendar.startOfDay(for: now)) ?? now
        let windowed = Array(
            entries.sorted { $0.date < $1.date }
                .filter { $0.date >= horizonStart }
                .suffix(dailyWindowDays)
        )
        let shedPoints = windowed.filter { $0.hasRecorded(.shedding) }
            .map { (day: $0.date, value: Double($0.shed.rawValue)) }
        let scalpPoints = windowed.filter(\.hasCompleteScalpRecording)
            .map { (day: $0.date, value: Double($0.scalpTotal)) }
        let shedValues = shedPoints.map(\.value)
        let scalpValues = scalpPoints.map(\.value)
        let dailySeries = DailySeries(
            days: windowed.map { e in
                DailySeries.Day(
                    date: dayString(e.date, calendar: calendar),
                    shed: e.hasRecorded(.shedding) ? e.shed.rawValue : nil,
                    scalpTotal: e.hasCompleteScalpRecording ? e.scalpTotal : nil,
                    sleepQuality: e.hasRecorded(.sleepQuality) ? e.sleepQuality : nil,
                    stress: e.hasRecorded(.stress) ? e.stress : nil,
                    oiliness: e.hasRecorded(.oiliness) ? e.oiliness : nil
                )
            },
            shed7d: ChartMath.trailingCalendarMean(shedPoints, windowDays: 7, calendar: calendar).last.map { round1($0.value) },
            shedDirection: shedValues.count >= 5 ? round2(HairAnalytics.direction(shedValues)) : nil,
            scalp7d: ChartMath.trailingCalendarMean(scalpPoints, windowDays: 7, calendar: calendar).last.map { round1($0.value) },
            scalpDirection: scalpValues.count >= 5 ? round2(HairAnalytics.direction(scalpValues)) : nil
        )

        // Treatments — all of them (isActive tells the model which are current), with the
        // adherence and 24-week gate math from HairAnalytics and 30 days of tolerability.
        let sideEffectCutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let includedTreatments = Array(treatments.sorted { $0.startDate < $1.startDate }.suffix(maximumTreatments))
        var omittedSideEffectCount = 0
        let treatmentFacts = includedTreatments
            .map { t -> TreatmentFacts in
                let weeks = HairAnalytics.weeksElapsed(since: t.startDate, now: now, calendar: calendar)
                let doseDates = doses
                    .filter { $0.treatment?.persistentModelID == t.persistentModelID }
                    .map(\.loggedAt)
                let adherence = HairAnalytics.adherence(
                    doseDates: doseDates, expectedPerDay: t.slots.count, now: now, calendar: calendar)
                let allRecent = sideEffects
                    .filter {
                        $0.treatment?.persistentModelID == t.persistentModelID
                            && $0.date >= sideEffectCutoff && $0.date <= now
                    }
                    .sorted { $0.date < $1.date }
                omittedSideEffectCount += max(0, allRecent.count - maximumSideEffectsPerTreatment)
                let recent = Array(allRecent.suffix(maximumSideEffectsPerTreatment))
                    .map { TreatmentFacts.SideEffect(name: bounded($0.type.title), severity: $0.severity) }
                return TreatmentFacts(
                    name: bounded(t.name.isEmpty ? t.treatmentClass.title : t.name, limit: 80),
                    treatmentClass: t.treatmentClass.rawValue,
                    dose: nonEmpty(t.dose).map { bounded($0, limit: 80) },
                    slots: Array(t.slots.prefix(8)).map { bounded($0, limit: 12) },
                    isActive: t.isActive,
                    startDate: dayString(t.startDate, calendar: calendar),
                    weeksElapsed: weeks,
                    outcomeReady: HairAnalytics.outcomeReady(weeksElapsed: weeks),
                    adherencePercent: adherence.map { Int(($0 * 100).rounded()) },
                    refillBy: t.refillBy.map { dayString($0, calendar: calendar) },
                    recentSideEffects: recent
                )
            }

        // Labs — value + reference range + the HairAnalytics flag, date-only.
        let includedLabs = Array(labs.sorted { $0.collectedAt < $1.collectedAt }.suffix(maximumLabs))
        let labFacts = includedLabs
            .map { lab -> LabFacts in
                let range = lab.test.referenceRange
                return LabFacts(
                    test: lab.test.rawValue,
                    title: lab.test.title,
                    value: round1(lab.value),
                    unit: lab.test.unit,
                    flag: flagCode(lab.flag),
                    collectedAt: dayString(lab.collectedAt, calendar: calendar),
                    referenceLow: range.lowerBound,
                    referenceHigh: range.upperBound
                )
            }

        // Triggers — dated TE context with the weeks-since math the lag rules key on.
        let includedTriggers = Array(triggers.sorted { $0.date < $1.date }.suffix(maximumTriggers))
        let triggerFacts = includedTriggers
            .map { t in
                TriggerFacts(
                    type: t.type.rawValue,
                    title: t.type.title,
                    date: dayString(t.date, calendar: calendar),
                    weeksAgo: t.weeksElapsed(now: now, calendar: calendar)
                )
            }

        // Progress check-ins — self-reported answers to the between-visit questions a
        // dermatologist asks, most recent ~6, oldest first (same windowing convention as the
        // daily series). Context only: phrases, never a diagnosis or a "worked" claim.
        let progressCheckInFacts = Array(
            progressCheckIns.sorted { $0.date < $1.date }.suffix(maximumProgressCheckIns)
        ).map { c in
            ProgressCheckInFacts(
                date: dayString(c.date, calendar: calendar),
                regrowth: c.regrowth.title,
                density: c.density.clinicianPhrase(for: .density),
                shedding: c.shedding.clinicianPhrase(for: .shedding),
                hairline: c.hairline.clinicianPhrase(for: .hairline),
                overall: c.overall.clinicianPhrase(for: .overall),
                scalpPain: c.scalpPain,
                note: bounded(c.note, limit: 240)
            )
        }

        // Body signals — latest + 30d delta per signal via BodySignalsMath; absent = untracked.
        var signalReadings: [BodySignals.Signal] = []
        for signal in BodySignal.allCases {
            let samples = snapshots.map { (date: $0.date, value: $0[keyPath: signal.keyPath]) }
            let series = BodySignalsMath.windowedSeries(
                samples, windowDays: dailyWindowDays, now: now, calendar: calendar)
            guard let latest = series.last?.value else { continue }
            let delta = BodySignalsMath.delta(samples, windowDays: 30, now: now, calendar: calendar)
            signalReadings.append(BodySignals.Signal(
                id: signal.rawValue, latest: round1(latest), delta30d: delta.map(round1)))
        }
        let massSamples = snapshots.compactMap { s in
            s.bodyMassKg.map { (date: s.date, massKg: $0) }
        }
        let bodySignals = BodySignals(
            signals: signalReadings,
            rapidWeightLossPercent: HairAnalytics.rapidWeightLossPercent(
                samples: massSamples, now: now, calendar: calendar).map(round1)
        )

        // Meta — logging volume plus photo METADATA (regions and dates, never pixels).
        let photoDates = photos.map(\.createdAt)
        let allShedValues = entries.filter { $0.hasRecorded(.shedding) }.map { Double($0.shed.rawValue) }
        let allScalpValues = entries.filter(\.hasCompleteScalpRecording).map { Double($0.scalpTotal) }
        let meta = Meta(
            entryCount: entries.count,
            streak: HairAnalytics.loggingStreak(
                entryDates: entries.map(\.date), now: now, calendar: calendar),
            photos: Meta.PhotoSummary(
                count: photos.count,
                regions: Set(photos.map(\.region.rawValue)).sorted(),
                firstDate: photoDates.min().map { dayString($0, calendar: calendar) },
                lastDate: photoDates.max().map { dayString($0, calendar: calendar) }
            ),
            longTerm: Meta.LongTermAggregates(
                firstEntryDate: entries.map(\.date).min().map { dayString($0, calendar: calendar) },
                lastEntryDate: entries.map(\.date).max().map { dayString($0, calendar: calendar) },
                averageShed: allShedValues.isEmpty ? nil : round2(HairAnalytics.mean(allShedValues)),
                averageScalpTotal: allScalpValues.isEmpty ? nil : round2(HairAnalytics.mean(allScalpValues))
            ),
            omitted: Meta.OmittedCounts(
                dailyEntries: max(0, entries.count - windowed.count),
                treatments: max(0, treatments.count - includedTreatments.count),
                labs: max(0, labs.count - includedLabs.count),
                triggers: max(0, triggers.count - includedTriggers.count),
                progressCheckIns: max(0, progressCheckIns.count - progressCheckInFacts.count),
                sideEffects: omittedSideEffectCount
            )
        )

        return AIContext(
            generatedAt: iso8601(now),
            profile: profileFacts,
            dailySeries: dailySeries,
            treatments: treatmentFacts,
            labs: labFacts,
            triggers: triggerFacts,
            progressCheckIns: progressCheckInFacts,
            bodySignals: bodySignals,
            meta: meta
        )
    }

    // MARK: - Serialization

    /// Stable JSON: `.sortedKeys` always, so two builds over the same data are byte-identical
    /// (tests rely on it, and stable prefixes are what prompt caching wants).
    func jsonString(pretty: Bool = false) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    // MARK: - Pure helpers

    /// "yyyy-MM-dd" in the given calendar — pure component math, no formatter state.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// ISO8601 (UTC, whole seconds) — deterministic for a given `Date`.
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func flagCode(_ flag: LabFlag) -> String {
        switch flag {
        case .low: return "low"
        case .normal: return "normal"
        case .high: return "high"
        }
    }

    static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func bounded(_ value: String, limit: Int = 160) -> String {
        String(value.prefix(limit))
    }
}
