//
//  StarterPlan.swift
//  Hair Compass AI 5
//
//  The starting plan handed over at the end of onboarding and kept on the Plan tab: labs worth
//  asking a clinician about, the treatment options the evidence supports, in-clinic options, and
//  five setup steps. Pure and stateless — a function of the profile and a value snapshot of the
//  record — so done-ness can never drift from the record. The only stored state (dismissed ids)
//  is an input.
//
//  Framing: education and record-keeping. Every "why" is a plain sentence; none is a directive.
//

import Foundation

enum StarterPlanGroup: String, CaseIterable, Identifiable {
    case setUp, askClinician, evidenceOptions, inClinic
    var id: String { rawValue }

    var eyebrow: String {
        switch self {
        case .setUp: return "Set up"
        case .askClinician: return "Ask your clinician about"
        case .evidenceOptions: return "Options with evidence"
        case .inClinic: return "In-clinic options"
        }
    }
}

enum StarterSetupStep: String, CaseIterable {
    case logToday, addTreatments, enterLabs, baselinePhoto, reminders

    var title: String {
        switch self {
        case .logToday: return "Log today"
        case .addTreatments: return "Add your medications and treatments"
        case .enterLabs: return "Enter your lab values"
        case .baselinePhoto: return "Take a baseline photo"
        case .reminders: return "Turn on reminders"
        }
    }

    var why: String {
        switch self {
        case .logToday: return "One entry a day is what the trends are built from."
        case .addTreatments: return "Anything you apply or take becomes a daily step in your ritual."
        case .enterLabs: return "Results you already have go here; the app watches the trend."
        case .baselinePhoto: return "The same angle every month is how change becomes visible."
        case .reminders: return "A nudge at your routine time keeps the record continuous."
        }
    }
}

enum StarterPlanKind: Equatable {
    case lab(LabTest)
    case treatment(optionID: String, action: RecommendedAction?)
    case procedure(ProcedureType)
    case setup(StarterSetupStep)
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

/// Which labs are worth asking about, by condition. Wording everywhere is "worth asking your
/// clinician about" — this table never orders a test. A clinician review of the table is a
/// release-checklist item.
enum LabSuggestion {
    static let pregnancyCaution = "Pregnancy, breastfeeding or trying to conceive change what's normal — tell your clinician when you ask."

    static func tests(condition: HairCondition, sex: BiologicalSex, pregnancy: PregnancyStatus) -> [LabTest] {
        var base: [LabTest]
        switch condition {
        case .telogenEffluvium: base = [.ferritin, .tsh, .vitaminD, .vitaminB12, .hemoglobin, .zinc]
        case .unsure: base = [.ferritin, .tsh, .vitaminD, .vitaminB12, .hemoglobin]
        case .androgenetic:
            base = sex == .female ? [.ferritin, .tsh, .vitaminD, .totalTestosterone, .dheaS] : [.ferritin, .vitaminD]
        case .alopeciaAreata: base = [.tsh, .freeT4, .vitaminD, .vitaminB12]
        case .traction, .seborrheicDermatitis: base = []
        }
        if isPregnancyRelated(pregnancy) {
            base.removeAll { $0 == .ferritin || $0 == .tsh }
            base.insert(contentsOf: [.ferritin, .tsh], at: 0)
        }
        return base
    }

    /// Duplicates `PregnancyStatus.flagsMedicationCaution` in name only — this delegates to it so
    /// the one clinical judgement (which statuses change what's normal enough to flag) lives in
    /// one place. Kept as its own function so existing callers and tests are unchanged.
    static func isPregnancyRelated(_ status: PregnancyStatus) -> Bool {
        status.flagsMedicationCaution
    }

    static func why(_ test: LabTest) -> String {
        switch test {
        case .ferritin: return "Low iron stores are a common, fixable reason for shedding."
        case .tsh: return "Thyroid problems are a common, checkable driver of shedding."
        case .freeT4: return "Paired with TSH, it completes the thyroid picture."
        case .vitaminD: return "Low vitamin D is common and easy to correct."
        case .vitaminB12: return "Low B12 can thin hair and is simple to check."
        case .hemoglobin: return "Anaemia is a frequent, treatable cause of diffuse shedding."
        case .zinc: return "Zinc is part of the hair cycle and worth ruling out."
        case .totalTestosterone: return "Helps your clinician see whether hormones play a part."
        case .dheaS: return "Another hormone marker that helps explain pattern loss in women."
        }
    }
}

/// In-clinic options by condition. Only the conditions where a procedure is a recognised path;
/// effluvium and a flaky scalp get none.
enum ProcedureSuggestion {
    static func types(condition: HairCondition) -> [ProcedureType] {
        switch condition {
        case .androgenetic: return [.prp, .lllt, .microneedling, .transplant]
        case .alopeciaAreata, .traction, .unsure: return [.consultation]
        case .telogenEffluvium, .seborrheicDermatitis: return []
        }
    }
}

enum StarterPlan {

    /// Everything the plan depends on, as values. Built from SwiftData by the callers
    /// (`StarterPlan.Snapshot.make`, `.fresh`) so this file never touches a model context.
    struct Snapshot: Equatable {
        var condition: HairCondition
        var sex: BiologicalSex
        var pregnancy: PregnancyStatus
        var labTests: Set<LabTest>              // tests with at least one result
        var treatmentClasses: Set<TreatmentClass>
        var hasAnyTreatment: Bool
        var hasAnyLab: Bool
        var hasBaselinePhoto: Bool
        var procedureTypes: Set<ProcedureType>  // recorded appointments
        var remindersEnabled: Bool
        var loggedToday: Bool
        var dismissed: Set<String>
    }

    static func items(for s: Snapshot) -> [StarterPlanItem] {
        var out: [StarterPlanItem] = []

        // Set up — always present, in a fixed order.
        for step in StarterSetupStep.allCases {
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

        // Ask your clinician about.
        let pregnancyRelated = LabSuggestion.isPregnancyRelated(s.pregnancy)
        for test in LabSuggestion.tests(condition: s.condition, sex: s.sex, pregnancy: s.pregnancy) {
            out.append(StarterPlanItem(
                id: "lab.\(test.rawValue)", group: .askClinician, kind: .lab(test),
                title: test.title, why: LabSuggestion.why(test),
                caution: pregnancyRelated ? LabSuggestion.pregnancyCaution : nil,
                isDone: s.labTests.contains(test)))
        }

        // Options with evidence — the top three strong or moderate options.
        let options = TreatmentRecommender.options(condition: s.condition, sex: s.sex)
            .filter { $0.tier == .strong || $0.tier == .moderate }
            .prefix(3)
        for option in options {
            let done: Bool
            switch option.action {
            case .addToPlan(let treatmentClass): done = s.treatmentClasses.contains(treatmentClass)
            case .addLabResult(let test): done = s.labTests.contains(test)
            default: done = false
            }
            out.append(StarterPlanItem(
                id: "treatment.\(option.id)", group: .evidenceOptions,
                kind: .treatment(optionID: option.id, action: option.action),
                title: option.name, why: option.summary, caution: option.caution, isDone: done))
        }

        // In-clinic options.
        for type in ProcedureSuggestion.types(condition: s.condition) {
            out.append(StarterPlanItem(
                id: "procedure.\(type.rawValue)", group: .inClinic, kind: .procedure(type),
                title: type.title, why: ProcedureGuide.shortExpectation(for: type), caution: nil,
                isDone: s.procedureTypes.contains(type)))
        }

        // Dismissed items are gone; within each group, done items sink to the end (stable).
        let kept = out.filter { !s.dismissed.contains($0.id) }
        return StarterPlanGroup.allCases.flatMap { group in
            let inGroup = kept.filter { $0.group == group }
            return inGroup.filter { !$0.isDone } + inGroup.filter { $0.isDone }
        }
    }

    /// Nothing left to do: every remaining item is done (dismissed ones are already excluded).
    static func isComplete(_ items: [StarterPlanItem]) -> Bool {
        items.allSatisfy(\.isDone)
    }
}
