import Foundation

/// Procedure-specific expectation and aftercare guidance for `ProcedureAppointment`s — PRP,
/// microneedling, a hair transplant, LLLT, mesotherapy, and a doctor visit. Mirrors
/// `TreatmentGuide`'s gentle-educator posture: every line is general orientation for a procedure
/// the person already booked or had, never a recommendation to have one, and never a substitute
/// for the clinic's own instructions. `TreatmentGuide.instruction` covers `TreatmentClass` (daily
/// treatments); this covers `ProcedureType` (dated in-clinic events) instead.
enum ProcedureGuide {

    /// One concise line for the booking form (`AddProcedureSheet`) — a same-glance summary of
    /// what's typical, shown as the type chip changes.
    static func shortExpectation(for type: ProcedureType) -> String {
        switch type {
        case .prp:
            return "Typical: mild scalp tenderness for a day or two; results build over a monthly series."
        case .microneedling:
            return "Typical: mild redness for a few hours; effect builds with weekly sessions over months."
        case .transplant:
            return "Typical: shock shedding around weeks 2–8 is expected; results are judged at 12–18 months."
        case .lllt:
            return "Typical: no downtime; effect builds with consistent sessions, not any single one."
        case .mesotherapy:
            return "Typical: mild redness at injection points for a day or two; results build over a series."
        case .consultation:
            return "Bring your recent photos, trends and treatment list — your visit report has all of it."
        case .other:
            return "Recovery and timeline vary by procedure — your clinic's instructions are the best guide."
        }
    }

    /// The fuller paragraph shown in `ProcedureDetailSheet` — what's typical to expect during and
    /// after this kind of procedure, and when it's reasonable to judge results. General
    /// orientation only; the clinic's own timeline and instructions are always the authority.
    static func expectations(for type: ProcedureType) -> String {
        switch type {
        case .prp:
            return "Mild scalp tenderness, redness, or light swelling at the injection sites for a day or two afterward is typical. Results build gradually across a series — most protocols run monthly sessions for the first three months, then space out to maintenance. Judge a series over months, not after one visit."
        case .microneedling:
            return "A little redness or a windburned feeling for a few hours after rolling is common and usually settles by the next day. Like other periodic treatments, microneedling's effect is cumulative — weekly sessions over months, not a single visit, are what studies used."
        case .transplant:
            return "Shock shedding of transplanted hairs — and sometimes nearby native ones — around weeks 2–8 is common and expected; it isn't graft failure. Fine new hairs can start appearing around month 3–4, with continued thickening through the first year. Full results are fairly judged at 12–18 months, not sooner. Your clinic's own timeline and instructions are the authority here — this is general orientation, not a substitute for them."
        case .lllt:
            return "There's typically no downtime — most people resume normal activity right away. Like a daily treatment, LLLT's effect builds with consistent sessions over months rather than any single one."
        case .mesotherapy:
            return "Mild redness, small bumps, or light tenderness at the injection points for a day or two afterward is typical. As with PRP, results build across a series of sessions rather than one visit."
        case .consultation:
            return "Bring your recent photos, trends and treatment list — your visit report has all of it. A dermatologist or GP can look at what's actually changed over time, ask about family history and any triggers you've logged, and decide whether anything (bloodwork, a closer look, a prescription change) is worth doing next. This app's record-keeping doesn't replace their exam or judgment — it just makes the conversation faster."
        case .other:
            return "Recovery and timeline vary by procedure — your clinic's own instructions are the best guide. Logging how you're doing here gives you a record to bring to a follow-up visit."
        }
    }

    /// Typical post-session care points — general practice, not this person's specific discharge
    /// instructions, and always paired with a "follow your clinic" line wherever it's shown.
    static func aftercareNotes(for type: ProcedureType) -> [String] {
        switch type {
        case .prp:
            return [
                "Avoid washing or wetting the treated area for the rest of the day, per typical protocol.",
                "Many clinics suggest skipping NSAIDs like ibuprofen for a day or two around the session — they can blunt the platelet response.",
                "Skip hard workouts or heavy sweating the day of the session.",
            ]
        case .microneedling:
            return [
                "Skip retinoids and other exfoliating actives on the area for 24–48 hours afterward.",
                "Keep the scalp clean and avoid heavy sweating for the rest of the day.",
                "Let any pinpoint redness settle on its own — it's usually gone within a day.",
            ]
        case .transplant:
            return [
                "Avoid direct sun, swimming, and sweat-heavy exercise for the first 10–14 days, per typical clinic guidance.",
                "Sleep slightly elevated for the first few nights if your clinic recommends it — some find it reduces swelling.",
                "Hold off on tight hats, helmets, or hairstyles that press on the grafts until your clinic clears it.",
                "Don't pick at scabs — they typically lift on their own within 7–14 days.",
                "Wash only the way your clinic showed you, on their schedule — this is the one step that varies most by provider.",
            ]
        case .lllt:
            return [
                "No special downtime — most people go straight back to their day.",
                "Consistency across sessions matters far more than any single one.",
            ]
        case .mesotherapy:
            return [
                "Avoid washing the scalp for the rest of the day, per typical clinic guidance.",
                "Mild redness or small bumps at injection points for a day or two is common.",
                "Hold off on hair coloring or other chemical treatments for about a week unless your clinic advises otherwise.",
            ]
        case .consultation:
            return [
                "Pull up or print your visit report before you go — it bundles your summary, trend charts and photos in one document.",
                "Note down your top 2–3 questions ahead of time so they don't get lost once you're in the room.",
                "Bring your current treatment list, including anything over-the-counter, and any past lab results you have.",
                "If anything's changed recently — a new medication, an illness, a stressful stretch — mention it; it can matter more than it seems.",
            ]
        case .other:
            return [
                "Follow the aftercare instructions your clinic gave you for this specific procedure — protocols differ by provider.",
            ]
        }
    }
}

// MARK: - Transplant recovery timeline

/// One week-anchored phase of a typical transplant recovery — a longer, milestone-based arc that
/// replaces the daily-treatment 24-week outcome gate, which doesn't fit a surgical procedure.
struct TransplantMilestone: Identifiable, Sendable, Equatable {
    let id: String
    let weekRange: ClosedRange<Int>
    let title: String
    let body: String
}

extension ProcedureGuide {
    /// Weeks elapsed at which a transplant's results become fair to judge (12–18 months, taken
    /// as ~18 months so the "judging window" tier below spans the full 12–18 month range).
    static let transplantJudgingWindowWeeks = 78

    /// A typical transplant recovery arc, week-anchored to the procedure date. Ranges and framing
    /// follow common clinic literature (graft-security window, weeks-2–8 shock loss, month-3–4
    /// early regrowth, 12–18-month final judging point) — the clinic's own timeline always wins
    /// over this general orientation.
    static let transplantTimeline: [TransplantMilestone] = [
        TransplantMilestone(id: "graft-security", weekRange: 0...2,
            title: "Graft security window",
            body: "Grafts are anchoring into the scalp. Gentle handling and washing exactly the way your clinic showed you matter most right now."),
        TransplantMilestone(id: "shock-loss", weekRange: 3...8,
            title: "Shock shedding (expected)",
            body: "Many transplanted hairs — and sometimes nearby native ones — shed in this window. This is a normal, expected phase, not a sign the graft failed."),
        TransplantMilestone(id: "early-regrowth", weekRange: 9...16,
            title: "Early regrowth",
            body: "Fine new hairs can start appearing for some people, though timing varies widely. Seeing little yet is still normal here."),
        TransplantMilestone(id: "thickening", weekRange: 17...26,
            title: "Visible thickening",
            body: "New hairs continue emerging and thickening. Density is still building, not final."),
        TransplantMilestone(id: "maturing", weekRange: 27...52,
            title: "Continued maturation",
            body: "Growth and thickness keep progressing through the rest of the first year."),
        TransplantMilestone(id: "judging-window", weekRange: 53...transplantJudgingWindowWeeks,
            title: "Results judging window",
            body: "Most clinics consider 12–18 months the fair point to judge the final result."),
        TransplantMilestone(id: "settled", weekRange: (transplantJudgingWindowWeeks + 1)...Int.max,
            title: "Past the judging window",
            body: "Results are typically settled by now. Keep tracking for your own long-term record."),
    ]

    /// The recovery phase a given week count falls into.
    static func transplantMilestone(weeksElapsed: Int) -> TransplantMilestone {
        transplantTimeline.first { $0.weekRange.contains(weeksElapsed) } ?? transplantTimeline[transplantTimeline.count - 1]
    }
}
