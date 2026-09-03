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
