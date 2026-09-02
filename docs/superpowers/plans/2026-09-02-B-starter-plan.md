# Sub-project B: Starter Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After onboarding, give the person a starting plan — labs worth asking a clinician about, treatment options with evidence tiers, in-clinic options, and five setup steps — previewed on the onboarding finale and kept on the Plan tab as a merged checklist whose done-ness is derived from the record.

**Architecture:** A pure, stateless engine (`StarterPlan`) maps a value-type `Snapshot` of the profile and record to an ordered item list; two builders make that snapshot from SwiftData models (one for the finale, one for the tab) and a parity test proves they agree. One view (`StarterPlanSection`) renders the checklist and reports taps and dismissals through closures; `CareView` owns the snapshot, the dismissed-id storage, and routing each row to the right existing sheet. The onboarding finale becomes a read-only preview of the same items.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (`@Test`/`#expect`). File-system-synchronized groups: new files under the app or test roots compile without project edits.

**Spec:** `docs/superpowers/specs/2026-09-02-first-run-plan-tour-refinement-design.md` (section B)

## Global Constraints

- Framing rule: record-keeping and education, never diagnosis. Labs are "worth asking your clinician about", options are "what the evidence supports". No copy tells the person to start, stop or change anything. Every surface that lists options carries `TreatmentRecommender.disclaimer`.
- No palette change, no new typefaces, no dark mode, no new dependencies.
- No change to what onboarding asks; only the finale (step 14) changes.
- Done-ness is derived from the record; the only stored state is the dismissed-id list under `@AppStorage("starterPlan.dismissed")` (JSON array of strings) and the closer flag `@AppStorage("starterPlan.closerSeen")`.
- Unit tests are Swift Testing (`@Test`, `#expect`), never XCTest.
- Every command runs from the worktree root. Paths contain spaces: quote them. In this worktree session run git only as plain single commands (no `&&`, no pipes, no "git" inside heredocs); write commit messages to a file and use `git commit -F`.
- Simulator: `platform=iOS Simulator,name=iPhone 17 Pro`. Test helper (define once; `DD` is given in the dispatch):

```bash
utest() { xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5Tests/$1" 2>&1 | grep -E 'error:|✘|✔|Test run with|TEST (SUCCEEDED|FAILED)|BUILD FAILED' | tail -20; }
```

After any xcodebuild run, before committing: `git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"`.

- Commit messages end with:
```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

---

## File structure

| File | Responsibility |
|---|---|
| Create `Hair Compass AI 5/Model/StarterPlan.swift` | Engine: groups, kinds, items, lab and procedure tables, setup steps, ordering, completion |
| Create `Hair Compass AI 5/Model/StarterPlanSnapshot.swift` | `StarterPlan.Snapshot.fresh(profile:)` and `.make(...)` from SwiftData models; `StarterPlanDismissals` JSON codec |
| Create `Hair Compass AI 5/Feature/StarterPlanSection.swift` | The checklist view: header, grouped rows, dismiss, undo, closer |
| Create `Hair Compass AI 5/Feature/Onboarding/StarterPlanFinale.swift` | Read-only preview on onboarding step 14 |
| Modify `Hair Compass AI 5/Feature/CareView.swift` | Snapshot, dismissals, section placement, row routing, ritual copy, scroll anchor, `onLogToday` |
| Modify `Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift:660-676` | `finale` renders `StarterPlanFinale` |
| Modify `Hair Compass AI 5/App/RootView.swift:174, 374-377` | pass `onLogToday`; land on the Plan tab after onboarding |
| Create `Hair Compass AI 5Tests/StarterPlanTests.swift` | Engine tables, ordering, done-derivation, dismissal, completion |
| Create `Hair Compass AI 5Tests/StarterPlanSnapshotTests.swift` | Builders, parity, dismissal codec |

---

### Task 1: `StarterPlan` engine

**Files:**
- Create: `Hair Compass AI 5/Model/StarterPlan.swift`
- Test: `Hair Compass AI 5Tests/StarterPlanTests.swift`

**Interfaces:**
- Consumes (existing): `HairCondition`, `BiologicalSex`, `PregnancyStatus`, `LabTest`, `TreatmentClass`, `ProcedureType`, `EvidenceTier` (`Model/Enums.swift`, each with `.title`); `TreatmentRecommender.options(condition:sex:) -> [RecommendedOption]` with `.id/.name/.tier/.summary/.caution/.action` (`Model/TreatmentRecommender.swift:27-41, 57`); `RecommendedAction` cases `.addToPlan(TreatmentClass)`, `.addLabResult(LabTest)`, `.scheduleDoctorVisit`, `.startPatchPhotoSeries`, `.recordTrigger`, `.reviewPregnancyCaution`; `ProcedureGuide.shortExpectation(for:)` (`Model/ProcedureGuide.swift:13`).
- Produces:
  - `enum StarterPlanGroup: String, CaseIterable, Identifiable { case setUp, askClinician, evidenceOptions, inClinic; var eyebrow: String }`
  - `enum StarterSetupStep: String, CaseIterable { case logToday, addTreatments, enterLabs, baselinePhoto, reminders }`
  - `enum StarterPlanKind: Equatable { case lab(LabTest); case treatment(optionID: String, action: RecommendedAction?); case procedure(ProcedureType); case setup(StarterSetupStep) }`
  - `struct StarterPlanItem: Identifiable, Equatable { id, group, kind, title, why, caution, isDone }`
  - `enum LabSuggestion { static func tests(condition:sex:pregnancy:) -> [LabTest]; static func why(_:) -> String; static let pregnancyCaution: String }`
  - `enum ProcedureSuggestion { static func types(condition:) -> [ProcedureType] }`
  - `enum StarterPlan { struct Snapshot: Equatable {...}; static func items(for:) -> [StarterPlanItem]; static func isComplete(_:) -> Bool }`

- [ ] **Step 1: Write the failing tests**

Create `Hair Compass AI 5Tests/StarterPlanTests.swift`:

```swift
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
            #expect(done(step) == true, step)
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `utest StarterPlanTests`
Expected: build failure — `StarterPlan`, `LabSuggestion`, `ProcedureSuggestion` cannot be found.

- [ ] **Step 3: Write the engine**

Create `Hair Compass AI 5/Model/StarterPlan.swift`:

```swift
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
    static let pregnancyCaution = "Pregnancy and breastfeeding change what's normal — tell your clinician when you ask."

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

    static func isPregnancyRelated(_ status: PregnancyStatus) -> Bool {
        switch status {
        case .pregnant, .breastfeeding, .tryingToConceive: return true
        case .no, .unspecified: return false
        }
    }

    static func why(_ test: LabTest) -> String {
        switch test {
        case .ferritin: return "Low iron stores are a common, fixable reason for shedding."
        case .tsh: return "Thyroid changes often show up in hair before anywhere else."
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
```

If `LabTest.dheaS` or another case name in the table does not compile, check `grep -n 'case ferritin' "Hair Compass AI 5/Model/Enums.swift"` and use the exact case names from that line; the tests use the same names.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `utest StarterPlanTests`
Expected: `✔ Test run with 17 tests in 1 suite passed`. If `treatmentOptionsAreTopThreeStrongOrModerate` fails on ids, print `TreatmentRecommender.options(condition: .androgenetic, sex: .male).map { ($0.id, $0.tier) }` in a scratch test to confirm the first three strong/moderate ids and correct the test's expectation to match the recommender — the recommender is the authority, never edited here.

- [ ] **Step 5: Commit**

Write the message to `/private/tmp/claude-501/-Users-haribazri-Hair-Compass-AI-5/ff0a543b-cd29-4e99-83c4-0d3dc9b8f4cb/scratchpad/msg-B1.txt`:

```
StarterPlan: the starting plan as a pure function of profile and record

Four groups — set up, ask your clinician about, options with evidence,
in-clinic options — with the lab table per condition and sex, pregnancy
moving ferritin and TSH to the front, the top three evidence-tiered
treatment options, condition-filtered procedures, and five setup steps.
Done-ness is derived from a value snapshot of the record; dismissed ids
are the only stored input. Seventeen tests pin the tables and the rules.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

Then: `git add "Hair Compass AI 5/Model/StarterPlan.swift" "Hair Compass AI 5Tests/StarterPlanTests.swift"` and `git commit -F "<that file>"`.

---

### Task 2: Snapshot builders and the dismissed-id codec

**Files:**
- Create: `Hair Compass AI 5/Model/StarterPlanSnapshot.swift`
- Test: `Hair Compass AI 5Tests/StarterPlanSnapshotTests.swift`

**Interfaces:**
- Consumes: `StarterPlan.Snapshot` (Task 1); SwiftData models `Profile` (`.condition`, `.sex`, `.pregnancyStatus`), `LabResult` (`.test`), `Treatment` (`.treatmentClass`), `PhotoRecord`, `ProcedureAppointment` (`.type`), `DailyEntry` (`.date`) — all in `Model/Models.swift`. Check the exact computed property names with `grep -n 'var test: LabTest\|var treatmentClass: TreatmentClass\|var type: ProcedureType' "Hair Compass AI 5/Model/Models.swift"` and use what is there.
- Produces:
  - `extension StarterPlan.Snapshot { static func fresh(profile: Profile) -> Self; static func make(profile: Profile, labs: [LabResult], treatments: [Treatment], photos: [PhotoRecord], procedures: [ProcedureAppointment], entries: [DailyEntry], remindersEnabled: Bool, dismissed: Set<String>, today: Date = .now, calendar: Calendar = .current) -> Self }`
  - `enum StarterPlanDismissals { static let key = "starterPlan.dismissed"; static func decode(_ json: String) -> Set<String>; static func encode(_ ids: Set<String>) -> String }`

- [ ] **Step 1: Write the failing tests**

Create `Hair Compass AI 5Tests/StarterPlanSnapshotTests.swift`:

```swift
//
//  StarterPlanSnapshotTests.swift
//  Hair Compass AI 5Tests
//
//  The finale and the Plan tab must show the same plan. `fresh` (finale) and `make` over an
//  empty record (tab, a moment later) have to agree item for item.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct StarterPlanSnapshotTests {

    private func profile(condition: HairCondition, sex: BiologicalSex, pregnancy: PregnancyStatus = .no) -> Profile {
        let p = Profile()
        p.condition = condition
        p.sex = sex
        p.pregnancyStatus = pregnancy
        return p
    }

    @Test func finaleAndTabAgreeOnAFreshRecord() {
        let p = profile(condition: .androgenetic, sex: .female, pregnancy: .breastfeeding)
        let finale = StarterPlan.Snapshot.fresh(profile: p)
        let tab = StarterPlan.Snapshot.make(
            profile: p, labs: [], treatments: [], photos: [], procedures: [], entries: [],
            remindersEnabled: false, dismissed: []
        )
        // The finale is shown before finish() seeds today's entry, so it counts today as logged;
        // the tab derives it. Everything else must be identical.
        var tabLogged = tab
        tabLogged.loggedToday = true
        #expect(finale == tabLogged)
        #expect(StarterPlan.items(for: finale).map(\.id) == StarterPlan.items(for: tabLogged).map(\.id))
    }

    @Test func makeDerivesDoneFromTheRecord() {
        let p = profile(condition: .telogenEffluvium, sex: .female)
        let lab = LabResult()
        lab.test = .ferritin
        let treatment = Treatment()
        treatment.treatmentClass = .minoxidil
        let entryToday = DailyEntry()
        entryToday.date = Date()
        let s = StarterPlan.Snapshot.make(
            profile: p, labs: [lab], treatments: [treatment], photos: [PhotoRecord()],
            procedures: [], entries: [entryToday], remindersEnabled: true, dismissed: ["lab.zinc"]
        )
        #expect(s.labTests == [.ferritin])
        #expect(s.treatmentClasses == [.minoxidil])
        #expect(s.hasAnyTreatment && s.hasAnyLab && s.hasBaselinePhoto && s.remindersEnabled && s.loggedToday)
        #expect(s.dismissed == ["lab.zinc"])
    }

    @Test func loggedTodayIsCalendarDayNotTwentyFourHours() {
        let p = profile(condition: .unsure, sex: .male)
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 23, minute: 50))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 23, minute: 55))!
        let e = DailyEntry()
        e.date = yesterday
        let s = StarterPlan.Snapshot.make(
            profile: p, labs: [], treatments: [], photos: [], procedures: [], entries: [e],
            remindersEnabled: false, dismissed: [], today: today, calendar: cal
        )
        #expect(s.loggedToday == false)
    }

    @Test func dismissalsRoundTripThroughJSON() {
        let ids: Set<String> = ["lab.zinc", "setup.reminders"]
        let json = StarterPlanDismissals.encode(ids)
        #expect(StarterPlanDismissals.decode(json) == ids)
        #expect(StarterPlanDismissals.decode("").isEmpty)
        #expect(StarterPlanDismissals.decode("not json").isEmpty)
        #expect(StarterPlanDismissals.encode([]) == "[]")
    }
}
```

If `LabResult()`, `Treatment()`, `DailyEntry()` or `PhotoRecord()` have no zero-argument initializer, check `grep -n 'init(' "Hair Compass AI 5/Model/Models.swift"` and use the initializer with every parameter defaulted or the minimal required ones; the assertions do not depend on other fields.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `utest StarterPlanSnapshotTests`
Expected: build failure — `fresh`, `make`, `StarterPlanDismissals` not found.

- [ ] **Step 3: Write the builders and codec**

Create `Hair Compass AI 5/Model/StarterPlanSnapshot.swift`:

```swift
//
//  StarterPlanSnapshot.swift
//  Hair Compass AI 5
//
//  The two places the starting plan is shown build their snapshot here, so they cannot drift:
//  the onboarding finale from the freshly filled profile (`fresh`), and the Plan tab from the
//  live record (`make`). `StarterPlanDismissals` is the codec for the one piece of stored state.
//

import Foundation

extension StarterPlan.Snapshot {

    /// The finale's view of the record: profile answers, nothing recorded yet. `loggedToday` is
    /// true because `OnboardingFlow.finish()` seeds today's entry the moment the finale closes.
    static func fresh(profile: Profile) -> StarterPlan.Snapshot {
        StarterPlan.Snapshot(
            condition: profile.condition, sex: profile.sex, pregnancy: profile.pregnancyStatus,
            labTests: [], treatmentClasses: [],
            hasAnyTreatment: false, hasAnyLab: false, hasBaselinePhoto: false,
            procedureTypes: [], remindersEnabled: false, loggedToday: true, dismissed: []
        )
    }

    /// The Plan tab's view of the record, derived on every body evaluation.
    static func make(
        profile: Profile,
        labs: [LabResult],
        treatments: [Treatment],
        photos: [PhotoRecord],
        procedures: [ProcedureAppointment],
        entries: [DailyEntry],
        remindersEnabled: Bool,
        dismissed: Set<String>,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> StarterPlan.Snapshot {
        StarterPlan.Snapshot(
            condition: profile.condition, sex: profile.sex, pregnancy: profile.pregnancyStatus,
            labTests: Set(labs.map(\.test)),
            treatmentClasses: Set(treatments.map(\.treatmentClass)),
            hasAnyTreatment: !treatments.isEmpty,
            hasAnyLab: !labs.isEmpty,
            hasBaselinePhoto: !photos.isEmpty,
            procedureTypes: Set(procedures.map(\.type)),
            remindersEnabled: remindersEnabled,
            loggedToday: entries.contains { calendar.isDate($0.date, inSameDayAs: today) },
            dismissed: dismissed
        )
    }
}

/// "Not for me" is the only stored state of the starting plan: a JSON array of item ids in
/// `UserDefaults`, read and written through `@AppStorage(StarterPlanDismissals.key)`.
enum StarterPlanDismissals {
    static let key = "starterPlan.dismissed"

    static func decode(_ json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    static func encode(_ ids: Set<String>) -> String {
        let data = (try? JSONEncoder().encode(ids.sorted())) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
```

Adjust the three key paths (`\.test`, `\.treatmentClass`, `\.type`) to the model's real computed property names found in Step 1's grep.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `utest StarterPlanSnapshotTests`
Expected: `✔ Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

Message file `.../scratchpad/msg-B2.txt`:

```
StarterPlan snapshots: one builder for the finale, one for the tab

`fresh(profile:)` is the finale's view (answers only, today counted as
logged because finish() seeds it); `make(...)` derives everything from
the live record on each body evaluation. A parity test proves the two
agree on a fresh record. The dismissed-id list has a JSON codec.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

`git add "Hair Compass AI 5/Model/StarterPlanSnapshot.swift" "Hair Compass AI 5Tests/StarterPlanSnapshotTests.swift"` then `git commit -F`.

---

### Task 3: The checklist on the Plan tab

**Files:**
- Create: `Hair Compass AI 5/Feature/StarterPlanSection.swift`
- Modify: `Hair Compass AI 5/Feature/CareView.swift` (state near `:26-67`; body `:100-107`; `planRitualPlate` `:491-503`; `remindersCard` (add `.id("reminders")`); new routing func next to `presentRecommendedAction` `:327`)
- Modify: `Hair Compass AI 5/App/RootView.swift:174`

**Interfaces:**
- Consumes: `StarterPlan.items(for:)`, `StarterPlan.isComplete`, `StarterPlanItem`, `StarterPlanGroup.eyebrow`, `StarterPlanKind` (Task 1); `StarterPlan.Snapshot.make`, `StarterPlanDismissals` (Task 2); existing CareView state `showAdd`, `recommendedTreatmentClass`, `recommendedLabTest`, `showRecommendedLab`, `showRecommendedPhoto`, `showInClinicOptions`, `showRecommender`, `remindersExpanded`, `presentRecommendedAction(_:)`; `notifications.isEnabled`; `deepLinks` (`DeepLinkRouter.openLogRequested`).
- Produces:
  - `struct StarterPlanSection: View { init(items: [StarterPlanItem], showsCloser: Bool, canUndo: Bool, onTap: @escaping (StarterPlanItem) -> Void, onDismiss: @escaping (StarterPlanItem) -> Void, onUndo: @escaping () -> Void) }`
  - `CareView.init(onLogToday: (() -> Void)? = nil)` — `var onLogToday: (() -> Void)? = nil`

- [ ] **Step 1: Write the section view**

Create `Hair Compass AI 5/Feature/StarterPlanSection.swift`:

```swift
//
//  StarterPlanSection.swift
//  Hair Compass AI 5
//
//  "Set up your plan": the starting plan as a checklist at the top of the Plan tab. Rows are
//  grouped under the plan's four eyebrows; a tap opens the right sheet (the owner decides which,
//  through `onTap`); swipe or long-press says "Not for me". Done rows keep their place with a
//  filled circle, and the whole section hands over to the ritual once everything is done or
//  dismissed. No enclosing card — hairline rules and spacing, as the rest of Plan.
//

import SwiftUI

struct StarterPlanSection: View {
    let items: [StarterPlanItem]
    let showsCloser: Bool
    let canUndo: Bool
    let onTap: (StarterPlanItem) -> Void
    let onDismiss: (StarterPlanItem) -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsCloser {
                closer
            } else {
                header
                ForEach(StarterPlanGroup.allCases) { group in
                    let inGroup = items.filter { $0.group == group }
                    if !inGroup.isEmpty {
                        groupBlock(group, inGroup)
                    }
                }
                if canUndo {
                    Button("Undo \"Not for me\"") { onUndo() }
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.accent)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("starterPlanUndo")
                }
                Text(TreatmentRecommender.disclaimer)
                    .font(Clinical.caption(11))
                    .foregroundStyle(Clinical.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("starterPlanSection")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "Set up your plan")
            Text("Your starting plan")
                .font(Clinical.headline(22))
                .foregroundStyle(Clinical.ink)
            Text("What's worth asking about, what the evidence supports, and the few things that make the record useful. Tick them off, or say not for me.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func groupBlock(_ group: StarterPlanGroup, _ rows: [StarterPlanItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: group.eyebrow)
                .padding(.top, 6)
                .padding(.bottom, 4)
            Divider().overlay(Clinical.hairline)
            ForEach(rows) { item in
                row(item)
                Divider().overlay(Clinical.hairline)
            }
        }
    }

    private func row(_ item: StarterPlanItem) -> some View {
        Button { onTap(item) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(Clinical.body(18))
                    .foregroundStyle(item.isDone ? Clinical.accent : Clinical.tertiary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(Clinical.body(15, weight: .medium))
                        .foregroundStyle(item.isDone ? Clinical.secondary : Clinical.ink)
                        .strikethrough(item.isDone, color: Clinical.tertiary)
                    Text(item.why)
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caution = item.caution {
                        Text(caution)
                            .font(Clinical.caption(11))
                            .foregroundStyle(Clinical.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(Clinical.body(11, weight: .semibold))
                    .foregroundStyle(Clinical.tertiary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clinicalPressable)
        .contextMenu {
            Button("Not for me", role: .destructive) { onDismiss(item) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Not for me", role: .destructive) { onDismiss(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.why)\(item.isDone ? ". Done." : "")")
        .accessibilityHint(item.isDone ? "" : "Opens the place to do this")
        .accessibilityIdentifier("starterPlanRow.\(item.id)")
    }

    private var closer: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(Clinical.body(16))
                .foregroundStyle(Clinical.accent)
            Text("Starting plan done — your ritual takes it from here.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("starterPlanCloser")
    }
}
```

`.swipeActions` only takes effect inside a `List`; outside one it is inert, so the context menu is the working "Not for me" on this scroll view. Keep both: the swipe costs nothing and works if the section ever moves into a `List`.

- [ ] **Step 2: Wire the section into CareView**

In `Hair Compass AI 5/Feature/CareView.swift`:

(a) Declare the callback and the stored state. Directly after `struct CareView: View {` add:

```swift
    /// From RootView: switch to Today and open the log — the "Log today" setup row's action.
    var onLogToday: (() -> Void)? = nil
```

Next to the other `@AppStorage` declarations (near `:65-67`) add:

```swift
    @AppStorage(StarterPlanDismissals.key) private var starterPlanDismissedJSON = "[]"
    @AppStorage("starterPlan.closerSeen") private var starterPlanCloserSeen = false
    /// The last dismissal, so one Undo can bring it back until the next launch.
    @State private var lastStarterDismissal: String?
```

(b) Compute the plan. Next to the other private computed properties (for example right before `private var planRitualPlate`) add:

```swift
    // MARK: Starting plan

    private var starterPlanItems: [StarterPlanItem] {
        guard let profile = profiles.first else { return [] }
        let snapshot = StarterPlan.Snapshot.make(
            profile: profile, labs: labs, treatments: treatments, photos: photoRecords,
            procedures: procedureAppointments, entries: entries,
            remindersEnabled: notifications.isEnabled,
            dismissed: StarterPlanDismissals.decode(starterPlanDismissedJSON)
        )
        return StarterPlan.items(for: snapshot)
    }

    private var starterPlanIsComplete: Bool { StarterPlan.isComplete(starterPlanItems) }

    private func starterPlanSection(proxy: ScrollViewProxy) -> some View {
        StarterPlanSection(
            items: starterPlanItems,
            showsCloser: starterPlanIsComplete,
            canUndo: lastStarterDismissal != nil,
            onTap: { openStarterPlanItem($0, proxy: proxy) },
            onDismiss: { item in
                var ids = StarterPlanDismissals.decode(starterPlanDismissedJSON)
                ids.insert(item.id)
                starterPlanDismissedJSON = StarterPlanDismissals.encode(ids)
                lastStarterDismissal = item.id
            },
            onUndo: {
                guard let id = lastStarterDismissal else { return }
                var ids = StarterPlanDismissals.decode(starterPlanDismissedJSON)
                ids.remove(id)
                starterPlanDismissedJSON = StarterPlanDismissals.encode(ids)
                lastStarterDismissal = nil
            }
        )
        // The closer shows once the plan completes; leaving the tab marks it seen so the section
        // is gone on the next visit.
        .onDisappear { if starterPlanIsComplete { starterPlanCloserSeen = true } }
    }

    /// Each row opens the place where the thing gets done. Nothing here writes to the record.
    private func openStarterPlanItem(_ item: StarterPlanItem, proxy: ScrollViewProxy) {
        switch item.kind {
        case .lab(let test):
            recommendedLabTest = test
            showRecommendedLab = true
        case .treatment(_, let action):
            if let action { presentRecommendedAction(action) } else { showRecommender = true }
        case .procedure:
            showInClinicOptions = true
        case .setup(let step):
            switch step {
            case .logToday: onLogToday?()
            case .addTreatments: showAdd = true
            case .enterLabs: recommendedLabTest = .ferritin; showRecommendedLab = true
            case .baselinePhoto: showRecommendedPhoto = true
            case .reminders:
                remindersExpanded = true
                withAnimation { proxy.scrollTo("reminders", anchor: .top) }
            }
        }
    }
```

(c) Place the section. In `body`, replace:

```swift
                if hasRecentSevereSideEffect { severeSideEffectBanner.staggeredEntrance(index: 2) }
                if !routine.isEmpty {
```

with:

```swift
                if hasRecentSevereSideEffect { severeSideEffectBanner.staggeredEntrance(index: 2) }
                // The starting plan leads the page until every item is done or dismissed; the
                // one-line closer shows once, then the section retires on the next visit.
                if profiles.first != nil, !(starterPlanIsComplete && starterPlanCloserSeen) {
                    starterPlanSection(proxy: proxy).staggeredEntrance(index: 2)
                }
                if !routine.isEmpty {
```

(d) Anchor the reminders card: find `remindersCard.staggeredEntrance(index: 5)` in `body` and change it to `remindersCard.id("reminders").staggeredEntrance(index: 5)`.

(e) Rewrite the ritual plate copy. In `planRitualPlate`, replace the `Text("Add a treatment and it becomes a daily step here. ...")` line's string with:

```swift
            Text("Each treatment you add becomes a daily step here, so a month of tracking can be compared with the next. Start with the checklist above; the ritual is what makes the record honest.")
```

- [ ] **Step 3: Pass the Today hand-off from RootView**

In `Hair Compass AI 5/App/RootView.swift`, replace `case .care: CareView()` with:

```swift
        case .care: CareView(onLogToday: {
            tab = .today
            deepLinks.openLogRequested = true
        })
```

- [ ] **Step 4: Build and run the affected suites**

Run: `utest StarterPlanTests` then `utest StarterPlanSnapshotTests` then `utest CareSchedulingTests`.
Expected: all `TEST SUCCEEDED`, no `error:` lines.

- [ ] **Step 5: See it in the simulator**

```bash
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -quiet 2>&1 | grep -E 'error:'
xcrun simctl terminate booted harib.Hair-Compass-AI-5 2>/dev/null
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/Hair Compass AI 5.app"
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_NORITUAL HC_TAB care
sleep 3
xcrun simctl io booted screenshot "$DD/../plan-checklist.png"
```

Open the screenshot with the Read tool. Expected: "Set up your plan" leads the Plan tab with grouped rows; with the simulator's one-day record, "Log today" shows a filled circle and the others are empty.

- [ ] **Step 6: Commit**

Message file `.../scratchpad/msg-B3.txt`:

```
Plan: the starting plan leads the page as a checklist

StarterPlanSection renders the four groups with check circles, one-line
whys and cautions; a tap opens the right sheet (lab with the test
preselected, treatment with its class, in-clinic options, guided
capture, reminders, or Today's log through RootView), a long-press says
"Not for me" with one Undo. Done-ness comes from the record on every
body evaluation; the dismissed ids are the only stored state. The
ritual plate's copy now points at the checklist.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

`git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"`, then `git add "Hair Compass AI 5/Feature/StarterPlanSection.swift" "Hair Compass AI 5/Feature/CareView.swift" "Hair Compass AI 5/App/RootView.swift"`, then `git commit -F`.

---

### Task 4: Onboarding finale: "Your starting plan"

**Files:**
- Create: `Hair Compass AI 5/Feature/Onboarding/StarterPlanFinale.swift`
- Modify: `Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift:660-676` (`finale`)
- Modify: `Hair Compass AI 5/App/RootView.swift:374-377` (land on Plan)

**Interfaces:**
- Consumes: `StarterPlan.Snapshot.fresh(profile:)`, `StarterPlan.items(for:)`, `StarterPlanGroup.eyebrow` (Tasks 1–2); `OnboardingFlow.finish()` (existing, `:206`), its `primary(_:action:)` button helper, `FallingHairView`.
- Produces: `struct StarterPlanFinale: View { init(profile: Profile, onOpenPlan: @escaping () -> Void) }`

- [ ] **Step 1: Write the finale view**

Create `Hair Compass AI 5/Feature/Onboarding/StarterPlanFinale.swift`:

```swift
//
//  StarterPlanFinale.swift
//  Hair Compass AI 5
//
//  Onboarding's last screen: the starting plan as a read-only preview — the same items the Plan
//  tab will show as a checklist a moment later (`StarterPlan.Snapshot.fresh` ↔ `.make` parity is
//  tested). Nothing here writes to the record; "Open my plan" hands over to the tab.
//

import SwiftUI

struct StarterPlanFinale: View {
    let profile: Profile
    let onOpenPlan: () -> Void

    private var items: [StarterPlanItem] {
        StarterPlan.items(for: .fresh(profile: profile))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Your starting plan")
                        Text(profile.name.isEmpty ? "Here's where to begin" : "Here's where to begin, \(profile.name)")
                            .font(Clinical.headline(28))
                            .foregroundStyle(Clinical.ink)
                        Text("Built from your answers. It lives on the Plan tab as a checklist — nothing here is decided for you.")
                            .font(Clinical.caption(14))
                            .foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 24)

                    ForEach(StarterPlanGroup.allCases) { group in
                        let rows = items.filter { $0.group == group }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Eyebrow(text: group.eyebrow).padding(.bottom, 4)
                                Divider().overlay(Clinical.hairline)
                                ForEach(rows) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(Clinical.body(15, weight: .medium))
                                            .foregroundStyle(Clinical.ink)
                                        Text(item.why)
                                            .font(Clinical.caption(12))
                                            .foregroundStyle(Clinical.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Divider().overlay(Clinical.hairline)
                                }
                            }
                        }
                    }

                    Text(TreatmentRecommender.disclaimer)
                        .font(Clinical.caption(11))
                        .foregroundStyle(Clinical.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 24)
            }

            Button("Open my plan", action: onOpenPlan)
                .buttonStyle(ClinicalButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .accessibilityIdentifier("onboardOpenPlan")
        }
        .accessibilityIdentifier("starterPlanFinale")
    }
}
```

- [ ] **Step 2: Render it as the finale**

In `Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift`, replace the whole `private var finale: some View { ... }` (the `ZStack` with `FallingHairView`, the checkmark seal, "You're all set" and `primary("Start tracking") { finish() }`) with:

```swift
    /// Step 14: the starting plan, previewed. `finish()` seeds day one and hands over; the
    /// Plan tab then shows the same items as a checklist.
    private var finale: some View {
        StarterPlanFinale(profile: profile) { finish() }
    }
```

If `FallingHairView` is now unreferenced anywhere (`grep -rn 'FallingHairView(' "Hair Compass AI 5"`), leave the type in place — it is shared art, not this task's to remove.

- [ ] **Step 3: Land on the Plan tab after onboarding**

In `Hair Compass AI 5/App/RootView.swift`, change the onboarding cover's `onFinish` closure:

```swift
                OnboardingFlow(profile: profile, onFinish: {
                    showOnboarding = false
                    tab = .care
                    if !hasSeenTutorial { showTutorial = true }
                })
```

- [ ] **Step 4: Build, run the onboarding suites, and see it**

Run: `utest OnboardingUpgradeTests` then `utest LaunchPresentationStateTests`. Expected: `TEST SUCCEEDED`.

Simulator:

```bash
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -quiet 2>&1 | grep -E 'error:'
xcrun simctl terminate booted harib.Hair-Compass-AI-5 2>/dev/null
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/Hair Compass AI 5.app"
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_NORITUAL HC_ONBOARD HC_ONBOARD_STEP 14
sleep 3
xcrun simctl io booted screenshot "$DD/../finale.png"
```

Open the screenshot. Expected: "Your starting plan" with the grouped read-only rows and the "Open my plan" button.

Then run the UI suite once (it walks the cover to the name step and exercises the paywall step; the finale change must not break either):

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5UITests" 2>&1 | grep -E "Test Case .* failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3
```

Expected: `Executed 9 tests, with 0 failures` (8 existing plus `testEraseReturnsToOnboarding` from sub-project A).

- [ ] **Step 5: Full unit suite, then commit**

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5Tests" 2>&1 | grep -E '✘|Test run with|TEST (SUCCEEDED|FAILED)|BUILD FAILED' | tail -3
```

Expected: every test passing (the count is the suite's previous total plus 21).

Message file `.../scratchpad/msg-B4.txt`:

```
Onboarding ends on the starting plan

Step 14 is now StarterPlanFinale: the four groups as a read-only preview
built from the fresh profile, the disclaimer, and one button, "Open my
plan", which seeds day one as before and lands on the Plan tab where the
same items wait as a checklist.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

`git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"`, `git add "Hair Compass AI 5/Feature/Onboarding/StarterPlanFinale.swift" "Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift" "Hair Compass AI 5/App/RootView.swift"`, `git commit -F`.

---

### Task 5: Land sub-project B

Controller task (git bookkeeping): fast-forward `feat/agent-profile-memory` to this branch, push, merge `rebuild/clinical-minimal` forward, push, and leave the simulator on the new build.

---

## Self-review notes

- Spec B1: engine, lab table, pregnancy rule, treatments (top three strong/moderate), procedures table, setup steps, ordering, persistence of dismissals only — Tasks 1–2. Deviation: `Snapshot` carries value fields instead of a `Profile` reference so the engine is testable without SwiftData; the builders in Task 2 are the only place models are read.
- Spec B2: finale preview, single button, `finish()` unchanged, parity test — Task 4 and Task 2's `finaleAndTabAgreeOnAFreshRecord`.
- Spec B3: section placement, row routing per kind, dismissal with Undo, closer and retirement, ritual copy — Task 3. Deviation: the closer retires on the next visit to the tab rather than the next launch (simpler, same effect).
- Names consistent across tasks: `StarterPlan.Snapshot`, `StarterPlan.items(for:)`, `StarterPlan.isComplete`, `StarterPlanItem`, `StarterPlanGroup`, `StarterPlanKind`, `StarterSetupStep`, `LabSuggestion`, `ProcedureSuggestion`, `StarterPlanDismissals.key/encode/decode`, `StarterPlan.Snapshot.fresh/make`, `StarterPlanSection`, `StarterPlanFinale`, `CareView.onLogToday`.
