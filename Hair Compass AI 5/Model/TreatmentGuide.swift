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
        case .spironolactone:
            return "Take as prescribed at the same time each day, with food if it upsets your stomach. It's prescription-only and specialist-guided — dose, monitoring, and duration are your prescriber's call, not this app's."
        case .microneedling:
            return "Roll gently over the target area on clean skin, usually about once a week, and let the scalp recover between sessions. Avoid combining with actives the same night unless advised."
        case .prp:
            return "Done in-clinic on the schedule your provider sets (often monthly at first). Log each session so the 24-week clock stays accurate."
        case .lllt:
            return "Use the device for the recommended session length on the recommended days. Regular, consistent sessions matter more than long occasional ones."
        case .shampoo:
            return "Massage into a wet scalp and, if it's a treatment shampoo, leave it on a few minutes before rinsing. Two to three times a week is typical — follow the product's label."
        case .oil:
            return "Massage a small amount into the scalp, often a few evenings a week. More isn't better, and an oil is a comfort step, not a proven regrowth treatment — follow the product's guidance."
        case .supplement:
            return "Take with water at the same time each day. Supplements help hair mainly when something is genuinely low (like iron or vitamin D) — they aren't a substitute for proven treatments."
        case .other:
            return "Follow the routine you and your clinician agreed on, and log it so your adherence and the 24-week window stay accurate."
        }
    }
}

// MARK: - What to expect (educational, per treatment class)

/// Mirrors `ProcedureGuide`'s expectation-management posture, applied to daily treatments instead
/// of dated procedures: the abandonment risk here isn't a bad reaction, it's quitting mid-trial
/// during a normal, expected phase (minoxidil's early shed, an SRI's slow onset) mistaken for
/// failure. Every line is general orientation for a treatment the person already chose, never a
/// reason to start or stop one, and never a substitute for the prescriber's own guidance.
extension TreatmentGuide {
    /// One concise line for the "Type" picker in `AddTreatmentSheet` — a same-glance summary of
    /// what's typical, shown as the class chip changes. Mirrors `ProcedureGuide.shortExpectation`.
    static func shortExpectation(for c: TreatmentClass) -> String {
        switch c {
        case .minoxidil:
            return "Typical: a temporary shed weeks 2–8 is common; results are judged at 24 weeks."
        case .finasteride, .dutasteride:
            return "Typical: little visible before 3–6 months; the full effect can take up to a year."
        case .spironolactone:
            return "Typical: 6+ months to a clear change, with prescriber-monitored bloodwork."
        case .microneedling:
            return "Typical: an adjunct — effect builds with weekly sessions over months."
        case .prp:
            return "Typical: mild tenderness after a session; results build over a monthly series."
        case .lllt:
            return "Typical: about 3 sessions a week for 16–26 weeks before judging."
        case .shampoo:
            return "Typical: scalp symptoms ease within weeks; any density effect is a slow adjunct."
        case .oil:
            return "Typical: a comfort and scalp-care step, not a proven regrowth treatment."
        case .supplement:
            return "Typical: helps only when a lab-confirmed deficiency is what's actually low."
        case .other:
            return "Typical: follow the plan you and your clinician agreed on."
        }
    }

    /// A short cadence hint for the "Days" section in `AddTreatmentSheet`/`TreatmentDetailSheet`,
    /// shown above the weekday picker for the home-use device classes — the ones that just gained
    /// a schedule and whose evidence-backed rhythm isn't obvious the way "a few times a week" is
    /// for shampoo. nil for classes without a distinct cadence to call out; the generic
    /// "every day / selected days" line below the picker already covers those. Same
    /// gentle-educator posture as `shortExpectation`/`expectations` — a typical practice, never a
    /// prescription.
    static func scheduleHint(for c: TreatmentClass) -> String? {
        switch c {
        case .microneedling:
            return "Microneedling is typically done about weekly."
        case .lllt:
            return "LLLT devices are commonly used a few times a week."
        default:
            return nil
        }
    }

    /// The fuller paragraph shown in `TreatmentDetailSheet`'s "What to expect" card — what's
    /// typical during the early weeks, how results build, and when it's fair to judge. General
    /// orientation only; the prescriber's own instructions are always the authority.
    static func expectations(for c: TreatmentClass) -> String {
        switch c {
        case .minoxidil:
            return "A temporary increase in shedding around weeks 2–8 is common, and is often a sign minoxidil is pushing resting follicles into a fresh growth cycle rather than a sign it's failing. Visible density gains, when they happen, usually take until around week 24 to become clear — the standard point trials judge results at. Stopping partway through, especially during the early shed, ends the trial before it's had a chance to show anything, and any gains already made typically fade within months of stopping."
        case .finasteride, .dutasteride:
            return "These work slowly — little is usually visible before 3 to 6 months, and the fuller effect keeps building for up to a year. A flat result in the first weeks isn't a fair read yet. Follow your prescriber's monitoring schedule; they set the actual duration."
        case .spironolactone:
            return "Like other hormonal treatments, spironolactone works slowly — most people don't see a clear change before 6 months. It also needs prescriber-monitored bloodwork (electrolytes, blood pressure) along the way. Dose, duration and monitoring are entirely your prescriber's call, not this app's."
        case .microneedling:
            return "Microneedling is typically used as an adjunct alongside a primary treatment rather than on its own, and its effect builds with weekly sessions over months, not any single one. Judge it on the same 24-week clock as whatever it's supporting."
        case .prp:
            return "Mild scalp tenderness for a day or two after a session is typical. Results build gradually across a series — most protocols run monthly for the first three months, then space out. Judge a series over months, not after one visit."
        case .lllt:
            return "Low-level laser needs consistency more than any single session — studies used about 3 sessions a week for 16 to 26 weeks before judging results. Skipping sessions, or judging early, is a common reason people give up before it's had a fair trial."
        case .shampoo:
            return "A medicated scalp shampoo (like ketoconazole) typically calms itching, flaking or oiliness within a couple of weeks. Any effect on density is a slower, secondary benefit — best thought of as an adjunct to a primary treatment, not a treatment on its own."
        case .oil:
            return "A scalp oil is a comfort and scalp-care step, not a proven regrowth treatment — there's no established trial timeline to judge it against. Use it for how it feels, and rely on an evidence-based treatment for density."
        case .supplement:
            return "A supplement meaningfully helps hair only when it corrects a lab-confirmed deficiency, like low ferritin or vitamin D. Taking one when your levels are already normal adds no benefit, and in some cases (like excess vitamin A) can cause the very shedding it's meant to fix. Test before you judge it."
        case .other:
            return "Follow the routine you and your clinician agreed on. Most hair treatments need months of consistent use before it's fair to judge them — log doses here so your own timeline stays accurate."
        }
    }

    /// A week-anchored line for the treatment's own phase right now, for the classes with a
    /// well-known early-shed or slow-onset window worth calling out by name. Returns nil once a
    /// class has settled into its steady "just keep going" phase, or never had a distinct phase to
    /// begin with — `expectations(for:)` already says enough there.
    static func phase(for c: TreatmentClass, weeksElapsed w: Int) -> String? {
        switch c {
        case .minoxidil:
            if w < 2 {
                return "Week \(w) — just getting started. It's normal to see nothing at all yet."
            } else if w <= 8 {
                return "Week \(w) — inside the early-shed window; a temporary shed now is common, not failure."
            } else if w < 24 {
                return "Week \(w) — past the early-shed window; density gains, if any, build gradually from here to week 24."
            } else {
                return "Week \(w) — past the 24-week judging point. If it's working, it's usually visible by now."
            }
        case .finasteride, .dutasteride:
            if w < 12 {
                return "Week \(w) — still early; little is usually visible before 3 months in trials."
            } else if w < 24 {
                return "Week \(w) — some notice a first difference around now; the fuller effect keeps building for months yet."
            } else {
                return "Week \(w) — past the app's 24-week checkpoint. The full effect can keep building for up to a year, so a flat result now isn't the final word."
            }
        case .spironolactone:
            if w < 24 {
                return "Week \(w) — still inside the typical 6-month window before a change is usually clear."
            } else {
                return "Week \(w) — past the point most people start to see a change, with your prescriber tracking labs alongside it."
            }
        case .lllt:
            if w < 16 {
                return "Week \(w) — inside the build-up window; studies used 3 sessions a week for 16 to 26 weeks before judging."
            } else if w <= 26 {
                return "Week \(w) — inside the studied judging window (16–26 weeks); close to a fair read if sessions have stayed consistent."
            } else {
                return "Week \(w) — past the studied window. Consistency from here matters more than any single session."
            }
        case .microneedling:
            if w < 24 {
                return "Week \(w) — building toward the 24-week judging point, same as whatever primary treatment it's supporting."
            } else {
                return "Week \(w) — past 24 weeks; judge it alongside whatever primary treatment it's supporting."
            }
        case .shampoo:
            return w < 4 ? "Week \(w) — scalp symptoms like itching or flaking, if present, often ease within the first few weeks." : nil
        case .prp, .oil, .supplement, .other:
            return nil
        }
    }
}

// MARK: - Common regimen presets (one-tap prefill, never auto-applied)

/// A common, evidence-based regimen for a treatment class, offered as a one-tap prefill in the
/// Add Treatment sheet. Strictly descriptive — "a common regimen", never a prescription: the UI
/// always says to confirm with the prescriber, applying one takes an explicit tap, and every
/// prefilled field stays freely editable afterwards.
struct DosePreset: Identifiable, Sendable, Equatable {
    let label: String          // chip title, e.g. "Topical 5%"
    let name: String           // prefills the treatment name
    let dose: String           // prefills the dose field
    let scheduleTimes: String  // "08:00,21:00" comma-separated; "" = periodic
    let note: String           // one short honest caveat, e.g. "once daily is common for women"

    var id: String { "\(label)|\(name)" }

    /// Slots parsed with the same rule as `Treatment.slots`' explicit parse.
    var slots: [String] {
        scheduleTimes
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Short chip subtitle, e.g. "1 mL · 2×/day" or "per clinic protocol · periodic".
    var summary: String {
        let cadence: String
        switch slots.count {
        case 0: cadence = "periodic"
        case 1: cadence = "1×/day"
        default: cadence = "\(slots.count)×/day"
        }
        return dose.isEmpty ? cadence : "\(dose) · \(cadence)"
    }
}

extension TreatmentGuide {
    /// Common regimens per class — the doses/cadences the trials actually used. `.other`
    /// deliberately has none: there is nothing honest to suggest for an unknown treatment.
    static func presets(for c: TreatmentClass) -> [DosePreset] {
        switch c {
        case .minoxidil: return [
            DosePreset(label: "Topical 5%", name: "Minoxidil 5%", dose: "1 mL",
                       scheduleTimes: "08:00,21:00",
                       note: "Twice daily; once daily is common for women."),
            DosePreset(label: "Oral low-dose", name: "Minoxidil (oral, low-dose)", dose: "2.5 mg",
                       scheduleTimes: "21:00",
                       note: "Prescription-only route, taken once nightly."),
        ]
        case .finasteride: return [
            DosePreset(label: "Standard 1 mg", name: "Finasteride", dose: "1 mg",
                       scheduleTimes: "21:00",
                       note: "Once daily, same time each day."),
        ]
        case .dutasteride: return [
            DosePreset(label: "Standard 0.5 mg", name: "Dutasteride", dose: "0.5 mg",
                       scheduleTimes: "21:00",
                       note: "Once daily, same time each day."),
        ]
        case .spironolactone: return [
            DosePreset(label: "Common 100 mg", name: "Spironolactone", dose: "100 mg",
                       scheduleTimes: "08:00",
                       note: "Doses vary 50–200 mg — confirm yours with your prescriber."),
        ]
        case .microneedling: return [
            DosePreset(label: "Weekly session", name: "Microneedling", dose: "0.5–1.5 mm",
                       scheduleTimes: "",
                       note: "Weekly is the studied cadence."),
        ]
        case .prp: return [
            DosePreset(label: "Clinic series", name: "PRP", dose: "per clinic protocol",
                       scheduleTimes: "",
                       note: "Typically monthly ×3, then maintenance."),
        ]
        case .lllt: return [
            DosePreset(label: "Home device", name: "Low-level laser", dose: "10–20 min session",
                       scheduleTimes: "",
                       note: "3×/week in studies."),
        ]
        case .shampoo: return [
            DosePreset(label: "Ketoconazole 2%", name: "Ketoconazole 2% shampoo", dose: "Lather 2\u{2013}3\u{00d7}/week, leave 3\u{2013}5 min",
                       scheduleTimes: "",
                       note: "A studied anti-dandruff shampoo strength — often sold behind the pharmacy counter."),
        ]
        case .oil, .supplement: return []   // OTC products carry no standard "regimen"
        case .other: return []
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
        } else if totalToday > 0, doneToday >= totalToday {
            detail = "All \(totalToday) step\(totalToday == 1 ? " is" : "s are") complete. Your plan is set for today."
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
