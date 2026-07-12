import Foundation

// Domain vocabulary. Every case here maps to a verified finding in docs/TrackingSpec.md.

enum HairCondition: String, Codable, CaseIterable, Identifiable {
    case androgenetic
    case alopeciaAreata
    case telogenEffluvium
    case traction
    case seborrheicDermatitis
    case unsure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .androgenetic: return "Androgenetic"
        case .alopeciaAreata: return "Alopecia areata"
        case .telogenEffluvium: return "Telogen effluvium"
        case .traction: return "Traction"
        case .seborrheicDermatitis: return "Seborrheic dermatitis"
        case .unsure: return "Not sure yet"
        }
    }

    var shortLabel: String {
        switch self {
        case .androgenetic: return "AGA"
        case .alopeciaAreata: return "AA"
        case .telogenEffluvium: return "TE"
        case .traction: return "Traction"
        case .seborrheicDermatitis: return "SD"
        case .unsure: return "Unsure"
        }
    }

    var summary: String {
        switch self {
        case .androgenetic: return "Pattern thinning driven by genetics and hormones."
        case .alopeciaAreata: return "Patchy, immune-related loss. Trichoscopy signs matter."
        case .telogenEffluvium: return "Diffuse shedding, usually after a trigger."
        case .traction: return "Tension-driven loss along the hairline."
        case .seborrheicDermatitis: return "Flaking, redness and itch of the scalp."
        case .unsure: return "Track broadly until a pattern is clear."
        }
    }

    /// Whether the seborrheic-dermatitis 16-point scalp scale is the headline metric.
    var usesScalpScale: Bool { self == .seborrheicDermatitis }

    /// Plain-language title for onboarding's "what are you noticing?" step — the clinical
    /// `title` stays the source of truth for charts and Care and is shown demoted alongside this.
    var plainTitle: String {
        switch self {
        case .androgenetic: return "Gradual thinning in a pattern"
        case .alopeciaAreata: return "Smooth round patches"
        case .telogenEffluvium: return "Sudden shedding all over"
        case .traction: return "Loss where hair is pulled tight"
        case .seborrheicDermatitis: return "Flaky, itchy scalp"
        case .unsure: return "Not sure yet"
        }
    }

    /// Plain-language summary shown under `plainTitle` in onboarding.
    var plainSummary: String {
        switch self {
        case .androgenetic: return "Slow thinning at the hairline, crown, or part — the most common kind."
        case .alopeciaAreata: return "Smooth, coin-sized bald patches that can show up fast."
        case .telogenEffluvium: return "Lots of extra shedding all over, often after stress or illness."
        case .traction: return "Thinning where hair is pulled tight — braids, buns, ponytails."
        case .seborrheicDermatitis: return "A flaky, itchy, sometimes red scalp."
        case .unsure: return "Not sure yet? We'll track broadly until a pattern shows."
        }
    }

    /// One plain line describing what the demo animation is showing.
    var demoCaption: String {
        switch self {
        case .androgenetic: return "What you're seeing: the crown slowly thinning."
        case .alopeciaAreata: return "What you're seeing: a smooth patch appear, then regrow."
        case .telogenEffluvium: return "What you're seeing: extra hairs shedding all over."
        case .traction: return "What you're seeing: a strand strained where it's pulled."
        case .seborrheicDermatitis: return "What you're seeing: flakes lifting from an itchy scalp."
        case .unsure: return "We'll help you find your pattern as you track."
        }
    }
}

enum FamilyHistory: String, Codable, CaseIterable, Identifiable {
    case none, oneParent, bothParents, extended
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None known"
        case .oneParent: return "One parent"
        case .bothParents: return "Both parents"
        case .extended: return "Extended family"
        }
    }

    /// Odds ratios from the 2026 AGA meta-analysis (presence OR 2.72). Used only to
    /// order the baseline risk readout — never to predict an individual outcome.
    var riskWeight: Int {
        switch self {
        case .none: return 0
        case .oneParent: return 2
        case .bothParents: return 3
        case .extended: return 1
        }
    }
}

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        }
    }
    /// Norwood staging for male-pattern, Ludwig for female-pattern.
    var stagingScaleName: String { self == .female ? "Ludwig" : "Norwood" }
}

/// Whether the person is pregnant or planning/expecting — asked once during onboarding (women
/// only) so the app can flag hair-loss medications that are usually avoided in and around
/// pregnancy. Self-reported context for a safety nudge, never a diagnosis or a directive.
enum PregnancyStatus: String, Codable, CaseIterable, Identifiable {
    case unspecified, no, pregnant, tryingToConceive, breastfeeding
    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified: return "Prefer not to say"
        case .no: return "No"
        case .pregnant: return "Yes, I'm pregnant"
        case .tryingToConceive: return "Trying to conceive"
        case .breastfeeding: return "Breastfeeding"
        }
    }

    /// True in the states where medications that aren't recommended in or around pregnancy
    /// should be flagged. "No" and "Prefer not to say" never raise a caution.
    var flagsMedicationCaution: Bool {
        switch self {
        case .pregnant, .tryingToConceive, .breastfeeding: return true
        case .unspecified, .no: return false
        }
    }
}

enum ShedLevel: Int, Codable, CaseIterable, Identifiable {
    case minimal = 0, normal = 1, elevated = 2, heavy = 3
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .minimal: return "Minimal"
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .heavy: return "Heavy"
        }
    }
    var caption: String {
        switch self {
        case .minimal: return "A few strands"
        case .normal: return "Typical daily shed"
        case .elevated: return "More than usual"
        case .heavy: return "Clumps / handfuls"
        }
    }
}

enum TreatmentClass: String, Codable, CaseIterable, Identifiable {
    // Medications, then in-office/device work, then over-the-counter care products, then a
    // free-form catch-all. `classRaw` is stored as a String, so appending cases needs no schema
    // migration — existing rows keep their raw value and only new entries can pick the new ones.
    case minoxidil, finasteride, dutasteride, microneedling, prp, lllt, shampoo, oil, supplement, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .minoxidil: return "Minoxidil"
        case .finasteride: return "Finasteride"
        case .dutasteride: return "Dutasteride"
        case .microneedling: return "Microneedling"
        case .prp: return "PRP"
        case .lllt: return "Low-level laser"
        case .shampoo: return "Shampoo"
        case .oil: return "Oil / serum"
        case .supplement: return "Supplement"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .minoxidil: return "drop.fill"
        case .finasteride, .dutasteride: return "pills.fill"
        case .microneedling: return "circle.grid.cross.fill"
        case .prp: return "syringe.fill"
        case .lllt: return "light.max"
        case .shampoo: return "bubbles.and.sparkles.fill"
        case .oil: return "drop.halffull"
        case .supplement: return "leaf.fill"
        case .other: return "cross.case.fill"
        }
    }

    /// Whether the item is a daily-adherence step (has clock times) or a periodic one that lives
    /// under "As scheduled". Shampoos and oils are used a few times a week, not on a clock, so
    /// they are periodic; a supplement is a once-a-day habit like the oral medications.
    var defaultDailyCount: Int {
        switch self {
        case .minoxidil: return 2
        case .finasteride, .dutasteride, .supplement: return 1
        default: return 0 // periodic, not daily (shampoo, oil, procedures, other)
        }
    }

    var isDaily: Bool { defaultDailyCount > 0 }

    /// True for the over-the-counter care products — used by the add form to reframe "Dose" as
    /// "Amount" and to offer product-appropriate placeholders instead of medication ones.
    var isCareProduct: Bool {
        switch self {
        case .shampoo, .oil, .supplement: return true
        default: return false
        }
    }
}

/// Pragmatic, class-agnostic tolerability vocabulary. Covers the common minoxidil
/// (irritation, swelling, dizziness) and finasteride/dutasteride (sexual, mood) reports
/// without pretending to be a medical taxonomy.
enum SideEffectType: String, Codable, CaseIterable, Identifiable {
    case scalpIrritation, itching, dizziness, headache, sexual, mood, swelling, shedding, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .scalpIrritation: return "Scalp irritation"
        case .itching: return "Itching"
        case .dizziness: return "Dizziness"
        case .headache: return "Headache"
        case .sexual: return "Sexual side effect"
        case .mood: return "Mood change"
        case .swelling: return "Swelling"
        case .shedding: return "Shedding flare"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .scalpIrritation: return "flame"
        case .itching: return "hand.raised.fingers.spread"
        case .dizziness: return "tornado"
        case .headache: return "brain.head.profile"
        case .sexual: return "heart.slash"
        case .mood: return "cloud.rain"
        case .swelling: return "bandage"
        case .shedding: return "wind"
        case .other: return "exclamationmark.circle"
        }
    }

    /// Honest context shown in the log form — only where it genuinely reassures.
    var caption: String? {
        self == .shedding ? "Often transient early on" : nil
    }
}

/// How pressing a refill is, banded from days remaining. Pure display vocabulary —
/// the banding math lives in `HairAnalytics.refillUrgency`.
enum RefillUrgency {
    case none, ok, soon, urgent, overdue
}

enum LabTest: String, Codable, CaseIterable, Identifiable {
    // Round-5 addition: zinc, hemoglobin, total testosterone and DHEA-S — the rest of a
    // standard hair-loss workup (CBC/iron studies and the female-pattern-loss androgen panel)
    // that a five-test vocabulary couldn't hold.
    case ferritin, tsh, freeT4, vitaminD, vitaminB12, zinc, hemoglobin, totalTestosterone, dheaS
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ferritin: return "Ferritin"
        case .tsh: return "TSH"
        case .freeT4: return "Free T4"
        case .vitaminD: return "Vitamin D (25-OH)"
        case .vitaminB12: return "Vitamin B12"
        case .zinc: return "Zinc"
        case .hemoglobin: return "Hemoglobin"
        case .totalTestosterone: return "Total testosterone"
        case .dheaS: return "DHEA-S"
        }
    }

    var unit: String {
        switch self {
        case .ferritin: return "ng/mL"
        case .tsh: return "mIU/L"
        case .freeT4: return "ng/dL"
        case .vitaminD: return "ng/mL"
        case .vitaminB12: return "pg/mL"
        case .zinc: return "mcg/dL"
        case .hemoglobin: return "g/dL"
        case .totalTestosterone: return "ng/dL"
        case .dheaS: return "mcg/dL"
        }
    }

    /// Common adult reference ranges. Flags below/above for context only — never diagnosis.
    var referenceRange: ClosedRange<Double> {
        switch self {
        case .ferritin: return 30...300      // hair-relevant floor often cited ~30–40
        case .tsh: return 0.4...4.0
        case .freeT4: return 0.8...1.8
        case .vitaminD: return 30...100
        case .vitaminB12: return 200...900
        case .zinc: return 70...120
        // Spans both sexes loosely — hemoglobin's real range is sex-specific (roughly
        // 13.5–17.5 g/dL men, 12.0–15.5 g/dL women). Use the per-result override for a
        // precise read; this default only catches a clearly abnormal value either way.
        case .hemoglobin: return 12.0...17.5
        // Testosterone and DHEA-S are ordered here mainly for a female-pattern-loss workup —
        // the default shown is a typical adult FEMALE range. A male result should always use
        // the range printed on the lab report (the per-result override below), not this default.
        case .totalTestosterone: return 15...70
        case .dheaS: return 65...380
        }
    }

    var note: String {
        switch self {
        case .ferritin: return "Iron stores. Low ferritin is linked to telogen effluvium."
        case .tsh, .freeT4: return "Thyroid function — a treatable shedding driver."
        case .vitaminD: return "Order when clinically indicated, not by default."
        case .vitaminB12: return "Checked selectively; deficiency is uncommon."
        case .zinc: return "Supports hair-follicle function; deficiency is uncommon without a dietary or absorption cause."
        case .hemoglobin: return "Part of a CBC/iron workup. Default range spans both sexes — use your lab's own range for a precise read."
        case .totalTestosterone: return "Ordered mainly for female pattern hair loss. Default range shown is typical for women — for a male result, use the range printed on your report."
        case .dheaS: return "Ordered mainly for female pattern hair loss. Ranges vary widely by age and lab — use your report's printed range."
        }
    }

    /// Alternate units some labs report in (UK/EU/AU reports commonly use SI units for vitamin
    /// D and B12), each with a deterministic factor to this test's canonical `unit` — the unit
    /// every `LabResult.value` is actually stored in. The canonical unit is always first, so
    /// "no conversion" is always an available, obvious choice.
    var unitOptions: [LabUnitOption] {
        switch self {
        case .vitaminD:
            // 25-OH vitamin D: 1 nmol/L ≈ 0.4 ng/mL (i.e. ng/mL = nmol/L / 2.496).
            return [
                LabUnitOption(label: unit, factorToCanonical: 1),
                LabUnitOption(label: "nmol/L", factorToCanonical: 1 / 2.496),
            ]
        case .vitaminB12:
            // 1 pmol/L ≈ 1.355 pg/mL.
            return [
                LabUnitOption(label: unit, factorToCanonical: 1),
                LabUnitOption(label: "pmol/L", factorToCanonical: 1.355),
            ]
        case .ferritin, .tsh, .freeT4, .zinc, .hemoglobin, .totalTestosterone, .dheaS:
            return [LabUnitOption(label: unit, factorToCanonical: 1)]
        }
    }
}

/// One unit a lab report might use for a given test, and the deterministic multiplier that
/// converts a value in that unit to the test's canonical stored unit.
struct LabUnitOption: Identifiable, Equatable {
    let label: String
    let factorToCanonical: Double
    var id: String { label }

    func toCanonical(_ value: Double) -> Double { value * factorToCanonical }
}

enum LabFlag: Equatable {
    case low, normal, high
    var title: String {
        switch self {
        case .low: return "Below range"
        case .normal: return "In range"
        case .high: return "Above range"
        }
    }
}

/// In-clinic procedures a user can book an appointment for. Distinct from a daily `Treatment` —
/// these are dated events with reminders and a completion state.
enum ProcedureType: String, Codable, CaseIterable, Identifiable {
    case prp, microneedling, transplant, lllt, mesotherapy, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .prp: return "PRP"
        case .microneedling: return "Microneedling"
        case .transplant: return "Hair transplant"
        case .lllt: return "Low-level laser (LLLT)"
        case .mesotherapy: return "Mesotherapy"
        case .other: return "Other procedure"
        }
    }

    var symbol: String {
        switch self {
        case .prp: return "syringe.fill"
        case .microneedling: return "circle.grid.cross.fill"
        case .transplant: return "cross.case.fill"
        case .lllt: return "light.max"
        case .mesotherapy: return "drop.triangle.fill"
        case .other: return "calendar.badge.plus"
        }
    }

    /// The bundled gouache procedure art, where one exists (else empty → callers fall back to the symbol).
    var art: String {
        switch self {
        case .prp: return "procedure-prp"
        case .microneedling: return "procedure-microneedling"
        case .transplant: return "procedure-hair-transplant"
        case .lllt: return "procedure-low-level-laser"
        case .mesotherapy, .other: return ""
        }
    }
}

/// The "are you seeing new hair?" answer — the earliest patient-observable sign a treatment or
/// procedure is working (fine vellus "baby" hairs converting to terminal, ~2–4 months in).
enum RegrowthLevel: Int, Codable, CaseIterable, Identifiable {
    case none, few, visible, lots
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .few: return "A few"
        case .visible: return "Clearly visible"
        case .lots: return "Lots"
        }
    }
}

/// A three-point self-reported direction where `.better` is always the good direction. The exact
/// wording differs per question (density vs shedding vs hairline vs overall) — `label(for:)`.
enum ProgressTrend: Int, Codable, CaseIterable, Identifiable {
    case worse, same, better
    var id: Int { rawValue }

    enum Question { case density, shedding, hairline, overall }

    func label(for q: Question) -> String {
        switch (q, self) {
        case (.density, .worse): return "More scalp shows"
        case (.density, .same): return "About the same"
        case (.density, .better): return "Less scalp shows"
        case (.shedding, .worse): return "More"
        case (.shedding, .same): return "Same"
        case (.shedding, .better): return "Less"
        case (.hairline, .worse): return "Receding / widening"
        case (.hairline, .same): return "Stable"
        case (.hairline, .better): return "Filling in"
        case (.overall, .worse): return "Worse"
        case (.overall, .same): return "Stable"
        case (.overall, .better): return "Better"
        }
    }

    /// Compact lower-case phrase for the clinician export line.
    func clinicianPhrase(for q: Question) -> String { label(for: q).lowercased() }
}

enum PhotoRegion: String, Codable, CaseIterable, Identifiable {
    case frontal, vertex, templeLeft, templeRight, global
    var id: String { rawValue }
    var title: String {
        switch self {
        case .frontal: return "Frontal"
        case .vertex: return "Vertex"
        case .templeLeft: return "Left temple"
        case .templeRight: return "Right temple"
        case .global: return "Global"
        }
    }
    var symbol: String {
        switch self {
        case .frontal: return "person.crop.rectangle"
        case .vertex: return "circle.circle"
        case .templeLeft: return "arrow.left.circle"
        case .templeRight: return "arrow.right.circle"
        case .global: return "camera.viewfinder"
        }
    }
}

enum SeverityBand: Int {
    case mild, moderate, severe
    var title: String {
        switch self {
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }
}

// MARK: - Evidence tiers & the tracked-variable catalog
// The app's identity is honest uncertainty: every signal shows its evidence tier, and myths
// are named and excluded (see docs/TrackingSpec.md + the 2026-07-02 targeted evidence pass).

/// How much the 2020–2026 literature actually supports a variable's link to hair loss.
enum EvidenceTier: Int, Codable, CaseIterable, Identifiable {
    case strong, moderate, weak, context
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .strong: return "Strong evidence"
        case .moderate: return "Moderate evidence"
        case .weak: return "Weak signal"
        case .context: return "Context only"
        }
    }
    var short: String {
        switch self {
        case .strong: return "Strong"
        case .moderate: return "Moderate"
        case .weak: return "Weak"
        case .context: return "Context"
        }
    }
}

/// Whether a value comes from HealthKit/a wearable automatically, or is entered by hand.
enum CaptureMode {
    case auto, manual
    var badge: String { self == .auto ? "Auto from Health" : "Manual" }
    var symbol: String { self == .auto ? "heart.text.square" : "hand.tap" }
}

/// Episodic telogen-effluvium context. Diffuse shedding follows a trigger by ~2–3 months, so
/// these are dated events, not daily fields.
enum TriggerType: String, Codable, CaseIterable, Identifiable {
    case crashDiet, illness, majorStress, childbirth, newMedication, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .crashDiet: return "Crash diet / big weight loss"
        case .illness: return "Illness or fever"
        case .majorStress: return "Major stress event"
        case .childbirth: return "Childbirth"
        case .newMedication: return "New medication"
        case .other: return "Other trigger"
        }
    }
    var symbol: String {
        switch self {
        case .crashDiet: return "fork.knife"
        case .illness: return "thermometer.medium"
        case .majorStress: return "bolt.heart"
        case .childbirth: return "figure.2.and.child.holdinghands"
        case .newMedication: return "pills"
        case .other: return "calendar.badge.exclamationmark"
        }
    }
}

/// One row of the tracked-variable catalog — the single source of truth the UX layer reads to
/// render a label, an evidence tier, a capture badge, and a "why this matters" line.
struct TrackedVariable: Identifiable {
    let id: String
    let title: String
    let tier: EvidenceTier
    let capture: CaptureMode
    let why: String

    static let catalog: [TrackedVariable] = [
        .init(id: "shedding", title: "Shedding", tier: .moderate, capture: .manual,
              why: "The core patient-tracked signal for telogen effluvium and pattern loss. Trended over time."),
        .init(id: "scalp", title: "Scalp severity", tier: .strong, capture: .manual,
              why: "Flaking, redness and itch form a validated 16-point seborrheic-dermatitis score (Zhang 2023)."),
        .init(id: "oiliness", title: "Scalp oiliness", tier: .weak, capture: .manual,
              why: "An observation, not a risk driver. Sebum tracks with hormones but isn't independently actionable."),
        .init(id: "sleep", title: "Sleep", tier: .moderate, capture: .auto,
              why: "Poor sleep is linked to pattern-loss progression (not presence). Timed, never framed as a cause."),
        .init(id: "stress", title: "Stress", tier: .context, capture: .manual,
              why: "A common shedding-trigger context. Lower-tier evidence — shown as context, not cause."),
        .init(id: "hrv", title: "Recovery (HRV)", tier: .context, capture: .auto,
              why: "An objective stress/recovery proxy. No direct evidence it predicts hair loss — a soft signal only."),
        .init(id: "cigarettes", title: "Smoking", tier: .strong, capture: .manual,
              why: "A genuine, quantified risk factor for pattern loss (ever-smoker pooled OR ~1.8)."),
        .init(id: "alcohol", title: "Alcohol", tier: .weak, capture: .manual,
              why: "A possible modest association — not proven. The pooled effect isn't statistically significant."),
        .init(id: "weight", title: "Body weight", tier: .moderate, capture: .auto,
              why: "Linked to metabolic factors in pattern loss; rapid loss can trigger shedding ~2–3 months later."),
        .init(id: "diet", title: "Diet quality", tier: .weak, capture: .manual,
              why: "A vegetable-forward pattern shows a protective association; crash diets can trigger shedding."),
        .init(id: "traction", title: "Hair-care tension", tier: .strong, capture: .manual,
              why: "Tight styles, heat and chemical treatment cause traction alopecia — preventable, reversible early."),
    ]

    static subscript(_ id: String) -> TrackedVariable? {
        catalog.first { $0.id == id }
    }
}

/// Variables we deliberately DO NOT track, named in-app so the app's honesty is visible —
/// the same stance docs/TrackingSpec.md takes toward zinc and biotin.
enum ExcludedMyth: String, CaseIterable, Identifiable {
    case water, caffeine, exercise
    var id: String { rawValue }
    var title: String {
        switch self {
        case .water: return "Water intake"
        case .caffeine: return "Dietary caffeine"
        case .exercise: return "Exercise level"
        }
    }
    var reason: String {
        switch self {
        case .water: return "No evidence links hydration to hair loss."
        case .caffeine: return "Drinking coffee has no proven effect — topical-caffeine studies don't transfer to intake."
        case .exercise: return "No credible evidence that exercise causes or prevents hair loss."
        }
    }
}
