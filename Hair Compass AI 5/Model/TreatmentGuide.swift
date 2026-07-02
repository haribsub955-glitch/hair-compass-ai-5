import Foundation
import SwiftData

/// Turns the user's own treatments into a daily routine, adds non-prescriptive application
/// guidance, and coaches adherence. Gentle-educator posture: guidance is for treatments the person
/// already chose to add ("typical practice — follow your label and clinician"), never a
/// recommendation to start something.

// MARK: - Application guidance (educational, per treatment type)

enum TreatmentGuide {
    static func instruction(for c: TreatmentClass) -> String {
        switch c {
        case .minoxidil:
            return "Apply to a dry scalp over the thinning area, then wash your hands and let it dry fully. Consistency matters more than amount — follow your product's label."
        case .finasteride:
            return "Take one tablet at the same time each day, with or without food. Daily consistency is what makes it work; skipping days blunts the effect. Follow your prescriber's directions."
        case .dutasteride:
            return "Take as prescribed at the same time each day. Like finasteride, steady daily use is what counts. Follow your prescriber's directions."
        case .microneedling:
            return "Roll gently over the target area on clean skin, usually about once a week, and let the scalp recover between sessions. Avoid combining with actives the same night unless advised."
        case .prp:
            return "Done in-clinic on the schedule your provider sets (often monthly at first). Log each session so the 24-week clock stays accurate."
        case .lllt:
            return "Use the device for the recommended session length on the recommended days. Regular, consistent sessions matter more than long occasional ones."
        case .other:
            return "Follow the routine you and your clinician agreed on, and log it so your adherence and the 24-week window stay accurate."
        }
    }
}

// MARK: - Daily routine

struct RoutineStep: Identifiable, Sendable, Equatable {
    let id: String
    let treatmentName: String
    let symbol: String
    let slot: String          // "08:00", or "" for periodic
    let instruction: String
    var done: Bool
}

enum RoutineBlock: String, CaseIterable, Identifiable, Sendable {
    case morning, evening, periodic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .morning: return "Morning"
        case .evening: return "Evening"
        case .periodic: return "Periodic"
        }
    }
    var symbol: String {
        switch self {
        case .morning: return "sunrise"
        case .evening: return "moon.stars"
        case .periodic: return "calendar"
        }
    }

    /// Slots before noon are morning, noon and later are evening; empty slot = periodic.
    static func block(for slot: String) -> RoutineBlock {
        guard let hour = Int(slot.split(separator: ":").first.map(String.init) ?? "") else { return .periodic }
        return hour < 12 ? .morning : .evening
    }
}

/// Pure grouping used by both the app and the tests.
struct RoutinePlanner {
    /// - Parameter loggedSlots: set of "treatmentID|slot" strings already logged today.
    static func steps(
        treatments: [(id: String, name: String, symbol: String, slots: [String], isActive: Bool, treatmentClass: TreatmentClass)],
        loggedSlots: Set<String>
    ) -> [RoutineBlock: [RoutineStep]] {
        var grouped: [RoutineBlock: [RoutineStep]] = [:]
        for t in treatments where t.isActive {
            let instruction = TreatmentGuide.instruction(for: t.treatmentClass)
            if t.slots.isEmpty {
                let step = RoutineStep(id: "\(t.id)|", treatmentName: t.name, symbol: t.symbol,
                                       slot: "", instruction: instruction, done: false)
                grouped[.periodic, default: []].append(step)
            } else {
                for slot in t.slots {
                    let key = "\(t.id)|\(slot)"
                    let step = RoutineStep(id: key, treatmentName: t.name, symbol: t.symbol,
                                           slot: slot, instruction: instruction, done: loggedSlots.contains(key))
                    grouped[RoutineBlock.block(for: slot), default: []].append(step)
                }
            }
        }
        return grouped
    }

    /// Count of daily (non-periodic) steps and how many are done — the adherence-for-today ratio.
    static func dailyProgress(_ grouped: [RoutineBlock: [RoutineStep]]) -> (done: Int, total: Int) {
        let daily = (grouped[.morning] ?? []) + (grouped[.evening] ?? [])
        return (daily.filter(\.done).count, daily.count)
    }
}

// MARK: - Adherence coach (deterministic)

struct CoachMessage: Equatable {
    let headline: String
    let detail: String
}

enum AdherenceCoach {
    static func message(doneToday: Int, totalToday: Int, streak: Int, weeklyAdherence: Double?) -> CoachMessage {
        let headline: String
        if totalToday == 0 {
            headline = streak > 0 ? "You're on a \(streak)-day streak" : "Let's start your routine"
        } else if doneToday >= totalToday {
            headline = "Today's routine is done"
        } else {
            let left = totalToday - doneToday
            headline = "\(left) step\(left == 1 ? "" : "s") left today"
        }

        let detail: String
        if streak >= 3 {
            detail = "\(streak)-day streak — consistency is the single biggest thing you control."
        } else if let w = weeklyAdherence, totalToday > 0 {
            detail = "\(Int((w * 100).rounded()))% of this week's steps done. Keep it steady."
        } else if totalToday > 0 {
            detail = "Small daily reps beat perfect occasional effort. Check them off as you go."
        } else {
            detail = "Add a treatment to build your daily routine and start a streak."
        }
        return CoachMessage(headline: headline, detail: detail)
    }
}

// MARK: - Milestones

struct Milestone: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let symbol: String
}

enum Milestones {
    static let streakThresholds = [3, 7, 14, 30, 60, 100]

    /// Achieved milestones, most salient first — a reached streak tier and any treatment that has
    /// crossed the halfway (12-week) or 24-week judging marks.
    static func achieved(streak: Int, treatments: [(name: String, weeks: Int)]) -> [Milestone] {
        var out: [Milestone] = []
        for t in treatments where t.weeks >= 24 {
            out.append(Milestone(id: "ready-\(t.name)", title: "\(t.name): 24 weeks reached",
                                 body: "You've hit the point where results become fair to judge. Compare your photos and trends now.",
                                 symbol: "checkmark.seal"))
        }
        if let tier = streakThresholds.last(where: { streak >= $0 }) {
            out.append(Milestone(id: "streak-\(tier)", title: "\(tier)-day streak",
                                 body: nextStreakLine(current: streak),
                                 symbol: "flame"))
        }
        for t in treatments where t.weeks >= 12 && t.weeks < 24 {
            out.append(Milestone(id: "half-\(t.name)", title: "\(t.name): halfway there",
                                 body: "Week \(t.weeks) of 24 — you're past the halfway mark. Keep going before judging results.",
                                 symbol: "hourglass"))
        }
        return out
    }

    private static func nextStreakLine(current: Int) -> String {
        if let next = streakThresholds.first(where: { $0 > current }) {
            return "Next milestone: \(next) days. \(next - current) to go."
        }
        return "You've passed every streak milestone — remarkable consistency."
    }
}

// MARK: - Main-actor adapter over SwiftData

enum RoutineService {
    @MainActor
    static func todaysRoutine(
        treatments: [Treatment],
        doses: [TreatmentDose],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [RoutineBlock: [RoutineStep]] {
        let loggedSlots: Set<String> = Set(
            doses.filter { calendar.isDate($0.loggedAt, inSameDayAs: now) }
                .compactMap { dose -> String? in
                    guard let t = dose.treatment else { return nil }
                    return "\(t.persistentModelID.hashValue)|\(dose.slot)"
                }
        )
        let mapped = treatments.map { t in
            (id: String(t.persistentModelID.hashValue), name: t.name.isEmpty ? t.treatmentClass.title : t.name,
             symbol: t.treatmentClass.symbol, slots: t.slots, isActive: t.isActive, treatmentClass: t.treatmentClass)
        }
        return RoutinePlanner.steps(treatments: mapped, loggedSlots: loggedSlots)
    }
}
