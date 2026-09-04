//
//  EvidencePath.swift
//  Hair Compass AI 5
//
//  The Living Evidence Path: milestones on the plan's own clock, each explaining why it exists,
//  what it reviews, whether a photo belongs there, whether the record is mature enough to read,
//  and the next action. PlanStrands folds the same adherence engine per treatment so an overall
//  number can never hide one part of the plan that needs attention.
//

import Foundation
import SwiftData

struct EvidenceMilestone: Identifiable, Equatable {
    enum State: Equatable {
        case reached
        case next
        case ahead
    }

    let week: Int
    let title: String
    let state: State
    let why: String
    let evidence: String
    let needsPhoto: Bool
    let interpretable: Bool
    let nextAction: String

    var id: Int { week }
}

enum EvidencePath {
    static func date(ofWeek week: Int, phase: EvidencePhase, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: week * 7, to: phase.start) ?? phase.start
    }

    static func milestones(
        phase: EvidencePhase,
        photos: [PhotoRecord],
        calendar: Calendar
    ) -> [EvidenceMilestone] {
        var weeks = [0, 4, 12, 24]
        if phase.nextReviewWeek > 24 {
            weeks.append(phase.nextReviewWeek)
        }
        let hasBaselinePhoto = HairAnalytics.hasNearbyDate(
            anchor: phase.start,
            candidates: photos.map(\.createdAt),
            calendar: calendar
        )

        return weeks.map { week in
            let state: EvidenceMilestone.State
            if week == 0 || week <= phase.week {
                state = .reached
            } else if week == phase.nextReviewWeek {
                state = .next
            } else {
                state = .ahead
            }

            switch week {
            case 0:
                return EvidenceMilestone(
                    week: 0,
                    title: "Baseline",
                    state: state,
                    why: "Every later comparison needs the same clear starting point.",
                    evidence: "The start date, first check-ins, and a baseline photo set.",
                    needsPhoto: true,
                    interpretable: false,
                    nextAction: hasBaselinePhoto
                        ? "Keep logging; the first review is at week four."
                        : "Take a baseline photo in good light when you can."
                )
            case 4:
                return EvidenceMilestone(
                    week: 4,
                    title: "Week 4 review",
                    state: state,
                    why: "This early checkpoint is about fit and tolerability, not visible change.",
                    evidence: "Four weeks of check-ins, side effects, and plan consistency.",
                    needsPhoto: false,
                    interpretable: false,
                    nextAction: "Record what felt easy, difficult, or worth discussing."
                )
            case 12:
                return EvidenceMilestone(
                    week: 12,
                    title: "Week 12 review",
                    state: state,
                    why: "A structured checkpoint keeps day-to-day impressions from becoming the verdict.",
                    evidence: "Twelve weeks of records and a photo taken under comparable conditions.",
                    needsPhoto: true,
                    interpretable: false,
                    nextAction: "Add a comparable photo during the review week."
                )
            case 24:
                return EvidenceMilestone(
                    week: 24,
                    title: "Week 24 review",
                    state: state,
                    why: "The record is now long enough for a careful comparison with the baseline.",
                    evidence: "Baseline and week-24 photos, plan consistency, and the shedding record.",
                    needsPhoto: true,
                    interpretable: true,
                    nextAction: "Compare the photo sets and prepare the visit report."
                )
            default:
                return EvidenceMilestone(
                    week: week,
                    title: "Week \(week) review",
                    state: state,
                    why: "A regular checkpoint keeps the longer record easier to read.",
                    evidence: "Records since the last review and a photo taken under comparable conditions.",
                    needsPhoto: true,
                    interpretable: true,
                    nextAction: "Compare this checkpoint with the week-24 photo set."
                )
            }
        }
    }
}

struct PlanStrand: Identifiable {
    let id: String
    let name: String
    let thirtyDay: PlanAdherence.Consistency?
    let sevenDay: PlanAdherence.Consistency?
    /// False for an as-needed item, which is recorded per use and never given a percentage.
    let isScheduled: Bool

    /// A scheduled item with nothing settled yet is planned but unscored. The interface must not
    /// turn this state into a percentage, grade, or zero-width performance mark.
    var isUnscored: Bool {
        isScheduled && (thirtyDay?.scored ?? 0) == 0
    }
}

enum PlanStrands {
    static func build(
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        now: Date,
        calendar: Calendar
    ) -> [PlanStrand] {
        treatments.filter(\.isActive).map { treatment in
            PlanStrand(
                id: "\(treatment.persistentModelID.hashValue)",
                name: treatment.name.isEmpty ? treatment.treatmentClass.title : treatment.name,
                thirtyDay: PlanAdherence.consistency(
                    treatment: treatment,
                    doses: doses,
                    missed: missed,
                    windowDays: 30,
                    now: now,
                    calendar: calendar
                ),
                sevenDay: PlanAdherence.consistency(
                    treatment: treatment,
                    doses: doses,
                    missed: missed,
                    windowDays: 7,
                    now: now,
                    calendar: calendar
                ),
                isScheduled: PlanAdherence.hasSchedule(treatment)
            )
        }
    }

    static func overall(
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        windowDays: Int,
        now: Date,
        calendar: Calendar
    ) -> PlanAdherence.Consistency? {
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(
            byAdding: .day, value: -(windowDays - 1), to: today
        ) else { return nil }
        return PlanAdherence.consistency(
            treatments: treatments.filter(\.isActive),
            doses: doses,
            missed: missed,
            from: first,
            through: today,
            now: now,
            calendar: calendar
        )
    }
}

// MARK: - Evidence lenses

/// One evidence source, interpreted by the rule that belongs to it. A readiness state says
/// whether the *record* can be read; it never grades the person and never claims a treatment is
/// effective. The UI presents these as selectable lenses so Plan stays compact while the logic
/// remains inspectable.
struct EvidenceSignal: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case treatment
        case shedding
        case scalp
        case photos
        case labs
        case events

        var id: String { rawValue }
        var title: String {
            switch self {
            case .treatment: return "Plan"
            case .shedding: return "Shedding"
            case .scalp: return "Scalp"
            case .photos: return "Photos"
            case .labs: return "Labs"
            case .events: return "Events"
            }
        }
        var symbol: String {
            switch self {
            case .treatment: return "checklist"
            case .shedding: return "wind"
            case .scalp: return "circle.hexagongrid"
            case .photos: return "camera.viewfinder"
            case .labs: return "testtube.2"
            case .events: return "point.topleft.down.curvedto.point.bottomright.up"
            }
        }
    }

    /// Deliberately not success/failure. These describe how the record should be handled now.
    enum State: Int, Equatable {
        case standby
        case building
        case readable
        case discuss
    }

    let kind: Kind
    let state: State
    let status: String
    let summary: String
    let rule: String
    let nextAction: String

    var id: Kind { kind }
}

/// Deterministic readiness logic for every evidence source on the Plan screen. This is intentionally
/// separate from the review clock: week 24 can make treatment outcomes fair to discuss, but it does
/// not magically make an unmatched photo, a one-day shedding entry, or two unrelated labs comparable.
enum EvidenceSignals {
    static let observationWindowDays = 28
    static let minimumSheddingContextSamples = 5
    static let minimumSheddingSpanDays = 14
    static let minimumScalpSamples = 7
    static let minimumScalpSpanDays = 14
    static let triggerLagWeeks = 8...12

    static func build(
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        sideEffects: [SideEffectLog],
        photos: [PhotoRecord],
        labs: [LabResult],
        triggers: [TriggerEvent],
        now: Date,
        calendar: Calendar
    ) -> [EvidenceSignal] {
        let recentEntries = oneEntryPerDay(
            entries, windowDays: observationWindowDays, now: now, calendar: calendar
        )
        return [
            treatmentSignal(
                treatments: treatments, doses: doses, missed: missed,
                sideEffects: sideEffects, now: now, calendar: calendar
            ),
            sheddingSignal(entries: recentEntries, calendar: calendar),
            scalpSignal(entries: recentEntries, calendar: calendar),
            photoSignal(photos: photos, now: now, calendar: calendar),
            labSignal(labs: labs),
            eventSignal(triggers: triggers, now: now, calendar: calendar),
        ]
    }

    // MARK: Treatment: due actions + tolerability + the 24-week outcome gate

    private static func treatmentSignal(
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        sideEffects: [SideEffectLog],
        now: Date,
        calendar: Calendar
    ) -> EvidenceSignal {
        let active = treatments.filter(\.isActive)
        let scheduled = active.filter { PlanAdherence.hasSchedule($0) }
        let sideEffectStart = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let recentEffects = sideEffects.filter { $0.date >= sideEffectStart && $0.date <= now }
        let severe = recentEffects.filter { $0.severity >= 3 }.max { $0.date < $1.date }
        let rule = "Counts only actions that were actually due. Future actions, clinician-directed pauses and as-needed use never lower the percentage; hair outcomes wait for week 24."

        if let severe {
            return EvidenceSignal(
                kind: .treatment,
                state: .discuss,
                status: "Recent severe side effect",
                summary: "A severe \(severe.type.title.lowercased()) entry is part of this treatment record. This is a tolerability signal, not an effectiveness result.",
                rule: rule,
                nextAction: "Keep the date and treatment attached to it; this is worth discussing with the prescriber."
            )
        }

        guard !scheduled.isEmpty else {
            let hasOnlyAsNeeded = !active.isEmpty
            return EvidenceSignal(
                kind: .treatment,
                state: .standby,
                status: hasOnlyAsNeeded ? "Recorded per use" : "No scheduled plan yet",
                summary: hasOnlyAsNeeded
                    ? "Your active items have no due-time schedule, so the app records each use without inventing an adherence score."
                    : "A treatment clock begins only after an active item has a real schedule.",
                rule: rule,
                nextAction: hasOnlyAsNeeded
                    ? "Keep recording each use; add a schedule only if one genuinely belongs to the plan."
                    : "Add the treatment and schedule you already follow."
            )
        }

        let overall = PlanStrands.overall(
            treatments: scheduled, doses: doses, missed: missed,
            windowDays: 30, now: now, calendar: calendar
        )
        guard let overall, overall.scored > 0 else {
            return EvidenceSignal(
                kind: .treatment,
                state: .building,
                status: "Waiting for due actions",
                summary: "The plan is scheduled, but no occurrence has become scorable yet. An open or future action is not a missed action.",
                rule: rule,
                nextAction: "Use the plan normally; the first settled due action will start the record."
            )
        }

        let earliestStart = scheduled.map(\.startDate).min() ?? now
        let trackedDays = max(1, (calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: earliestStart),
            to: calendar.startOfDay(for: now)
        ).day ?? 0) + 1)
        let hasWeek = trackedDays >= 7
        return EvidenceSignal(
            kind: .treatment,
            state: hasWeek ? .readable : .building,
            status: hasWeek ? "30-day rhythm is readable" : "First week is still building",
            summary: "\(overall.completed) of \(overall.scored) due actions were completed; \(overall.planned) actions were planned through today.",
            rule: rule,
            nextAction: hasWeek
                ? "Read each treatment separately below; consistency helps interpret a later review but does not prove effectiveness."
                : "Keep settling due actions until there is at least one week of plan evidence."
        )
    }

    // MARK: Shedding: ordinal trend, split by wash context

    private static func sheddingSignal(entries: [DailyEntry], calendar: Calendar) -> EvidenceSignal {
        let rule = "Uses the 0–3 self-report scale and keeps wash days separate from non-wash days. A one-day spike—or a wash day compared with a non-wash day—is never called a trend."
        guard !entries.isEmpty else {
            return EvidenceSignal(
                kind: .shedding, state: .standby, status: "No observations yet",
                summary: "Shedding becomes useful as a repeated ordinal pattern, not as a hair count.",
                rule: rule,
                nextAction: "Log the level and whether hair was washed whenever you check in."
            )
        }

        let washCount = entries.filter(\.washedHair).count
        let nonWashCount = entries.count - washCount
        let span = spanDays(entries.map(\.date), calendar: calendar)
        let washReady = washCount >= minimumSheddingContextSamples
        let nonWashReady = nonWashCount >= minimumSheddingContextSamples
        let hasTimeSpan = span >= minimumSheddingSpanDays

        if hasTimeSpan && (washReady || nonWashReady) {
            let status: String
            if washReady && nonWashReady {
                status = "Both wash contexts are readable"
            } else if washReady {
                status = "Wash-day series is readable"
            } else {
                status = "Non-wash series is readable"
            }
            return EvidenceSignal(
                kind: .shedding,
                state: .readable,
                status: status,
                summary: "The last \(observationWindowDays) days contain \(washCount) wash-day and \(nonWashCount) non-wash observation\(nonWashCount == 1 ? "" : "s") across \(span) days.",
                rule: rule,
                nextAction: washReady && nonWashReady
                    ? "Keep marking wash days; read the two smoothed series over weeks, never day by day."
                    : "Keep marking wash days so the other context can build its own five-observation baseline."
            )
        }

        let strongestContext = max(washCount, nonWashCount)
        let samplesNeeded = max(0, minimumSheddingContextSamples - strongestContext)
        let timeNeeded = max(0, minimumSheddingSpanDays - span)
        let need: String
        if samplesNeeded > 0 && timeNeeded > 0 {
            need = "\(samplesNeeded) more like-with-like observation\(samplesNeeded == 1 ? "" : "s") across \(timeNeeded) more day\(timeNeeded == 1 ? "" : "s")"
        } else if samplesNeeded > 0 {
            need = "\(samplesNeeded) more like-with-like observation\(samplesNeeded == 1 ? "" : "s")"
        } else {
            need = "\(timeNeeded) more day\(timeNeeded == 1 ? "" : "s") of separation"
        }
        return EvidenceSignal(
            kind: .shedding,
            state: .building,
            status: "Context-matched baseline building",
            summary: "You have \(washCount) wash-day and \(nonWashCount) non-wash observation\(nonWashCount == 1 ? "" : "s"); the record needs \(need).",
            rule: rule,
            nextAction: "Keep the check-in light and consistent; do not add extra checks after an anxious hair day."
        )
    }

    // MARK: Scalp: validated component score + a separate symptom window

    private static func scalpSignal(entries: [DailyEntry], calendar: Calendar) -> EvidenceSignal {
        let rule = "Maps flaking 0–3 to 0/3/6/10, then adds redness 0–3 and itch 0–3 for a 0–16 scalp score. It reads symptom direction, never hair growth."
        guard let latest = entries.last else {
            return EvidenceSignal(
                kind: .scalp, state: .standby, status: "No symptom record yet",
                summary: "Flaking, redness and itch need to be captured together for the score to mean anything.",
                rule: rule,
                nextAction: "Rate the same three signs in a daily check-in when symptoms are relevant."
            )
        }

        let span = spanDays(entries.map(\.date), calendar: calendar)
        let latestTotal = latest.scalpTotal
        let latestBand = latest.scalpBand.title.lowercased()
        guard entries.count >= minimumScalpSamples, span >= minimumScalpSpanDays else {
            let samplesNeeded = max(0, minimumScalpSamples - entries.count)
            let daysNeeded = max(0, minimumScalpSpanDays - span)
            var needs: [String] = []
            if samplesNeeded > 0 { needs.append("\(samplesNeeded) more entr\(samplesNeeded == 1 ? "y" : "ies")") }
            if daysNeeded > 0 { needs.append("\(daysNeeded) more day\(daysNeeded == 1 ? "" : "s") of separation") }
            return EvidenceSignal(
                kind: .scalp,
                state: .building,
                status: "Symptom window building",
                summary: "The latest scalp score is \(latestTotal)/16 (\(latestBand)); the direction needs \(needs.joined(separator: " and ")).",
                rule: rule,
                nextAction: "Use the same 0–3 ratings rather than checking more often."
            )
        }

        let split = max(1, entries.count / 2)
        let early = HairAnalytics.mean(entries.prefix(split).map { Double($0.scalpTotal) })
        let recent = HairAnalytics.mean(entries.suffix(split).map { Double($0.scalpTotal) })
        let delta = recent - early
        let status: String
        if delta <= -ProgressReport.scalpDeadband {
            status = "Symptoms are easing in this window"
        } else if delta >= ProgressReport.scalpDeadband {
            status = "Symptoms are higher in this window"
        } else {
            status = "Symptoms are steady in this window"
        }
        return EvidenceSignal(
            kind: .scalp,
            state: .readable,
            status: status,
            summary: "The latest score is \(latestTotal)/16 (\(latestBand)); the earlier half averages \(oneDecimal(early)) and the recent half \(oneDecimal(recent)).",
            rule: rule,
            nextAction: latest.scalpBand == .severe
                ? "Keep the dated record; persistent severe or painful symptoms belong in a clinician conversation."
                : "Continue the same three ratings so the next window stays comparable."
        )
    }

    // MARK: Photos: same series + same conditions + enough time

    private struct PhotoSeriesKey: Hashable {
        let region: PhotoRegion
        let patch: String
    }

    private static func photoSignal(
        photos: [PhotoRecord], now: Date, calendar: Calendar
    ) -> EvidenceSignal {
        let rule = "A pair is readable only when it is the same region (and patch series), matching wet/dry state, light, distance and parting, at least 28 days apart."
        guard !photos.isEmpty else {
            return EvidenceSignal(
                kind: .photos, state: .standby, status: "Baseline not captured",
                summary: "A clear starting set is more useful than frequent, unmatched photos.",
                rule: rule,
                nextAction: "Capture a baseline in good light and keep the setup for the next month."
            )
        }

        let groups = Dictionary(grouping: photos) { photo in
            PhotoSeriesKey(
                region: photo.region,
                patch: photo.region == .patch ? photo.normalizedPatchSeriesLabel : ""
            )
        }
        var readyLabels: [String] = []
        var hasConditionMismatch = false
        var hasEarlyMatchedPair = false
        for (key, unsorted) in groups {
            let series = unsorted.sorted { $0.createdAt < $1.createdAt }
            guard let baseline = series.first, series.count >= 2 else { continue }
            for candidate in series.dropFirst().reversed() {
                let gap = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: baseline.createdAt),
                    to: calendar.startOfDay(for: candidate.createdAt)
                ).day ?? 0
                if PhotoComparability.mismatchCaption(baseline, candidate) == nil {
                    if gap >= PhotoCadence.intervalDays {
                        let label = key.region == .patch && !key.patch.isEmpty
                            ? "\(key.region.title): \(key.patch)" : key.region.title
                        readyLabels.append(label)
                    } else {
                        hasEarlyMatchedPair = true
                    }
                    break
                } else {
                    hasConditionMismatch = true
                }
            }
        }

        if !readyLabels.isEmpty {
            let labels = readyLabels.sorted().prefix(2).joined(separator: " · ")
            let verb = readyLabels.count == 1 ? "has" : "have"
            return EvidenceSignal(
                kind: .photos,
                state: .readable,
                status: "\(readyLabels.count) comparable series ready",
                summary: "\(labels) \(readyLabels.count > 2 ? "and \(readyLabels.count - 2) more " : "")\(verb) a condition-matched pair at least 28 days apart.",
                rule: rule,
                nextAction: "Compare only those matched pairs; keep the next capture on the monthly cadence."
            )
        }

        let cadence = PhotoCadence.status(photos: photos, now: now, calendar: calendar)
        let status: String
        let next: String
        if hasConditionMismatch {
            status = "Follow-up conditions do not match"
            next = "Repeat one region using the baseline's light, distance, parting and wet/dry state."
        } else if hasEarlyMatchedPair {
            status = "Matched pair is still too close"
            next = "Let at least 28 days separate the baseline and follow-up; more photos will not make the change clearer."
        } else {
            switch cadence {
            case .noBaseline:
                status = "Baseline not captured"
                next = "Capture one clear baseline set."
            case .due:
                status = "Baseline ready for follow-up"
                next = "Capture the same regions now, matching the baseline conditions."
            case .upcoming(let days):
                status = "Baseline saved · follow-up in \(days) days"
                next = "Wait for the monthly follow-up; keep the same setup notes."
            }
        }
        return EvidenceSignal(
            kind: .photos,
            state: .building,
            status: status,
            summary: "\(photos.count) photo\(photos.count == 1 ? "" : "s") across \(groups.count) series, with no mature condition-matched pair yet.",
            rule: rule,
            nextAction: next
        )
    }

    // MARK: Labs: per-test range + same-test repeats only

    private static func labSignal(labs: [LabResult]) -> EvidenceSignal {
        let rule = "Reads each test only against its own effective reference range. A repeat trend compares the same test in its canonical unit; unrelated values are never blended into a score."
        guard !labs.isEmpty else {
            return EvidenceSignal(
                kind: .labs, state: .standby, status: "No individualized labs",
                summary: "Labs are optional context, not a checklist or a blanket supplement screen.",
                rule: rule,
                nextAction: "Record a result only when it was actually ordered; use the range printed on the report when available."
            )
        }

        let groups = Dictionary(grouping: labs, by: \.test)
        let latest = groups.compactMapValues { $0.max { $0.collectedAt < $1.collectedAt } }
        let flagged = latest.values.filter { $0.flag != .normal }
        let repeated = groups.values.filter { $0.count >= 2 }
        let movingTowardRange = repeated.filter { group in
            let sorted = group.sorted { $0.collectedAt < $1.collectedAt }
            guard sorted.count >= 2, let current = sorted.last else { return false }
            return HairAnalytics.labImproving(
                previous: sorted[sorted.count - 2].value,
                latest: current.value,
                range: current.effectiveRange
            )
        }.count

        if !flagged.isEmpty {
            return EvidenceSignal(
                kind: .labs,
                state: .discuss,
                status: "\(flagged.count) latest result\(flagged.count == 1 ? "" : "s") outside range",
                summary: "The app checked \(latest.count) latest test\(latest.count == 1 ? "" : "s") separately; an out-of-range flag is context for review, not a diagnosis.",
                rule: rule,
                nextAction: "Confirm the printed lab range and take the flagged result to a clinician; do not infer a supplement from a combined score."
            )
        }

        let repeatText = repeated.isEmpty
            ? "Each has a range read, but no same-test repeat exists yet."
            : "\(repeated.count) same-test series can be read over time\(movingTowardRange > 0 ? "; \(movingTowardRange) moved toward its range" : "")."
        return EvidenceSignal(
            kind: .labs,
            state: .readable,
            status: repeated.isEmpty ? "Latest ranges are readable" : "Same-test history is readable",
            summary: "\(latest.count) latest test\(latest.count == 1 ? " is" : "s are") in the recorded range. \(repeatText)",
            rule: rule,
            nextAction: "Keep each future draw attached to its test and report range; retest timing belongs to the clinician's plan."
        )
    }

    // MARK: Life events: dated context with an 8–12 week lag window

    private static func eventSignal(
        triggers: [TriggerEvent], now: Date, calendar: Calendar
    ) -> EvidenceSignal {
        let rule = "Places a real dated event beside shedding after the expected 8–12 week lag. Timing can explain context; it cannot prove that the event caused a change."
        guard !triggers.isEmpty else {
            return EvidenceSignal(
                kind: .events, state: .standby, status: "No event recorded",
                summary: "No major illness, rapid weight loss, childbirth, medication change or other trigger is recorded.",
                rule: rule,
                nextAction: "Add only a real, memorable event—not ordinary daily stress or a guess."
            )
        }

        let dated = triggers.map { ($0, $0.weeksElapsed(now: now, calendar: calendar)) }
        let focus = dated
            .filter { triggerLagWeeks.contains($0.1) }
            .max { $0.0.date < $1.0.date }
            ?? dated.max { $0.0.date < $1.0.date }!
        let event = focus.0
        let weeks = focus.1
        let status: String
        let state: EvidenceSignal.State
        let next: String
        if weeks < triggerLagWeeks.lowerBound {
            let remaining = triggerLagWeeks.lowerBound - weeks
            status = "Context window opens in \(remaining) week\(remaining == 1 ? "" : "s")"
            state = .building
            next = "Keep ordinary shedding check-ins; do not increase checking while the lag window approaches."
        } else if triggerLagWeeks.contains(weeks) {
            status = "Inside the 8–12 week context window"
            state = .readable
            next = "Read any repeated shedding pattern beside this date as context only, not proof of cause."
        } else {
            status = "Event preserved on the timeline"
            state = .readable
            next = weeks > 26
                ? "If shedding remains heavy or is still rising beyond six months, the dated record is useful for a clinician review."
                : "Keep the date visible at reviews; no extra action is created by the event alone."
        }
        return EvidenceSignal(
            kind: .events,
            state: state,
            status: status,
            summary: "\(event.type.title) was recorded \(weeks) week\(weeks == 1 ? "" : "s") ago; \(triggers.count) event\(triggers.count == 1 ? " is" : "s are") kept on the timeline.",
            rule: rule,
            nextAction: next
        )
    }

    // MARK: Helpers

    /// Defensive day de-duplication keeps readiness based on days observed, even if an imported
    /// store contains duplicate rows for a date. The most recently timestamped row wins.
    private static func oneEntryPerDay(
        _ entries: [DailyEntry],
        windowDays: Int,
        now: Date,
        calendar: Calendar
    ) -> [DailyEntry] {
        let today = calendar.startOfDay(for: now)
        let floor = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today
        // Calendar-day evidence includes all of today. Backups and backfilled rows may be
        // normalized to noon even when the screen is opened in the morning; excluding those by
        // clock time would make a saved check-in disappear from readiness for a few hours.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let eligible = entries.filter { $0.date >= floor && $0.date < tomorrow }
        return Dictionary(grouping: eligible) { calendar.startOfDay(for: $0.date) }
            .compactMap { $0.value.max { $0.date < $1.date } }
            .sorted { $0.date < $1.date }
    }

    private static func spanDays(_ dates: [Date], calendar: Calendar) -> Int {
        guard let first = dates.min(), let last = dates.max() else { return 0 }
        return (calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last)
        ).day ?? 0) + 1
    }

    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
