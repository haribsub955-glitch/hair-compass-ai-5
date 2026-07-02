import SwiftData
import SwiftUI

/// One-time baseline capture — the highest-value fields (family history, condition) up front.
/// Also reused as the editable profile from the Today header.
struct BaselineFlow: View {
    @Bindable var profile: Profile
    @Environment(\.dismiss) private var dismiss

    private let ageBands = ["Under 25", "26–35", "36–45", "46–55", "56+"]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    intro

                    field("Your name") {
                        TextField("Name", text: $profile.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(12)
                            .background(Clinical.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                            .accessibilityIdentifier("baselineName")
                    }

                    field("Biological sex") {
                        ClinicalSegmented(options: BiologicalSex.allCases, label: { $0.title }, selection: $profile.sex)
                        Text("Sets the staging scale: \(profile.sex.stagingScaleName).")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }

                    field("Age") {
                        chips(ageBands, selected: profile.ageBand) { profile.ageBand = $0 }
                    }

                    field("What are you tracking?") {
                        VStack(spacing: 8) {
                            ForEach(HairCondition.allCases) { c in
                                conditionRow(c)
                            }
                        }
                    }

                    field("Family history of hair loss") {
                        chips(FamilyHistory.allCases.map(\.title), selected: profile.familyHistory.title) { title in
                            if let match = FamilyHistory.allCases.first(where: { $0.title == title }) {
                                profile.familyHistory = match
                            }
                        }
                        Text("The single strongest measured risk factor for pattern loss.")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }

                    field("Baseline stage (optional)") {
                        TextField("e.g. \(profile.sex.stagingScaleName) III", text: $profile.baselineStage)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(12)
                            .background(Clinical.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                    }

                    Button("Save baseline", action: complete)
                        .buttonStyle(ClinicalButtonStyle())
                        .disabled(profile.name.trimmingCharacters(in: .whitespaces).count < 2)
                        .opacity(profile.name.trimmingCharacters(in: .whitespaces).count < 2 ? 0.5 : 1)
                        .accessibilityIdentifier("baselineSave")
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .clinicalScreen()
            .navigationTitle("Baseline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if profile.hasOnboarded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { complete() }
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Set up once")
            Text("A few facts that shape everything")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Clinical.ink)
            Text("These are the signals a dermatologist weighs first. You'll only set them once.")
                .font(.system(size: 14))
                .foregroundStyle(Clinical.secondary)
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
            content()
        }
    }

    private func conditionRow(_ c: HairCondition) -> some View {
        let on = profile.condition == c
        return Button {
            profile.condition = c
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Clinical.accent : Clinical.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                    Text(c.summary).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(on ? Clinical.accentSoft : Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Clinical.accent.opacity(0.4) : Clinical.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("condition_\(c.rawValue)")
    }

    private func chips(_ items: [String], selected: String, onPick: @escaping (String) -> Void) -> some View {
        FlowChips(items: items, selected: selected, onPick: onPick)
    }

    private func complete() {
        profile.hasOnboarded = true
        dismiss()
    }
}

/// Horizontally scrolling chip row — robust across label widths, no layout math.
private struct FlowChips: View {
    let items: [String]
    let selected: String
    let onPick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let on = item == selected
                    Button {
                        onPick(item)
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(item)
                            .font(.system(size: 14, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(on ? Clinical.ink : Clinical.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }
}
