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

// MARK: - Catalogue content for the in-clinic options screen

/// What each procedure *is*, how strong the evidence for it is, and how often it's typically done.
///
/// `ProcedureGuide`'s original members answer "I've booked this — what happens after?".
/// These answer "what is this, and is it worth asking my clinician about?" — the browsing case
/// the in-clinic options screen serves.
///
/// The posture is unchanged and load-bearing: **education, never a recommendation to undergo.**
/// Evidence grades are deliberately conservative and describe the *state of the literature for
/// androgenetic hair loss*, not a prediction for any individual. They must not be inflated to make
/// the screen more exciting — `.weak` on mesotherapy is the honest reading and it stays.
extension ProcedureGuide {

    /// One plain sentence: what the procedure actually involves.
    static func summary(for type: ProcedureType) -> String {
        switch type {
        case .prp:
            return "A sample of your own blood is spun to concentrate its platelets, then injected into the thinning areas of the scalp."
        case .microneedling:
            return "Fine needles make controlled micro-injuries in the scalp to prompt a repair response. Most often used alongside minoxidil rather than on its own."
        case .transplant:
            return "Follicles are moved from a denser donor area to thinning areas. It redistributes the hair you have — it doesn't create new hair."
        case .lllt:
            return "Red-light devices — caps, combs or helmets — used on a regular schedule, at home or in clinic."
        case .mesotherapy:
            return "Injections of vitamin, drug or nutrient mixtures into the scalp. Formulations vary widely between clinics and aren't standardised."
        case .consultation:
            return "A dermatologist or GP examines your scalp, reviews your history, and decides what — if anything — is worth doing next."
        case .other:
            return "Anything else a clinic offers that isn't listed here."
        }
    }

    /// How strong the published evidence is *for hair loss*, using the app's shared vocabulary so
    /// a procedure is graded on the same scale as everything else the app rates.
    static func evidence(for type: ProcedureType) -> EvidenceTier {
        switch type {
        case .transplant:
            // Long-established surgical redistribution with predictable results in suitable
            // candidates — the strongest evidence base of anything on this list.
            return .strong
        case .prp, .microneedling, .lllt:
            // All three have randomised trials showing benefit, but with small samples and
            // inconsistent protocols between studies. Genuinely promising, not settled.
            return .moderate
        case .mesotherapy:
            // Little good-quality evidence, and no standard formulation to study. Graded honestly
            // even though it is widely sold.
            return .weak
        case .consultation, .other:
            // Not treatments, so not evidence-graded — context for the rest of the list.
            return .context
        }
    }

    /// The typical rhythm, phrased as a range because protocols genuinely differ between clinics.
    static func cadence(for type: ProcedureType) -> String? {
        switch type {
        case .prp: return "Often monthly for 3 sessions, then maintenance"
        case .microneedling: return "Weekly to fortnightly, over months"
        case .transplant: return "One or two sessions · judged at 12–18 months"
        case .lllt: return "Several short sessions a week, ongoing"
        case .mesotherapy: return "A series of sessions · protocol varies widely"
        case .consultation: return "As needed"
        case .other: return nil
        }
    }

    /// The single most useful caution for someone considering this — the thing worth raising with
    /// a clinician before agreeing to it. `nil` where there's nothing specific to flag.
    static func caution(for type: ProcedureType) -> String? {
        switch type {
        case .prp:
            return "Protocols and costs vary a lot between clinics, and a series is usually needed before anything can be judged."
        case .microneedling:
            return "Needle depth matters, and at-home rollers carry an infection risk if they aren't kept clean."
        case .transplant:
            return "It moves existing hair rather than adding any, so ongoing loss elsewhere usually still needs treating. Donor supply is finite."
        case .lllt:
            return "Effects are modest and depend on using the device consistently for months."
        case .mesotherapy:
            return "Because mixtures aren't standardised, ask exactly what's being injected and why."
        case .consultation, .other:
            return nil
        }
    }

    /// The order the catalogue lists them in: strongest evidence first, with the two non-treatment
    /// entries last, so the screen never leads with the weakest option.
    static var catalogueOrder: [ProcedureType] {
        [.transplant, .prp, .microneedling, .lllt, .mesotherapy, .consultation, .other]
    }
}
