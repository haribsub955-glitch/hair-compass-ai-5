import Foundation

/// A record-backed roadmap, not a prescription. Sources and clinical boundaries are shared
/// by onboarding and Plan; see docs/StarterCarePlan.md.
enum StarterPlanGroup: String, CaseIterable, Identifiable {
    case setUp, askClinician, evidenceOptions, inClinic
    var id: String { rawValue }
    var eyebrow: String {
        switch self {
        case .setUp: return "1 · Start with a record"
        case .askClinician: return "2 · Check the cause"
        case .evidenceOptions: return "3 · Agree on care"
        case .inClinic: return "Later · Specialist options"
        }
    }
}

enum StarterSetupStep: String, CaseIterable {
    case logToday, addTreatments, enterLabs, baselinePhoto, reminders
    var title: String {
        switch self {
        case .logToday: return "Make a brief check-in"
        case .addTreatments: return "Record care you already use"
        case .enterLabs: return "Save results you already have"
        case .baselinePhoto: return "Take a baseline photo"
        case .reminders: return "Choose a reminder, if helpful"
        }
    }
    var why: String {
        switch self {
        case .logToday: return "Note how things are today. You do not need to count every hair or keep checking."
        case .addTreatments: return "Optional: record existing medicines or scalp care and the schedule you were given. This is not a request to start treatment."
        case .enterLabs: return "Optional: copy the date, units and reference range from an existing report. No new test is required to use the app."
        case .baselinePhoto: return "One consistent set gives you a starting point. Compare about monthly, not several times a day."
        case .reminders: return "Optional: a quiet nudge for a routine you choose, never pressure to keep a perfect streak."
        }
    }
}

enum StarterGuidance: String, Identifiable {
    case labs, care
    var id: String { rawValue }
}

enum StarterPlanKind: Equatable {
    case lab(LabTest)
    case treatment(optionID: String, action: RecommendedAction?)
    case procedure(ProcedureType)
    case setup(StarterSetupStep)
    case guidance(StarterGuidance)
}

struct StarterPlanItem: Identifiable, Equatable {
    let id: String
    let group: StarterPlanGroup
    let kind: StarterPlanKind
    let title: String
    let why: String
    let caution: String?
    let isDone: Bool
}

/// Discussion examples, never a standing lab order. The profile does not collect enough
/// history to infer a deficiency, thyroid disorder or hormone excess from sex alone.
enum LabSuggestion {
    static let pregnancyCaution = "Tell your clinician if you are pregnant, breastfeeding or trying to conceive before discussing tests or treatment."
    static func tests(condition: HairCondition, sex: BiologicalSex, pregnancy: PregnancyStatus) -> [LabTest] {
        condition == .telogenEffluvium ? [.ferritin, .tsh] : []
    }
    static func isPregnancyRelated(_ status: PregnancyStatus) -> Bool { status.flagsMedicationCaution }
    static func why(_ test: LabTest) -> String {
        switch test {
        case .ferritin: return "With diffuse shedding, your clinician may consider iron studies if your history or examination suggests iron deficiency."
        case .tsh: return "Your clinician may consider thyroid testing when evaluating diffuse shedding or symptoms of thyroid disease."
        default: return "Whether this test is useful depends on your history, examination and existing results. Ask your clinician before arranging it."
        }
    }
}

/// Procedures remain in the education library, not a new user's required to-do list.
enum ProcedureSuggestion {
    static func types(condition: HairCondition) -> [ProcedureType] { [.consultation] }
}

enum StarterPlan {
    static let disclaimer = "Based on your answers, not a diagnosis. A clinician decides which tests and treatments, if any, are appropriate. Tracking must not delay getting care."
    static let safetyNote = "Seek prompt medical assessment for sudden patches, rapid worsening, scalp pain or burning, sores, or a shiny/scar-like area. You do not need to wait for a trend."
    static let diagnosisURL = URL(string: "https://www.aad.org/public/diseases/hair-loss/treatment/diagnosis-treat")!
    static let sheddingURL = URL(string: "https://www.bad.org.uk/pils/telogen-effluvium")!
    static let symptomsURL = URL(string: "https://www.aad.org/public/diseases/hair-loss/types/ccca/symptoms")!

    struct Snapshot: Equatable {
        var condition: HairCondition
        var sex: BiologicalSex
        var pregnancy: PregnancyStatus
        var labTests: Set<LabTest>
        var treatmentClasses: Set<TreatmentClass>
        var hasAnyTreatment: Bool
        var hasAnyLab: Bool
        var hasBaselinePhoto: Bool
        var procedureTypes: Set<ProcedureType>
        var remindersEnabled: Bool
        var loggedToday: Bool
        var dismissed: Set<String>
        var hasCompletedConsultation = false
        var discussed: Set<String> = []
    }

    static func visitReason(_ condition: HairCondition) -> String {
        switch condition {
        case .unsure: return "Start with a primary-care clinician or dermatologist to examine your scalp and work out the cause before choosing treatment."
        case .telogenEffluvium: return "Discuss when shedding began, recent illness, childbirth, diet changes and medicines. Your reported pattern still needs clinical assessment."
        case .androgenetic: return "A clinician can assess the pattern, check for overlapping causes and discuss suitable options. Selecting a pattern in onboarding is not a diagnosis."
        case .alopeciaAreata: return "Arrange a dermatologist assessment for patchy loss. An examination helps distinguish causes and guide care."
        case .traction: return "Discuss pulling or tight hairstyles and have the affected areas examined. Avoid styles that pull while arranging advice."
        case .seborrheicDermatitis: return "Discuss persistent flaking, itch and any hair loss with a clinician so scalp care matches the cause."
        }
    }

    static func labReason(_ condition: HairCondition) -> String {
        if condition == .telogenEffluvium {
            return "For diffuse shedding, ask whether iron studies (such as ferritin) or thyroid testing are indicated. History and examination come first; not everyone needs tests."
        }
        return "There is no automatic hair-loss blood panel here. Ask whether your symptoms, diet, medicines or examination make targeted testing useful."
    }

    static func items(for s: Snapshot) -> [StarterPlanItem] {
        var out: [StarterPlanItem] = []
        // Two small first steps. Optional setup stays available without dominating day one.
        for step in [StarterSetupStep.baselinePhoto, .logToday, .addTreatments, .enterLabs, .reminders] {
            let done: Bool
            switch step {
            case .logToday: done = s.loggedToday
            case .addTreatments: done = s.hasAnyTreatment
            case .enterLabs: done = s.hasAnyLab
            case .baselinePhoto: done = s.hasBaselinePhoto
            case .reminders: done = s.remindersEnabled
            }
            out.append(StarterPlanItem(
                id: "setup.\(step.rawValue)", group: .setUp, kind: .setup(step),
                title: step.title, why: step.why, caution: nil, isDone: done))
        }
        let caution = s.pregnancy.flagsMedicationCaution ? LabSuggestion.pregnancyCaution : nil
        out.append(StarterPlanItem(
            id: "procedure.consultation", group: .askClinician, kind: .procedure(.consultation),
            title: s.hasCompletedConsultation ? "Clinician visit recorded" : "Arrange a clinician assessment",
            why: visitReason(s.condition), caution: caution, isDone: s.hasCompletedConsultation))
        out.append(StarterPlanItem(
            id: "discussion.labs", group: .askClinician, kind: .guidance(.labs),
            title: "Discuss whether labs would help", why: labReason(s.condition),
            caution: nil, isDone: s.discussed.contains(StarterGuidance.labs.rawValue)))
        out.append(StarterPlanItem(
            id: "discussion.care", group: .evidenceOptions, kind: .guidance(.care),
            title: "Agree on care and a review date",
            why: "Ask what to use, what side effects to report and when to review. Record only the care you choose together; no purchase or procedure is required.",
            caution: caution, isDone: s.discussed.contains(StarterGuidance.care.rawValue)))

        let kept = out.filter { !s.dismissed.contains($0.id) }
        return StarterPlanGroup.allCases.flatMap { group in
            let rows = kept.filter { $0.group == group }
            return rows.filter { !$0.isDone } + rows.filter { $0.isDone }
        }
    }

    static func isComplete(_ items: [StarterPlanItem]) -> Bool { items.allSatisfy(\.isDone) }
}
