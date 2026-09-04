import SwiftUI

/// The action layer of the roadmap. Reading advice never completes a medical task.
struct StarterPlanAdviceSheet: View {
    let item: StarterPlanItem
    let condition: HairCondition
    let onDiscussed: (StarterGuidance, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showAppointment = false
    @State private var showVisits = false
    @State private var showLabs = false
    @State private var showTreatments = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(item.title).font(Clinical.headline(28)).foregroundStyle(Clinical.ink)
                    Text(item.why).font(Clinical.body(15)).foregroundStyle(Clinical.secondary)
                    if let caution = item.caution {
                        Text(caution).font(Clinical.caption(13)).foregroundStyle(Clinical.warning)
                    }
                    switch item.kind {
                    case .procedure:
                        section("Bring to the appointment", text: "When the change began; where it appears; scalp symptoms; recent illness, childbirth or weight change; medicines and supplements; existing lab reports and a baseline photo.")
                        section("Ask", text: "What is the likely cause? Are any tests needed? What would you recommend, and when should we review? Mention how the worry is affecting your day, too.")
                        Button("Add a booked appointment") { showAppointment = true }
                            .buttonStyle(ClinicalButtonStyle())
                            .accessibilityIdentifier("starterBookVisit")
                        Button("View visits / record completion") { showVisits = true }
                            .minimumHitTarget()
                        Text("Adding a date does not book the clinic or mark the visit attended. Record completion after the visit.")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    case .guidance(.labs):
                        section("Decide together", text: "Bring previous results first. Your clinician may decide that no tests are needed, choose targeted tests, or investigate another cause. Do not start iron or other supplements just because hair is shedding.")
                        ForEach(LabSuggestion.tests(condition: condition, sex: .other, pregnancy: .unspecified), id: \.self) { test in
                            section(test.title, text: LabSuggestion.why(test))
                        }
                        section("Not a default panel", text: "Vitamin, mineral and hormone tests are not automatically added based only on the pattern you selected or your sex. Further testing depends on clinical findings and any treatment being considered.")
                        Button("I have results to record") { showLabs = true }
                            .buttonStyle(ClinicalButtonStyle())
                        discussionButton(.labs)
                    case .guidance(.care):
                        section("Make the plan specific", text: "Ask about the expected benefit, how to use the treatment, possible side effects, cost and when to reassess. No treatment may also be a reasonable outcome of that conversation.")
                        section("Track, then review", text: "Log the schedule you were given and note side effects. Use consistent photos about monthly. Agree on a review date with your clinician; do not wait for the app's longer-term progress window if symptoms worsen.")
                        Button("Record agreed treatment") { showTreatments = true }
                            .buttonStyle(ClinicalButtonStyle())
                        Button("Add an agreed review appointment") { showAppointment = true }
                            .minimumHitTarget()
                        discussionButton(.care)
                    default: EmptyView()
                    }
                    Text(StarterPlan.safetyNote).font(Clinical.caption(13)).foregroundStyle(Clinical.warning)
                    StarterPlanSources()
                }
                .padding(20)
                .fixedSize(horizontal: false, vertical: true)
            }
            .clinicalScreen()
            .navigationTitle("Your next step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showAppointment) { AddProcedureSheet(initialType: .consultation) }
            .sheet(isPresented: $showVisits) { ProceduresView() }
            .sheet(isPresented: $showLabs) {
                NavigationStack {
                    ProGate(feature: "Lab Results", symbol: "testtube.2",
                            description: "Track ferritin, vitamin D, thyroid and more — part of Hair Compass Pro.") {
                        LabsView()
                    }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showLabs = false } } }
                }
            }
            .sheet(isPresented: $showTreatments) { AddTreatmentSheet() }
        }
        .tint(Clinical.accent)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Clinical.body(16, weight: .semibold)).foregroundStyle(Clinical.ink)
            Text(text).font(Clinical.caption(14)).foregroundStyle(Clinical.secondary)
        }
    }

    private func discussionButton(_ guidance: StarterGuidance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(item.isDone ? "Undo discussion checkmark" : "I've discussed this with my clinician") {
                onDiscussed(guidance, !item.isDone)
                dismiss()
            }
            .minimumHitTarget()
            .accessibilityIdentifier("starterDiscussed.\(guidance.rawValue)")
            Text("A discussion can end with no tests or treatment. This checkmark records the conversation, not a medical result.")
                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
        }
    }
}

struct StarterPlanSources: View {
    var body: some View {
        DisclosureGroup("Why these steps? · Sources") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources checked 4 September 2026. Your clinician tailors this guidance to you.")
                Link("American Academy of Dermatology · Assessment", destination: StarterPlan.diagnosisURL)
                Link("British Association of Dermatologists · Shedding", destination: StarterPlan.sheddingURL)
                Link("American Academy of Dermatology · Scalp warning signs", destination: StarterPlan.symptomsURL)
            }
            .padding(.top, 8)
        }
        .font(Clinical.caption(12))
        .foregroundStyle(Clinical.secondary)
        .tint(Clinical.accent)
    }
}
