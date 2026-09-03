//
//  GroundingCards.swift
//  Hair Compass AI 5
//
//  The deterministic Daily Grounding card (spec §4, §10). One card per state, chosen by the
//  spec's hierarchy — safety, then a real shedding observation, then the action that is due,
//  then a photo or review that is approaching, then closure, recovery, a milestone, the early
//  horizon, and finally a quiet day. Every card acknowledges, anchors in the record, points at
//  one action at most, and closes by saying what needs no attention. Pure: the same record
//  produces the same card all day; it changes only when the record does. The server-generated
//  card (spec §4.5) arrives later and falls back to this one.
//

import Foundation

struct GroundingCard: Equatable {
    enum Kind: String {
        case safety, grounding, continuation, preparation, closure, settled, recovery, celebration, education, quiet
    }

    enum Action: Equatable {
        case completePlanItem(id: String, label: String)
        case logCheckIn
        case openPhotos
        case openPlan
        case prepareVisit
        case none
    }

    let kind: Kind
    let eyebrow: String
    let headline: String
    let body: String
    let evidenceAnchor: String?
    let primary: Action
    let closure: String
    /// Shown behind "Why this?": the one fact in the record that selected this card.
    let reason: String
}

struct GroundingInput {
    var flags: [ClinicianReviewFlag]
    var plan: PlanAdherence.TodayPlan
    var missedYesterday: Int
    var phase: EvidencePhase?
    var photo: PhotoCadence.Status
    var photoWithinTwoWeeks: Bool
    var consistency30: PlanAdherence.Consistency?
    var sheddingAboveUsual: Bool
    var loggedToday: Bool
}

enum GroundingSignals {
    /// True when yesterday's shed band is strictly above every one of the (up to six) entries
    /// before it, and at least three such entries exist — a conservative "above your usual
    /// range", never a trend claim.
    static func sheddingAboveUsual(entries: [DailyEntry], now: Date, calendar: Calendar) -> Bool {
        guard let yesterdayDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return false }
        let bounds = HairAnalytics.dayBounds(for: yesterdayDay, calendar: calendar)
        let sorted = entries.sorted { $0.date < $1.date }
        guard let yesterday = sorted.last(where: { bounds.contains($0.date) }) else { return false }
        let prior = sorted.filter { $0.date < bounds.lowerBound }.suffix(6)
        guard prior.count >= 3 else { return false }
        let usualMax = prior.map { $0.shed.rawValue }.max() ?? 0
        return yesterday.shed.rawValue > usualMax
    }

    /// Yesterday's occurrences that were missed or skipped — the recovery card's trigger.
    static func missedYesterday(
        treatments: [Treatment], doses: [TreatmentDose], missed: [MissedDoseRecord],
        now: Date, calendar: Calendar
    ) -> Int {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return 0 }
        return treatments
            .flatMap {
                PlanAdherence.occurrences(treatment: $0, doses: doses, missed: missed,
                                          from: yesterday, through: yesterday, now: now, calendar: calendar)
            }
            .filter { $0.state == .missed || $0.state == .skipped }
            .count
    }
}

enum GroundingCards {

    static func daysWord(_ n: Int) -> String {
        switch n {
        case ...0: return "today"
        case 1: return "tomorrow"
        default: return "in \(n) days"
        }
    }

    private static func reviewAnchor(_ phase: EvidencePhase?) -> String? {
        guard let phase else { return nil }
        return phase.daysToReview == 0 ? "Review due today" : "Next review in \(phase.daysToReview) days"
    }

    private static func photoClosure(_ photo: PhotoCadence.Status) -> String {
        switch photo {
        case .noBaseline: return "A baseline photo can wait for a day with good light."
        case .due: return "A comparable photo is due at the next convenient moment."
        case .upcoming(let days): return days <= 3 ? "Your next comparable photo is \(daysWord(days))." : "No photo is needed today."
        }
    }

    private static func dueAction(_ plan: PlanAdherence.TodayPlan, loggedToday: Bool) -> GroundingCard.Action {
        if let next = plan.nextOpen, next.state == .due {
            let name = next.treatment.name.isEmpty ? next.treatment.treatmentClass.title : next.treatment.name
            return .completePlanItem(id: next.id, label: "Mark \(name) complete")
        }
        return loggedToday ? .none : .logCheckIn
    }

    static func select(_ input: GroundingInput) -> GroundingCard {
        let phase = input.phase
        let dayLine = phase.map { "Day \($0.dayNumber)" } ?? "Today"

        // 1. Safety: a clinician-review rule fired. No motivation, one care step.
        if let flag = input.flags.first {
            return GroundingCard(
                kind: .safety, eyebrow: "Worth a clinician's look",
                headline: flag.title, body: flag.detail, evidenceAnchor: nil,
                primary: .prepareVisit,
                closure: "This note is saved for your clinician. Do not change or double a medication because of anything in the app; follow your prescriber's or the product's instructions.",
                reason: "A pattern in your record met the clinician-review rule \"\(flag.id)\"."
            )
        }

        // 2. (An explicit concern from "I'm worried" arrives with sub-project G4.)

        // 3. Grounding: yesterday's shedding sat above the recent range.
        if input.sheddingAboveUsual {
            return GroundingCard(
                kind: .grounding, eyebrow: "Today's grounding",
                headline: "One observation is not a trend",
                body: "You recorded more shedding yesterday than in the days before it. Shedding varies between wash days, so Hair Compass waits for a repeated pattern before reading anything into it.",
                evidenceAnchor: reviewAnchor(phase),
                primary: dueAction(input.plan, loggedToday: input.loggedToday),
                closure: "You logged it. That is enough for today.",
                reason: "Yesterday's shedding band was above every entry in the six days before it."
            )
        }

        // 4. Continuation: an action is due now.
        if let next = input.plan.nextOpen, next.state == .due {
            let name = next.treatment.name.isEmpty ? next.treatment.treatmentClass.title : next.treatment.name
            return GroundingCard(
                kind: .continuation, eyebrow: "Today's grounding",
                headline: "One step today keeps the record honest",
                body: "\(dayLine) of your plan. Your next planned action is \(name). Consistent records are what make the next review readable.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .completePlanItem(id: next.id, label: "Mark \(name) complete"),
                closure: photoClosure(input.photo),
                reason: "\(name) is due and not yet recorded."
            )
        }

        // 5. Preparation: a comparable photo is due, a baseline is pending, or a review is close.
        switch input.photo {
        case .due(let overdue):
            return GroundingCard(
                kind: .preparation, eyebrow: "Coming up",
                headline: "A comparable photo is due",
                body: "It has been \(PhotoCadence.intervalDays + overdue) days since your last photo. Same light, same parting, same distance keeps the comparison fair.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .openPhotos,
                closure: "After that, nothing else is needed today.",
                reason: "Your last photo is \(PhotoCadence.intervalDays + overdue) days old; the cadence is every \(PhotoCadence.intervalDays) days."
            )
        case .noBaseline:
            return GroundingCard(
                kind: .preparation, eyebrow: "Coming up",
                headline: "A baseline photo anchors everything",
                body: "There is no baseline photo yet. One photo in good light, taken the same way each time, is what every later comparison is measured against.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .openPhotos,
                closure: "Whenever you are ready — it does not have to be today.",
                reason: "The record has no photo yet."
            )
        case .upcoming:
            break
        }
        if let phase, phase.daysToReview <= 7 {
            let headline = phase.nextReviewWeek == 4 ? "Your first review is approaching" : "Your week \(phase.nextReviewWeek) review is approaching"
            return GroundingCard(
                kind: .preparation, eyebrow: "Coming up",
                headline: headline,
                body: "The record now holds \(phase.week) weeks of plan and shedding entries. A comparable photo before the review completes the checkpoint.",
                evidenceAnchor: "Review \(daysWord(phase.daysToReview))",
                primary: input.photoWithinTwoWeeks ? .none : .openPhotos,
                closure: input.photoWithinTwoWeeks ? "Your recent photo already covers it. Nothing else is needed today." : "One photo this week is the whole preparation.",
                reason: "The week \(phase.nextReviewWeek) review is \(daysWord(phase.daysToReview))."
            )
        }

        // 6. Settled or closure: every planned action today is recorded.
        if input.plan.isComplete {
            if input.plan.completedCount == 0 {
                return GroundingCard(
                    kind: .settled, eyebrow: "Today is recorded",
                    headline: "Today's plan is recorded",
                    body: "Every action today was skipped with a reason. One skipped day does not erase the record; tomorrow is a clean place to restart.",
                    evidenceAnchor: reviewAnchor(phase),
                    primary: .none,
                    closure: "Nothing else needs to be checked today.",
                    reason: "Every planned action today was skipped with a reason."
                )
            }
            return GroundingCard(
                kind: .closure, eyebrow: "Today is done",
                headline: "Your plan is complete for today",
                body: "You showed up. Today is now part of the evidence you are building, and your next useful check is tomorrow.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .none,
                closure: "Nothing else needs to be checked today.",
                reason: "Every planned action today is recorded or skipped with a reason."
            )
        }

        // 7. Recovery: something was missed yesterday and today has not started yet.
        if input.missedYesterday > 0 {
            let rhythm = input.consistency30.map { "Over the last 30 days you completed \($0.completed) of \($0.expected) planned actions. " } ?? ""
            let due = dueAction(input.plan, loggedToday: input.loggedToday)
            let primary: GroundingCard.Action
            if case .completePlanItem = due {
                primary = due
            } else {
                primary = input.loggedToday ? .openPlan : .logCheckIn
            }
            return GroundingCard(
                kind: .recovery, eyebrow: "Today's grounding",
                headline: "Today is a clean place to restart",
                body: "One missed action does not erase the record already built. \(rhythm)Resume your normal plan today unless your clinician instructed otherwise.",
                evidenceAnchor: reviewAnchor(phase),
                primary: primary,
                closure: "Nothing needs catching up. Today's step is the only one that counts now.",
                reason: "\(input.missedYesterday) planned action\(input.missedYesterday == 1 ? " was" : "s were") not recorded yesterday."
            )
        }

        // 8. Recognition: a milestone week, on its first two days only.
        if let phase, phase.isMilestoneWeek, phase.daysIntoWeek <= 1 {
            let weeks: String
            switch phase.week {
            case 4: weeks = "Four"
            case 12: weeks = "Twelve"
            case 24: weeks = "Twenty-four"
            default: weeks = "\(phase.week)"
            }
            return GroundingCard(
                kind: .celebration, eyebrow: "Stored evidence",
                headline: "\(weeks) weeks of evidence, stored",
                body: "Your record now covers \(phase.week) weeks of plan and shedding entries. This is stored evidence, not a verdict on your hair — the review reads it.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .openPlan,
                closure: "Nothing else is needed today.",
                reason: "Week \(phase.week) is a review milestone on the plan's clock."
            )
        }

        // 9. Education: too early to judge.
        if let phase, phase.week < 4 {
            return GroundingCard(
                kind: .education, eyebrow: "Today's grounding",
                headline: "You are building the baseline",
                body: "\(dayLine) of your plan. It is too early to judge visible change; consistent records make the first comparison at week four more reliable.",
                evidenceAnchor: reviewAnchor(phase),
                primary: input.loggedToday ? .none : .logCheckIn,
                closure: "No photo is needed today.",
                reason: "The plan is in its first four weeks."
            )
        }

        // 10. Quiet day.
        return GroundingCard(
            kind: .quiet, eyebrow: "Today's grounding",
            headline: "You are allowed to have a normal day",
            body: "No unusual pattern or plan action needs your attention right now. Hair Compass will say when something meaningful is due.",
            evidenceAnchor: reviewAnchor(phase),
            primary: input.loggedToday ? .none : .logCheckIn,
            closure: input.loggedToday ? "You can close the app." : "The check-in is the whole day.",
            reason: "Nothing in the record met an earlier rule today."
        )
    }
}
