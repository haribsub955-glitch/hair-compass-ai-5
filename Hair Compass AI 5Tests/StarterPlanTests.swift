//
//  StarterPlanTests.swift
//  Hair Compass AI 5Tests
//
//  The starting plan is a pure function of the profile and the record. These tests pin the lab
//  and procedure tables (the one clinical judgement in the feature), the pregnancy reordering,
//  done-derivation for every item kind, dismissal, ordering, and completion.
//

import Testing
@testable import Hair_Compass_AI_5

struct StarterPlanTests {

    private func snapshot(
        condition: HairCondition = .telogenEffluvium,
        sex: BiologicalSex = .female,
        pregnancy: PregnancyStatus = .no,
        labTests: Set<LabTest> = [],
        treatmentClasses: Set<TreatmentClass> = [],
        hasAnyTreatment: Bool = false,
        hasAnyLab: Bool = false,
        hasBaselinePhoto: Bool = false,
        procedureTypes: Set<ProcedureType> = [],
        remindersEnabled: Bool = false,
        loggedToday: Bool = false,
        dismissed: Set<String> = []
    ) -> StarterPlan.Snapshot {
        StarterPlan.Snapshot(
            condition: condition, sex: sex, pregnancy: pregnancy,
            labTests: labTests, treatmentClasses: treatmentClasses,
            hasAnyTreatment: hasAnyTreatment, hasAnyLab: hasAnyLab,
            hasBaselinePhoto: hasBaselinePhoto, procedureTypes: procedureTypes,
            remindersEnabled: remindersEnabled, loggedToday: loggedToday, dismissed: dismissed
        )
    }

    // MARK: Lab table

    @Test func telogenEffluviumGetsTheBroadScreen() {
        #expect(LabSuggestion.tests(condition: .telogenEffluvium, sex: .male, pregnancy: .no)
                == [.ferritin, .tsh, .vitaminD, .vitaminB12, .hemoglobin, .zinc])
    }

    @Test func unsureGetsTheBroadScreenWithoutZinc() {
        #expect(LabSuggestion.tests(condition: .unsure, sex: .female, pregnancy: .no)
                == [.ferritin, .tsh, .vitaminD, .vitaminB12, .hemoglobin])
    }

    @Test func femalePatternLossAddsHormones() {
        #expect(LabSuggestion.tests(condition: .androgenetic, sex: .female, pregnancy: .no)
                == [.ferritin, .tsh, .vitaminD, .totalTestosterone, .dheaS])
    }

    @Test func malePatternLossKeepsItShort() {
        #expect(LabSuggestion.tests(condition: .androgenetic, sex: .male, pregnancy: .no) == [.ferritin, .vitaminD])
        #expect(LabSuggestion.tests(condition: .androgenetic, sex: .other, pregnancy: .no) == [.ferritin, .vitaminD])
    }

    @Test func areataGetsThyroidPair() {
        #expect(LabSuggestion.tests(condition: .alopeciaAreata, sex: .male, pregnancy: .no)
                == [.tsh, .freeT4, .vitaminD, .vitaminB12])
    }

    @Test func mechanicalAndSkinConditionsSuggestNoLabs() {
        #expect(LabSuggestion.tests(condition: .traction, sex: .female, pregnancy: .no).isEmpty)
        #expect(LabSuggestion.tests(condition: .seborrheicDermatitis, sex: .male, pregnancy: .no).isEmpty)
    }

    /// Pregnancy, breastfeeding or trying to conceive: ferritin and TSH lead, added if absent.
    @Test func pregnancyMovesFerritinAndTSHToTheFront() {
        for status in [PregnancyStatus.pregnant, .breastfeeding, .tryingToConceive] {
            let areata = LabSuggestion.tests(condition: .alopeciaAreata, sex: .female, pregnancy: status)
            #expect(Array(areata.prefix(2)) == [.ferritin, .tsh], "\(status)")
            #expect(areata.filter { $0 == .tsh }.count == 1, "no duplicates for \(status)")
            let traction = LabSuggestion.tests(condition: .traction, sex: .female, pregnancy: status)
            #expect(traction == [.ferritin, .tsh], "\(status)")
        }
    }

    @Test func everyLabHasAPlainLanguageWhy() {
        for test in LabTest.allCases {
            let why = LabSuggestion.why(test)
            #expect(!why.isEmpty, "\(test)")
            #expect(!why.lowercased().contains("you need"), "\(test): never a directive")
        }
    }

    // MARK: Procedure table

    @Test func procedureTable() {
        #expect(ProcedureSuggestion.types(condition: .androgenetic) == [.prp, .lllt, .microneedling, .transplant])
        #expect(ProcedureSuggestion.types(condition: .alopeciaAreata) == [.consultation])
        #expect(ProcedureSuggestion.types(condition: .traction) == [.consultation])
        #expect(ProcedureSuggestion.types(condition: .unsure) == [.consultation])
        #expect(ProcedureSuggestion.types(condition: .telogenEffluvium).isEmpty)
        #expect(ProcedureSuggestion.types(condition: .seborrheicDermatitis).isEmpty)
    }

    // MARK: Items

    @Test func groupsComeInOrderWithSetupFirst() {
        let items = StarterPlan.items(for: snapshot(condition: .androgenetic, sex: .female))
        let groups = items.map(\.group)
        let firstIndex: [StarterPlanGroup: Int] = Dictionary(
            groups.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        #expect(firstIndex[.setUp]! < firstIndex[.askClinician]!)
        #expect(firstIndex[.askClinician]! < firstIndex[.evidenceOptions]!)
        #expect(firstIndex[.evidenceOptions]! < firstIndex[.inClinic]!)
    }

    @Test func setupStepsAreAlwaysPresentInOrder() {
        let items = StarterPlan.items(for: snapshot(condition: .traction))
        let setup = items.filter { $0.group == .setUp }.map(\.id)
        #expect(setup == ["setup.logToday", "setup.addTreatments", "setup.enterLabs", "setup.baselinePhoto", "setup.reminders"])
    }

    @Test func idsAreStableAndDistinct() {
        let items = StarterPlan.items(for: snapshot(condition: .androgenetic, sex: .female))
        #expect(items.map(\.id).contains("lab.ferritin"))
        #expect(items.map(\.id).contains("procedure.prp"))
        #expect(items.contains { $0.id.hasPrefix("treatment.") })
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test func treatmentOptionsAreTopThreeStrongOrModerate() {
        let items = StarterPlan.items(for: snapshot(condition: .androgenetic, sex: .male))
        let treatments = items.filter { $0.group == .evidenceOptions }
        #expect(treatments.count == 3)
        let ids = treatments.map(\.id)
        #expect(ids == ["treatment.combo", "treatment.minox", "treatment.fin"])
    }

    @Test func doneIsDerivedFromTheRecord() {
        let s = snapshot(
            condition: .androgenetic, sex: .male,
            labTests: [.ferritin], treatmentClasses: [.minoxidil],
            hasAnyTreatment: true, hasAnyLab: true, hasBaselinePhoto: true,
            procedureTypes: [.prp], remindersEnabled: true, loggedToday: true
        )
        let items = StarterPlan.items(for: s)
        func done(_ id: String) -> Bool? { items.first { $0.id == id }?.isDone }
        #expect(done("lab.ferritin") == true)
        #expect(done("lab.vitaminD") == false)
        #expect(done("treatment.minox") == true)       // .addToPlan(.minoxidil) and minoxidil is in the plan
        #expect(done("treatment.combo") == false)      // no action → only dismissible
        #expect(done("procedure.prp") == true)
        #expect(done("procedure.lllt") == false)
        for step in ["setup.logToday", "setup.addTreatments", "setup.enterLabs", "setup.baselinePhoto", "setup.reminders"] {
            #expect(done(step) == true, "\(step)")
        }
    }

    @Test func doneItemsSinkToTheEndOfTheirGroup() {
        let s = snapshot(condition: .telogenEffluvium, labTests: [.ferritin])
        let labs = StarterPlan.items(for: s).filter { $0.group == .askClinician }
        #expect(labs.last?.id == "lab.ferritin")
        #expect(labs.first?.id == "lab.tsh")
    }

    @Test func dismissedItemsAreExcluded() {
        let s = snapshot(condition: .telogenEffluvium, dismissed: ["lab.zinc", "setup.reminders"])
        let ids = StarterPlan.items(for: s).map(\.id)
        #expect(!ids.contains("lab.zinc"))
        #expect(!ids.contains("setup.reminders"))
        #expect(ids.contains("lab.ferritin"))
    }

    @Test func pregnancyCautionRidesOnLabItems() {
        let items = StarterPlan.items(for: snapshot(condition: .telogenEffluvium, pregnancy: .pregnant))
        let ferritin = items.first { $0.id == "lab.ferritin" }
        #expect(ferritin?.caution == LabSuggestion.pregnancyCaution)
        let plain = StarterPlan.items(for: snapshot(condition: .telogenEffluvium, pregnancy: .no))
        #expect(plain.first { $0.id == "lab.ferritin" }?.caution == nil)
    }

    @Test func completeMeansEveryRemainingItemIsDone() {
        let s = snapshot(
            condition: .seborrheicDermatitis, sex: .male,
            hasAnyTreatment: true, hasAnyLab: true, hasBaselinePhoto: true,
            remindersEnabled: true, loggedToday: true,
            dismissed: ["treatment.antifungal", "treatment.note-sd"]
        )
        let items = StarterPlan.items(for: s)
        #expect(StarterPlan.isComplete(items))
        let incomplete = StarterPlan.items(for: snapshot(condition: .seborrheicDermatitis))
        #expect(!StarterPlan.isComplete(incomplete))
        #expect(StarterPlan.isComplete([]))
    }
}
