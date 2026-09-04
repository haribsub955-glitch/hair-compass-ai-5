import Testing
@testable import Hair_Compass_AI_5

struct StarterPlanTests {
    private func snapshot(condition: HairCondition = .unsure) -> StarterPlan.Snapshot {
        .init(condition: condition, sex: .female, pregnancy: .no,
              labTests: [], treatmentClasses: [], hasAnyTreatment: false, hasAnyLab: false,
              hasBaselinePhoto: false, procedureTypes: [], remindersEnabled: false,
              loggedToday: false, dismissed: [])
    }

    @Test func sexAndPregnancyDoNotInventLabPanels() {
        for condition in HairCondition.allCases {
            for sex in BiologicalSex.allCases {
                for pregnancy in PregnancyStatus.allCases {
                    let tests = LabSuggestion.tests(condition: condition, sex: sex, pregnancy: pregnancy)
                    #expect(tests == (condition == .telogenEffluvium ? [.ferritin, .tsh] : []))
                }
            }
        }
    }

    @Test func assessmentNotProceduresOrPrescriptionsLeadsEveryPlan() {
        for condition in HairCondition.allCases {
            let items = StarterPlan.items(for: snapshot(condition: condition))
            #expect(items.contains { $0.id == "procedure.consultation" })
            #expect(items.contains { $0.id == "discussion.labs" })
            #expect(items.contains { $0.id == "discussion.care" })
            #expect(!items.contains {
                if case .treatment = $0.kind { return true }
                if case .lab = $0.kind { return true }
                if case .procedure(let type) = $0.kind { return type != .consultation }
                return false
            })
            #expect(Set(items.map(\.id)).count == items.count)
            #expect(!StarterPlan.visitReason(condition).isEmpty)
        }
    }

    @Test func scheduledAppointmentDoesNotMeanAttended() {
        var s = snapshot()
        s.procedureTypes = [.consultation]
        #expect(StarterPlan.items(for: s).first { $0.id == "procedure.consultation" }?.isDone == false)
        s.hasCompletedConsultation = true
        #expect(StarterPlan.items(for: s).first { $0.id == "procedure.consultation" }?.isDone == true)
    }

    @Test func resultsDoNotProveDiscussion() {
        var s = snapshot()
        s.hasAnyLab = true
        s.labTests = [.ferritin, .tsh]
        #expect(StarterPlan.items(for: s).first { $0.id == "discussion.labs" }?.isDone == false)
        s.discussed = ["labs"]
        #expect(StarterPlan.items(for: s).first { $0.id == "discussion.labs" }?.isDone == true)
        #expect(StarterPlan.items(for: s).first { $0.id == "discussion.care" }?.isDone == false)
    }

    @Test func planCanCompleteWithoutTestsOrTreatment() {
        var s = snapshot()
        s.hasBaselinePhoto = true
        s.loggedToday = true
        s.hasCompletedConsultation = true
        s.discussed = ["labs", "care"]
        s.dismissed = ["setup.addTreatments", "setup.enterLabs", "setup.reminders"]
        #expect(StarterPlan.isComplete(StarterPlan.items(for: s)))
        s.discussed.remove("care")
        #expect(!StarterPlan.isComplete(StarterPlan.items(for: s)))
    }

    @Test func dismissalCanBeUndone() {
        var s = snapshot()
        let original = StarterPlan.items(for: s)
        s.dismissed = ["discussion.labs"]
        #expect(!StarterPlan.items(for: s).contains { $0.id == "discussion.labs" })
        s.dismissed = []
        #expect(StarterPlan.items(for: s) == original)
    }

    @Test func pregnancyCautionIsVisible() {
        var s = snapshot()
        s.pregnancy = .pregnant
        for id in ["procedure.consultation", "discussion.care"] {
            #expect(StarterPlan.items(for: s).first { $0.id == id }?.caution == LabSuggestion.pregnancyCaution)
        }
    }

    @Test func setupCompletionComesFromRecords() {
        var s = snapshot()
        s.hasAnyTreatment = true
        s.hasAnyLab = true
        s.hasBaselinePhoto = true
        s.loggedToday = true
        s.remindersEnabled = true
        let setupIsDone = StarterPlan.items(for: s).filter { $0.group == .setUp }.allSatisfy { $0.isDone }
        #expect(setupIsDone)
    }
}
