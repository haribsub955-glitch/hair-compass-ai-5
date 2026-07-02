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
    case minoxidil, finasteride, dutasteride, microneedling, prp, lllt, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .minoxidil: return "Minoxidil"
        case .finasteride: return "Finasteride"
        case .dutasteride: return "Dutasteride"
        case .microneedling: return "Microneedling"
        case .prp: return "PRP"
        case .lllt: return "Low-level laser"
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
        case .other: return "cross.case.fill"
        }
    }

    /// Typical loggable events per day, used for adherence math.
    var defaultDailyCount: Int {
        switch self {
        case .minoxidil: return 2
        case .finasteride, .dutasteride: return 1
        default: return 0 // periodic, not daily
        }
    }

    var isDaily: Bool { defaultDailyCount > 0 }
}

enum LabTest: String, Codable, CaseIterable, Identifiable {
    case ferritin, tsh, freeT4, vitaminD, vitaminB12
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ferritin: return "Ferritin"
        case .tsh: return "TSH"
        case .freeT4: return "Free T4"
        case .vitaminD: return "Vitamin D (25-OH)"
        case .vitaminB12: return "Vitamin B12"
        }
    }

    var unit: String {
        switch self {
        case .ferritin: return "ng/mL"
        case .tsh: return "mIU/L"
        case .freeT4: return "ng/dL"
        case .vitaminD: return "ng/mL"
        case .vitaminB12: return "pg/mL"
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
        }
    }

    var note: String {
        switch self {
        case .ferritin: return "Iron stores. Low ferritin is linked to telogen effluvium."
        case .tsh, .freeT4: return "Thyroid function — a treatable shedding driver."
        case .vitaminD: return "Order when clinically indicated, not by default."
        case .vitaminB12: return "Checked selectively; deficiency is uncommon."
        }
    }
}

enum LabFlag {
    case low, normal, high
    var title: String {
        switch self {
        case .low: return "Below range"
        case .normal: return "In range"
        case .high: return "Above range"
        }
    }
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
