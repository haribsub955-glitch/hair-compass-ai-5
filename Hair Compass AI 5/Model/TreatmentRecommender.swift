import Foundation

/// Gentle-educator guidance: for the user's stated pattern, what the evidence actually supports —
/// ranked, with cautions and an always-present "confirm with a clinician" note. It EDUCATES and
/// RANKS; it never prescribes a drug or a dose. Grounded in docs/TrackingSpec.md + the evidence pass.

enum RecommendedAction: Equatable {
    case addToPlan(TreatmentClass)
    case scheduleDoctorVisit
    case startPatchPhotoSeries
    case recordTrigger
    case addLabResult(LabTest)
    case reviewPregnancyCaution

    var title: String {
        switch self {
        case .addToPlan: return "Add to plan"
        case .scheduleDoctorVisit: return "Plan a clinician visit"
        case .startPatchPhotoSeries: return "Start a patch photo series"
        case .recordTrigger: return "Record a possible trigger"
        case .addLabResult: return "Add a lab result"
        case .reviewPregnancyCaution: return "Review pregnancy caution"
        }
    }
}

struct RecommendedOption: Identifiable {
    let id: String
    let name: String
    let tier: EvidenceTier
    let summary: String
    let clinicianNote: String
    let caution: String?
    let action: RecommendedAction?

    init(id: String, name: String, tier: EvidenceTier, summary: String,
         clinicianNote: String, caution: String?, action: RecommendedAction? = nil) {
        self.id = id; self.name = name; self.tier = tier; self.summary = summary
        self.clinicianNote = clinicianNote; self.caution = caution; self.action = action
    }
}

enum TreatmentRecommender {
    static let disclaimer = "This is education, not a prescription. What's right for you depends on your history and health — confirm any treatment with a clinician before starting."

    static func headline(condition: HairCondition) -> String {
        switch condition {
        case .androgenetic: return "For pattern hair loss, the evidence supports:"
        case .telogenEffluvium: return "For diffuse shedding, the priority is the trigger:"
        case .alopeciaAreata: return "Alopecia areata needs specialist care:"
        case .traction: return "For tension-driven loss, the fix is mechanical:"
        case .seborrheicDermatitis: return "For a flaky, inflamed scalp:"
        case .unsure: return "Before choosing an approach, get a diagnosis:"
        }
    }

    static func options(condition: HairCondition, sex: BiologicalSex) -> [RecommendedOption] {
        switch condition {
        case .androgenetic:
            return sex == .female ? femaleAGA : maleAGA
        case .telogenEffluvium: return telogen
        case .alopeciaAreata: return alopeciaAreata
        case .traction: return traction
        case .seborrheicDermatitis: return sebDerm
        case .unsure: return unsure
        }
    }

    private static let maleAGA: [RecommendedOption] = [
        .init(id: "combo", name: "Minoxidil + finasteride together", tier: .strong,
              summary: "The most effective combination in trials for male pattern loss — better than either alone.",
              clinicianNote: "Finasteride is prescription-only; a clinician confirms it's suitable for you.",
              caution: "Finasteride causes sexual side effects in a minority — discuss the risks."),
        .init(id: "minox", name: "Minoxidil (topical)", tier: .strong,
              summary: "A well-studied over-the-counter topical that helps many. Expect an early shedding phase and results around 6 months.",
              clinicianNote: "Ask a pharmacist or clinician which strength suits you.",
              caution: "Apply consistently — a temporary shed at the start is normal, not failure.", action: .addToPlan(.minoxidil)),
        .init(id: "fin", name: "Finasteride (oral)", tier: .strong,
              summary: "A prescription DHT-blocker with strong evidence for slowing and partly reversing male pattern loss.",
              clinicianNote: "Prescription only — review the side-effect profile with your doctor.",
              caution: "Must not be handled or taken by anyone who is or may become pregnant."),
        .init(id: "microneedle", name: "Microneedling", tier: .moderate,
              summary: "Adds to minoxidil's effect in several trials, typically done about weekly.",
              clinicianNote: "Ask about needle depth and technique to do it safely.", caution: nil),
        .init(id: "keto", name: "Ketoconazole shampoo", tier: .moderate,
              summary: "An anti-inflammatory medicated shampoo that can support density as an add-on.",
              clinicianNote: "A reasonable adjunct; the 2% strength has the best evidence.", caution: nil),
    ]

    private static let femaleAGA: [RecommendedOption] = [
        .init(id: "minox-f", name: "Minoxidil (topical)", tier: .strong,
              summary: "The first-line, best-evidenced option for female pattern loss. Results build over about 6 months.",
              clinicianNote: "Ask a clinician which strength and routine fit you.",
              caution: "A temporary shed at the start is normal.", action: .addToPlan(.minoxidil)),
        .init(id: "antiandrogen", name: "Anti-androgen (e.g. spironolactone)", tier: .moderate,
              summary: "Prescription anti-androgens are used for female pattern loss under a clinician's guidance.",
              clinicianNote: "Specialist-guided and prescription-only — discuss suitability.",
              caution: "Not during pregnancy; needs monitoring.", action: .reviewPregnancyCaution),
        .init(id: "lllt-f", name: "Low-level laser therapy", tier: .weak,
              summary: "Some devices show modest benefit; reasonable as an adjunct if you want a drug-free add-on.",
              clinicianNote: "Optional adjunct — set realistic expectations.", caution: nil),
        .init(id: "labs-f", name: "Rule out reversible causes", tier: .moderate,
              summary: "Diffuse thinning in women often has treatable drivers — iron, thyroid, vitamin D.",
              clinicianNote: "Ask your clinician to check ferritin, thyroid and vitamin D (log them in Labs).", caution: nil, action: .addLabResult(.ferritin)),
    ]

    private static let telogen: [RecommendedOption] = [
        .init(id: "trigger", name: "Find and fix the trigger", tier: .strong,
              summary: "Telogen effluvium usually recovers on its own once the trigger (illness, crash diet, stress, childbirth) passes.",
              clinicianNote: "Log the likely trigger date so the ~2–3 month lag makes sense.", caution: nil, action: .recordTrigger),
        .init(id: "labs-te", name: "Check ferritin, thyroid, vitamin D", tier: .moderate,
              summary: "Low iron or thyroid problems are common, treatable drivers of diffuse shedding.",
              clinicianNote: "Ask for these blood tests and log the results here.", caution: nil, action: .addLabResult(.ferritin)),
        .init(id: "minox-te", name: "Minoxidil (optional)", tier: .weak,
              summary: "May help density while you recover, though the shedding often resolves without it.",
              clinicianNote: "Optional; discuss if the shedding drags on.", caution: nil),
        .init(id: "time-te", name: "Give it time", tier: .strong,
              summary: "Most cases settle within 6 months. See a clinician if shedding lasts longer or worsens.",
              clinicianNote: "Persistent shedding beyond 6 months warrants a review.", caution: nil),
    ]

    private static let alopeciaAreata: [RecommendedOption] = [
        .init(id: "derm-aa", name: "See a dermatologist", tier: .strong,
              summary: "Alopecia areata is immune-mediated — over-the-counter products don't address it.",
              clinicianNote: "Treatments (steroid injections, topical immunotherapy, JAK inhibitors) are specialist-guided.", caution: nil, action: .scheduleDoctorVisit),
        .init(id: "track-aa", name: "Document the patches", tier: .moderate,
              summary: "Photos of each patch over time help your dermatologist judge activity and response.",
              clinicianNote: "Use the guided camera to keep a consistent record.", caution: nil, action: .startPatchPhotoSeries),
    ]

    private static let traction: [RecommendedOption] = [
        .init(id: "release", name: "Release the tension", tier: .strong,
              summary: "Loosen tight styles and avoid constant pulling. Early traction loss is preventable and reversible.",
              clinicianNote: "If the hairline hasn't recovered after easing off, see a dermatologist — chronic traction can scar.", caution: nil),
        .init(id: "minox-tr", name: "Minoxidil at the hairline (optional)", tier: .weak,
              summary: "May support regrowth on affected areas once the tension is removed.",
              clinicianNote: "Optional adjunct — the tension change is the main fix.", caution: nil),
    ]

    private static let sebDerm: [RecommendedOption] = [
        .init(id: "antifungal", name: "Antifungal shampoo (ketoconazole)", tier: .strong,
              summary: "The mainstay for a flaky, inflamed, itchy scalp — used regularly, then as needed.",
              clinicianNote: "For persistent or severe flares, a clinician can add a short anti-inflammatory.", caution: nil),
        .init(id: "note-sd", name: "This is scalp health, not pattern loss", tier: .moderate,
              summary: "Seborrheic dermatitis is separate from thinning — calming it can reduce shedding and itch.",
              clinicianNote: "If thinning persists after the scalp calms, ask about pattern loss too.", caution: nil),
    ]

    private static let unsure: [RecommendedOption] = [
        .init(id: "track", name: "Track for a few weeks", tier: .moderate,
              summary: "Log shedding and scalp signs so a pattern emerges — the right approach depends on which type of loss you have.",
              clinicianNote: "Bring your trends and photos to the appointment.", caution: nil),
        .init(id: "diagnose", name: "Get a diagnosis", tier: .strong,
              summary: "A clinician can tell pattern loss from shedding or an inflammatory cause — that decides everything else.",
              clinicianNote: "A dermatologist or GP can examine your scalp and order the right tests.", caution: nil, action: .scheduleDoctorVisit),
    ]
}
