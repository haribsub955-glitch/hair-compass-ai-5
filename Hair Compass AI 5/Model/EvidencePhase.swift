//
//  EvidencePhase.swift
//  Hair Compass AI 5
//
//  Where the person is in the plan, as data. The anchor is the earliest active daily treatment
//  (the same rule ProgressReport uses), else the first entry in the record. The review clock is
//  ProgressReport's: weeks 4, 12, 24, then every 12. Nothing here judges the hair — it only
//  says how far along the record is and when the next honest read is due.
//

import Foundation

struct EvidencePhase: Equatable {
    enum Anchor: Equatable {
        case treatment(name: String)
        case record
    }

    let anchor: Anchor
    /// Start of the anchor's calendar day.
    let start: Date
    /// 1 on the start day.
    let dayNumber: Int
    let week: Int
    let label: String
    let nextReviewWeek: Int
    let nextReviewDate: Date
    let daysToReview: Int

    var isMilestoneWeek: Bool { ProgressReport.isMilestone(week: week) }
    /// 0 on the first day of the current week, 6 on the last.
    var daysIntoWeek: Int { (dayNumber - 1) - week * 7 }
    /// 0…1 through the current review window — the horizon marker's position (Important 4). 0
    /// on the start day, 1 on the review day itself (and beyond, clamped); the denominator is
    /// the review's own week count, not a fixed horizon, so an early review (week 4) and a late
    /// one (week 24+) both read as "how far through this stretch", not "how far through a year".
    var progressToReview: Double {
        min(1, max(0, Double(dayNumber - 1) / Double(max(1, nextReviewWeek * 7))))
    }

    static func label(forWeek week: Int) -> String {
        switch week {
        case ..<4: return "Building the baseline"
        case 4..<12: return "Early evidence"
        case 12..<24: return "Assessment"
        default: return "Review-ready"
        }
    }

    static func current(
        treatments: [Treatment],
        entries: [DailyEntry],
        now: Date,
        calendar: Calendar
    ) -> EvidencePhase? {
        let primary = treatments
            .filter { $0.isActive && !$0.slots.isEmpty }
            .min { $0.startDate < $1.startDate }
        let anchor: Anchor
        let startDate: Date
        if let primary {
            anchor = .treatment(name: primary.name.isEmpty ? primary.treatmentClass.title : primary.name)
            startDate = primary.startDate
        } else if let first = entries.map(\.date).min() {
            anchor = .record
            startDate = first
        } else {
            return nil
        }
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        let days = max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
        // One review clock: the same weeksElapsed ProgressReport uses, so this phase's "week"
        // never disagrees with the progress report's.
        let week = HairAnalytics.weeksElapsed(since: start, now: now, calendar: calendar)
        let nextWeek = ProgressReport.nextMilestone(after: week)
        let nextDate = calendar.date(byAdding: .day, value: nextWeek * 7, to: start) ?? today
        let daysToReview = max(0, calendar.dateComponents([.day], from: today, to: nextDate).day ?? 0)
        return EvidencePhase(
            anchor: anchor, start: start, dayNumber: days + 1, week: week,
            label: label(forWeek: week), nextReviewWeek: nextWeek,
            nextReviewDate: nextDate, daysToReview: daysToReview
        )
    }
}
