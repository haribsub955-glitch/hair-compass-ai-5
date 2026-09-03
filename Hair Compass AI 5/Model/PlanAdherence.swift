//
//  PlanAdherence.swift
//  Hair Compass AI 5
//
//  The plan-adherence engine (spec: 2026-09-03 Daily Grounding + Plan Adherence, §6). Treatments,
//  logged doses and missed-dose records in; occurrences with one state each out, then the counts
//  Today and Plan show. Pure and deterministic — every date decision uses the calendar passed in,
//  nothing here reads the clock or a ModelContext. It measures completed planned actions, never
//  hair outcomes, and it never scores a pause, a future day or an as-needed item.
//

import Foundation
import SwiftData

enum PlanAdherence {

    // MARK: Types

    enum OccurrenceState: String, Equatable {
        /// Today, slot time not yet reached — or a future day.
        case upcoming
        /// Today, slot time reached (slotless items are due all day), nothing recorded yet.
        case due
        case completed
        /// A missed-dose record with any reason other than a clinician-directed pause.
        case skipped
        /// A past expected occurrence with no dose and no record.
        case missed
        /// Excluded from every count: a clinician-directed pause, a paused treatment, a day
        /// before the start or after the end, a weekday the item is not scheduled for.
        case notExpected
    }

    struct Occurrence: Identifiable {
        let treatment: Treatment
        /// Start of the calendar day.
        let day: Date
        /// "HH:mm", or "" for a slotless periodic item.
        let slot: String
        let state: OccurrenceState
        let completedAt: Date?

        var id: String {
            "\(treatment.persistentModelID.hashValue)|\(Int(day.timeIntervalSince1970))|\(slot)"
        }
        var isOpen: Bool { state == .due || state == .upcoming }
        var isSettled: Bool { state == .completed || state == .skipped }
    }

    /// Completed planned actions over the actions that counted. `expected` never includes a
    /// future, paused, not-expected or still-open occurrence.
    struct Consistency: Equatable {
        let completed: Int
        let expected: Int
        var fraction: Double { expected == 0 ? 0 : Double(completed) / Double(expected) }
        var percent: Int { Int((fraction * 100).rounded()) }
    }

    struct TodayPlan {
        /// Today's occurrences, `notExpected` omitted, sorted by slot time then name.
        let occurrences: [Occurrence]
        var completedCount: Int { occurrences.filter { $0.state == .completed }.count }
        var settledCount: Int { occurrences.filter(\.isSettled).count }
        var openCount: Int { occurrences.filter(\.isOpen).count }
        var isComplete: Bool { !occurrences.isEmpty && openCount == 0 }
        var nothingExpected: Bool { occurrences.isEmpty }
        var nextOpen: Occurrence? {
            occurrences.first { $0.state == .due } ?? occurrences.first { $0.state == .upcoming }
        }
    }

    enum DayMark: Equatable {
        case complete, partial, missed, notExpected, today, upcoming
    }

    struct DayState: Identifiable, Equatable {
        let day: Date
        let mark: DayMark
        let completed: Int
        let expected: Int
        var id: Date { day }
    }

    // MARK: Schedule

    /// Whether the engine can score this item: clock slots, or a periodic item done on a weekday
    /// cadence (the care products, plus microneedling and LLLT — see
    /// `TreatmentClass.supportsWeekdaySchedule`). Anything else (PRP, a free-form "other" item
    /// with no times) is recorded as usage and never given a percentage.
    static func hasSchedule(_ treatment: Treatment) -> Bool {
        !treatment.slots.isEmpty || treatment.treatmentClass.supportsWeekdaySchedule
    }

    /// The slots expected on `day` — empty when the item is not scheduled that weekday or has not
    /// started yet. An inactive treatment with no end date was never expected at all. With an end
    /// date: every day before the stop day keeps every slot; the stop day itself keeps only the
    /// slots whose clock time is at or before the stop time (a slotless occurrence always
    /// counts), so a dose logged earlier on the day a treatment was paused stays countable; days
    /// after the stop day return nothing.
    static func expectedSlots(_ treatment: Treatment, on day: Date, calendar: Calendar) -> [String] {
        guard hasSchedule(treatment) else { return [] }
        let start = calendar.startOfDay(for: treatment.startDate)
        guard day >= start else { return [] }
        guard treatment.isDueToday(now: day, calendar: calendar) else { return [] }
        let allSlots = treatment.slots.isEmpty ? [""] : treatment.slots
        guard !treatment.isActive else { return allSlots }
        guard let end = treatment.endDate else { return [] }
        let stopDay = calendar.startOfDay(for: end)
        if day < stopDay {
            return allSlots
        }
        guard day == stopDay else { return [] }
        return allSlots.filter { slot in
            guard let slotTime = slotDate(slot, on: day, calendar: calendar) else { return true }
            return slotTime <= end
        }
    }

    // MARK: Occurrences

    static func occurrences(
        treatment: Treatment,
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        from firstDay: Date,
        through lastDay: Date,
        now: Date,
        calendar: Calendar
    ) -> [Occurrence] {
        let id = treatment.persistentModelID
        // Ascending by loggedAt so a slot with more than one dose agrees with
        // `DoseRepository.matchingDose`, which fetches `sortBy: loggedAt` and returns the first —
        // the same dose Undo deletes.
        let ownDoses = doses.filter { $0.treatment?.persistentModelID == id }
            .sorted { $0.loggedAt < $1.loggedAt }
        let ownMissed = missed.filter { $0.treatment?.persistentModelID == id }
        let today = calendar.startOfDay(for: now)
        let last = calendar.startOfDay(for: lastDay)
        var day = calendar.startOfDay(for: firstDay)
        var out: [Occurrence] = []
        while day <= last {
            let bounds = HairAnalytics.dayBounds(for: day, calendar: calendar)
            for slot in expectedSlots(treatment, on: day, calendar: calendar) {
                let dose = ownDoses.first { $0.slot == slot && bounds.contains($0.loggedAt) }
                let record = ownMissed.first { $0.slot == slot && bounds.contains($0.date) }
                let state: OccurrenceState
                if dose != nil {
                    state = .completed
                } else if let record {
                    state = record.reason == .clinicianDirectedPause ? .notExpected : .skipped
                } else if day < today {
                    state = .missed
                } else if day > today {
                    state = .upcoming
                } else {
                    state = isReached(slot: slot, now: now, calendar: calendar) ? .due : .upcoming
                }
                out.append(Occurrence(treatment: treatment, day: day, slot: slot,
                                      state: state, completedAt: dose?.loggedAt))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    // MARK: Folds

    /// nil when nothing counted — a fresh item, an as-needed item, a window with no expected day.
    static func consistency(occurrences: [Occurrence]) -> Consistency? {
        let scored = occurrences.filter {
            $0.state == .completed || $0.state == .skipped || $0.state == .missed
        }
        guard !scored.isEmpty else { return nil }
        return Consistency(completed: scored.filter { $0.state == .completed }.count,
                           expected: scored.count)
    }

    /// One treatment over the trailing `windowDays` (today included; the start date clamps it).
    static func consistency(
        treatment: Treatment,
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        windowDays: Int,
        now: Date,
        calendar: Calendar
    ) -> Consistency? {
        guard hasSchedule(treatment) else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else { return nil }
        return consistency(occurrences: occurrences(
            treatment: treatment, doses: doses, missed: missed,
            from: first, through: today, now: now, calendar: calendar
        ))
    }

    /// Every treatment over an explicit day range — the week ribbon and the overall plan rhythm.
    static func consistency(
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        from firstDay: Date,
        through lastDay: Date,
        now: Date,
        calendar: Calendar
    ) -> Consistency? {
        consistency(occurrences: treatments.flatMap {
            occurrences(treatment: $0, doses: doses, missed: missed,
                        from: firstDay, through: lastDay, now: now, calendar: calendar)
        })
    }

    static func today(
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        now: Date,
        calendar: Calendar
    ) -> TodayPlan {
        let day = calendar.startOfDay(for: now)
        let occ = treatments
            .flatMap {
                occurrences(treatment: $0, doses: doses, missed: missed,
                            from: day, through: day, now: now, calendar: calendar)
            }
            .filter { $0.state != .notExpected }
            .sorted { lhs, rhs in
                let l = slotMinutes(lhs.slot) ?? Int.max
                let r = slotMinutes(rhs.slot) ?? Int.max
                if l != r { return l < r }
                return lhs.treatment.name.localizedCaseInsensitiveCompare(rhs.treatment.name) == .orderedAscending
            }
        return TodayPlan(occurrences: occ)
    }

    /// The current calendar week (the calendar's own first weekday), one mark per day.
    static func week(
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        now: Date,
        calendar: Calendar
    ) -> [DayState] {
        let today = calendar.startOfDay(for: now)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        var states: [DayState] = []
        var day = interval.start
        for _ in 0..<7 {
            let occ = treatments
                .flatMap {
                    occurrences(treatment: $0, doses: doses, missed: missed,
                                from: day, through: day, now: now, calendar: calendar)
                }
                .filter { $0.state != .notExpected }
            let expected = occ.count
            let completed = occ.filter { $0.state == .completed }.count
            let mark: DayMark
            if day > today {
                mark = .upcoming
            } else if day == today && expected == 0 {
                // A quiet today still needs its "you are here" outline — decided before the
                // generic expected == 0 → notExpected branch below, or it would disappear.
                mark = .today
            } else if expected == 0 {
                mark = .notExpected
            } else if completed == expected {
                mark = .complete
            } else if day == today {
                mark = .today
            } else if completed > 0 {
                mark = .partial
            } else {
                mark = .missed
            }
            states.append(DayState(day: day, mark: mark, completed: completed, expected: expected))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return states
    }

    // MARK: Slots

    static func slotMinutes(_ slot: String) -> Int? {
        let parts = slot.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// The slot's clock time on `day`'s calendar day; nil for a slotless item.
    static func slotDate(_ slot: String, on day: Date, calendar: Calendar) -> Date? {
        guard let minutes = slotMinutes(slot) else { return nil }
        return calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: day))
    }

    /// True once the slot's clock time has passed today; slotless items are reached all day.
    static func isReached(slot: String, now: Date, calendar: Calendar) -> Bool {
        guard let minutes = slotMinutes(slot) else { return true }
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0) >= minutes
    }
}
