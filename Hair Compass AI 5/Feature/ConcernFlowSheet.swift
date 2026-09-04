//
//  ConcernFlowSheet.swift
//  Hair Compass AI 5
//
//  A short evidence lens: choose what pulled attention, answer at most two unknowns, then read
//  four ordered sections and take one useful action. Free-form Wren appears only afterwards.
//

import SwiftUI

struct ConcernFlowSheet: View {
    let record: ConcernRecord
    var onAction: (ConcernKind, ConcernResponse, ConcernAction) -> Void
    var onAskWren: (ConcernKind, ConcernResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kind: ConcernKind?
    @State private var answers: [String] = []

    private var questions: [ConcernQuestion] {
        kind.map { ConcernResponder.questions(for: $0, record: record) } ?? []
    }

    private var response: ConcernResponse? {
        guard let kind, answers.count >= questions.count else { return nil }
        return ConcernResponder.respond(kind: kind, answers: answers, record: record)
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                Group {
                    if let kind, let response {
                        responseView(kind: kind, response: response)
                            .transition(stepTransition)
                    } else if kind != nil, answers.count < questions.count {
                        questionView(questions[answers.count], index: answers.count)
                            .transition(stepTransition)
                    } else {
                        picker
                            .transition(stepTransition)
                    }
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(kind == nil ? "Close" : "Back", action: goBack)
                }
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("HC_CONCERN_RESPONSE") {
                    kind = .moreShedding
                    answers = []
                }
                #endif
            }
        }
    }

    private func goBack() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            if kind == nil {
                dismiss()
            } else if !answers.isEmpty {
                answers.removeLast()
            } else {
                kind = nil
            }
        }
    }

    // MARK: - Choose

    private var picker: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                CompanionView(moment: .listening, variant: .avatar, size: 28)
                Eyebrow(text: "Private · Wren")
            }
            Text("What pulled your attention today?")
                .font(Clinical.headline(22, weight: .semibold))
                .foregroundStyle(Clinical.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Choose the closest concern. Wren will separate what happened from what the record can actually say.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(ConcernKind.allCases) { option in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                            kind = option
                            answers = []
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.symbol)
                                .font(Clinical.body(14, weight: .medium))
                                .foregroundStyle(Clinical.accent)
                                .frame(width: 22)
                            Text(option.title)
                                .font(Clinical.body(15, weight: .medium))
                                .foregroundStyle(Clinical.ink)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(Clinical.body(11, weight: .semibold))
                                .foregroundStyle(Clinical.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Clinical.hairline, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.clinicalPressable)
                    .accessibilityIdentifier("concernOption.\(option.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("concernPicker")
    }

    // MARK: - Clarify

    private func questionView(_ question: ConcernQuestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: kind?.title ?? "")
            Text(question.prompt)
                .font(Clinical.headline(22, weight: .semibold))
                .foregroundStyle(Clinical.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Question \(index + 1) of \(questions.count)")
                .font(Clinical.caption(11.5))
                .foregroundStyle(Clinical.tertiary)
            VStack(spacing: 8) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                            answers.append(option)
                        }
                    } label: {
                        HStack {
                            Text(option)
                                .font(Clinical.body(15, weight: .medium))
                                .foregroundStyle(Clinical.ink)
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Clinical.hairline, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.clinicalPressable)
                    .accessibilityIdentifier("concernAnswer.\(optionIndex)")
                }
            }
        }
    }

    // MARK: - Answer

    private func responseView(kind: ConcernKind, response: ConcernResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                CompanionView(moment: .thinking, variant: .avatar, size: 28)
                Eyebrow(text: "Wren · evidence lens")
            }
            Text(response.headline)
                .font(Clinical.headline(22, weight: .semibold))
                .foregroundStyle(Clinical.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            responseSection("What the record shows", response.recordShows)
            responseSection("What cannot be concluded yet", response.cannotConclude)
            responseSection("What to do next", response.nextStep)
            responseSection(
                "When to seek help",
                response.seekHelp
                    ?? "The record cannot judge urgency. Contact a clinician if a symptom is persistent, severe, or concerning to you.",
                emphasis: response.seekHelp != nil
            )
            Text(response.closure)
                .font(Clinical.caption(12.5))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                if response.primary != .done {
                    Button {
                        onAction(kind, response, response.primary)
                        dismiss()
                    } label: {
                        Text(response.primaryLabel)
                            .font(Clinical.body(13, weight: .medium))
                            .foregroundStyle(Clinical.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Clinical.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.clinicalPressable)
                    .minimumHitTarget()
                    .accessibilityIdentifier("concernPrimary")
                }
                HStack(spacing: 18) {
                    Button("Ask Wren about this") {
                        onAskWren(kind, response)
                    }
                    .font(Clinical.body(13, weight: .medium))
                    .foregroundStyle(Clinical.accent)
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .accessibilityIdentifier("concernAskWren")

                    Button("Done") {
                        onAction(kind, response, .done)
                        dismiss()
                    }
                    .font(Clinical.body(13, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .accessibilityIdentifier("concernDone")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("concernResponse")
    }

    private func responseSection(_ title: String, _ text: String, emphasis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Clinical.eyebrow(10))
                .tracking(1.2)
                .foregroundStyle(emphasis ? Clinical.warning : Clinical.tertiary)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(Clinical.body(14))
                .foregroundStyle(Clinical.ink.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
