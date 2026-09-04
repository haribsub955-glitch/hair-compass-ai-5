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
    @State private var showOptional = false
    @State private var showRecorded = false

    private func isOptional(_ item: StarterPlanItem) -> Bool {
        switch item.kind {
        case .setup(.addTreatments), .setup(.enterLabs), .setup(.reminders): return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsCloser && !showRecorded {
                closer
                Button("Review starting steps") { showRecorded = true }
                    .font(Clinical.caption(13)).foregroundStyle(Clinical.accent).minimumHitTarget()
                if canUndo {
                    undoButton
                }
            } else {
                header
                ForEach(StarterPlanGroup.allCases) { group in
                    let inGroup = items.filter { $0.group == group && !$0.isDone && !isOptional($0) }
                    if !inGroup.isEmpty {
                        groupBlock(group, inGroup)
                    }
                }
                if canUndo {
                    undoButton
                }
                let optional = items.filter { isOptional($0) && !$0.isDone }
                if !optional.isEmpty {
                    DisclosureGroup("Optional setup · \(optional.count)", isExpanded: $showOptional) {
                        ForEach(optional) { row($0) }
                    }
                    .font(Clinical.caption(13)).tint(Clinical.accent)
                }
                let recorded = items.filter(\.isDone)
                if !recorded.isEmpty {
                    DisclosureGroup("Already recorded · \(recorded.count)", isExpanded: $showRecorded) {
                        ForEach(recorded) { row($0) }
                    }
                    .font(Clinical.caption(13)).tint(Clinical.accent)
                }
                Text(StarterPlan.disclaimer)
                    .font(Clinical.caption(11))
                    .foregroundStyle(Clinical.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                StarterPlanSources()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("starterPlanSection")
    }

    /// Dismissing the last open item completes the plan (the closer shows) without losing the
    /// one Undo that reverses that exact dismissal — so this renders under both branches.
    private var undoButton: some View {
        Button("Undo \"Not for me\"") { onUndo() }
            .font(Clinical.caption(12))
            .foregroundStyle(Clinical.accent)
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityIdentifier("starterPlanUndo")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "One step at a time")
            Text("Your starting plan")
                .font(Clinical.headline(22))
                .foregroundStyle(Clinical.ink)
            Text("Start with a photo and a clinician conversation. Then record the care you agree on. You do not have to do everything today.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Long-press a row to say not for me.")
                .font(Clinical.caption(11))
                .foregroundStyle(Clinical.tertiary)
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
        .accessibilityLabel("\(item.title). \(item.why)\(item.caution.map { ". \($0)" } ?? "")\(item.isDone ? ". Done." : "")")
        .accessibilityHint(item.isDone ? "" : "Opens the place to do this")
        .accessibilityAction(named: "Not for me") { onDismiss(item) }
        .accessibilityIdentifier("starterPlanRow.\(item.id)")
    }

    private var closer: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(Clinical.body(16))
                .foregroundStyle(Clinical.accent)
            Text("Your starting steps are recorded or set aside. Keep the review date you agreed with your clinician.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your starting steps are recorded or set aside. Keep the review date you agreed with your clinician.")
        .accessibilityIdentifier("starterPlanCloser")
    }
}
