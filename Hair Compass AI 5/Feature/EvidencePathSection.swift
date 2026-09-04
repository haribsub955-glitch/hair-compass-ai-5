//
//  EvidencePathSection.swift
//  Hair Compass AI 5
//
//  A living field-journal path down the Plan page. Its motion expresses progress once: the rail
//  reveals from top to bottom, reached nodes settle in order, and the current marker lands without
//  pulsing. Milestones open into five plain-language statements. Per-treatment consistency sits
//  below as thin strands, with no percentage at all until an action has actually become scorable.
//

import SwiftUI

struct EvidencePathSection: View {
    let phase: EvidencePhase
    let milestones: [EvidenceMilestone]
    let strands: [PlanStrand]
    let overall: PlanAdherence.Consistency?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("evidencePath.enteredKey") private var enteredKey = ""
    @State private var expandedWeek: Int?
    @State private var revealsRail = false
    @State private var revealsNodes = false
    @State private var settlesCurrent = false
    @State private var entranceTask: Task<Void, Never>?

    private var isStatic: Bool { reduceMotion || MotionQA.isStatic }
    private var entranceKey: String {
        "\(Int(phase.start.timeIntervalSince1970))|\(phase.week)|\(phase.nextReviewWeek)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            path
            strandsBlock
        }
        .onAppear { enterIfNeeded() }
        .onChange(of: entranceKey) { _, _ in enterIfNeeded(reset: true) }
        .onDisappear {
            entranceTask?.cancel()
            entranceTask = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evidencePath")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Your evidence path")
                Spacer(minLength: 12)
                Text("Day \(phase.dayNumber)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Clinical.accent)
                    .monospacedDigit()
            }
            Text("The path you are building")
                .font(Clinical.headline(22, weight: .semibold))
                .foregroundStyle(Clinical.ink)
            Text("Checkpoints protect a slow process from being judged day by day.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Milestone path

    private var path: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                milestoneRow(milestone, index: index)
                if shouldPlaceCurrent(after: milestone, index: index) {
                    currentRow(index: index + 1)
                }
            }
        }
    }

    private func shouldPlaceCurrent(after milestone: EvidenceMilestone, index: Int) -> Bool {
        guard milestone.state == .reached, index + 1 < milestones.count else { return false }
        return milestones[index + 1].state == .next
    }

    private func milestoneRow(_ milestone: EvidenceMilestone, index: Int) -> some View {
        let expanded = expandedWeek == milestone.week
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    expandedWeek = expanded ? nil : milestone.week
                }
            } label: {
                HStack(alignment: .top, spacing: 13) {
                    node(milestone.state, index: index)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(milestone.title)
                            .font(Clinical.body(14, weight: milestone.state == .ahead ? .regular : .medium))
                            .foregroundStyle(milestone.state == .ahead ? Clinical.secondary : Clinical.ink)
                        Text(subtitle(milestone))
                            .font(Clinical.caption(11.5))
                            .foregroundStyle(milestone.state == .next ? Clinical.accent : Clinical.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(Clinical.body(10, weight: .semibold))
                        .foregroundStyle(Clinical.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("\(milestone.title), \(stateWord(milestone.state))")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows what this checkpoint reviews")
            .accessibilityIdentifier("evidenceMilestone.\(milestone.week)")

            if expanded {
                detail(milestone)
                    .padding(.leading, 31)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Why: \(milestone.why) Reviews: \(milestone.evidence) "
                        + "Photo: \(milestone.needsPhoto ? "A comparable photo is needed." : "No photo is needed.") "
                        + "Reads: \(milestone.interpretable ? "Enough to interpret with the usual caveats." : "Too early to interpret.") "
                        + "Next: \(milestone.nextAction)"
                    )
                    .accessibilityIdentifier("evidenceMilestoneDetail.\(milestone.week)")
            }
        }
        .background(alignment: .topLeading) {
            if index < milestones.count - 1 {
                GeometryReader { proxy in
                    EvidenceConnector(bend: index.isMultiple(of: 2) ? 4 : -4)
                        .trim(from: 0, to: railProgress)
                        .stroke(
                            connectorColor(after: milestone, index: index),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                        )
                        .frame(width: 18, height: proxy.size.height + 18)
                        .offset(y: 18)
                        .animation(
                            .easeInOut(duration: MotionSpec.evidencePath.segment)
                                .delay(Double(index) * MotionSpec.evidencePath.segmentStep),
                            value: revealsRail
                        )
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func currentRow(index: Int) -> some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack {
                Circle()
                    .strokeBorder(Clinical.accent.opacity(0.45), lineWidth: 1)
                    .frame(width: 24, height: 24)
                Circle()
                    .strokeBorder(Clinical.accent, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                Circle().fill(Clinical.accent).frame(width: 6, height: 6)
            }
            .frame(width: 18)
            .scaleEffect(isStatic || settlesCurrent ? 1 : 0.72)
            .opacity(isStatic || settlesCurrent ? 1 : 0)
            .animation(
                .spring(
                    response: MotionSpec.evidencePath.currentSpring.response,
                    dampingFraction: MotionSpec.evidencePath.currentSpring.damping
                ).delay(Double(index) * MotionSpec.evidencePath.nodeStep),
                value: settlesCurrent
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("You are here")
                    .font(Clinical.body(13, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                Text(reviewLine)
                    .font(Clinical.caption(11.5))
                    .foregroundStyle(Clinical.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You are here. \(reviewLine)")
    }

    private var reviewLine: String {
        switch phase.daysToReview {
        case 0: return "Review due today"
        case 1: return "1 day to the next review"
        default: return "\(phase.daysToReview) days to the next review"
        }
    }

    private var railProgress: CGFloat {
        isStatic || revealsRail ? 1 : 0
    }

    private func node(_ state: EvidenceMilestone.State, index: Int) -> some View {
        ZStack {
            switch state {
            case .reached:
                Circle().fill(Clinical.sage)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Clinical.surface)
            case .next:
                Circle().strokeBorder(Clinical.accent.opacity(0.7), lineWidth: 1.5)
                Circle().fill(Clinical.accent.opacity(0.15)).frame(width: 8, height: 8)
            case .ahead:
                Circle().strokeBorder(Clinical.hairline, lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
        .padding(.top, 1)
        .scaleEffect(isStatic || revealsNodes ? 1 : 0.72)
        .opacity(isStatic || revealsNodes ? 1 : 0)
        .animation(
            .spring(response: 0.36, dampingFraction: 0.82)
                .delay(Double(index) * MotionSpec.evidencePath.nodeStep),
            value: revealsNodes
        )
    }

    private func connectorColor(after milestone: EvidenceMilestone, index: Int) -> Color {
        guard index + 1 < milestones.count else { return Clinical.hairline }
        if milestone.state == .reached && milestones[index + 1].state == .reached {
            return Clinical.sage.opacity(0.65)
        }
        if milestone.state == .reached {
            return Clinical.accent.opacity(0.35)
        }
        return Clinical.hairline
    }

    private func subtitle(_ milestone: EvidenceMilestone) -> String {
        switch milestone.state {
        case .reached:
            return milestone.week == 0 ? "Starting point recorded" : "Checkpoint reached"
        case .next:
            return milestone.needsPhoto ? "Next · comparable photo at this checkpoint" : "Next checkpoint"
        case .ahead:
            return milestone.needsPhoto ? "Ahead · comparable photo at this checkpoint" : "Ahead"
        }
    }

    private func stateWord(_ state: EvidenceMilestone.State) -> String {
        switch state {
        case .reached: return "reached"
        case .next: return "next"
        case .ahead: return "ahead"
        }
    }

    private func detail(_ milestone: EvidenceMilestone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailLine("Why", symbol: "signpost.right", milestone.why)
            detailLine("Reviews", symbol: "doc.text.magnifyingglass", milestone.evidence)
            detailLine(
                "Photo",
                symbol: "camera",
                milestone.needsPhoto
                    ? "A photo taken under comparable conditions belongs at this checkpoint."
                    : "No comparison photo is needed at this checkpoint."
            )
            detailLine(
                "Can read",
                symbol: milestone.interpretable ? "checkmark.circle" : "hourglass",
                milestone.interpretable
                    ? "Ready for a careful comparison, with the usual limits."
                    : "Still building evidence; this checkpoint is not an outcome verdict."
            )
            detailLine("Next", symbol: "arrow.right", milestone.nextAction)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(Clinical.sage.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailLine(_ label: String, symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(Clinical.caption(10.5))
                .foregroundStyle(Clinical.sage)
                .frame(width: 14, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(Clinical.eyebrow(9)).tracking(0.8)
                    .foregroundStyle(Clinical.tertiary)
                Text(text)
                    .font(Clinical.caption(12.5))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Consistency strands

    private var strandsBlock: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(overallHeadline)
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text(overallCount)
                    .font(Clinical.caption(11.5))
                    .foregroundStyle(Clinical.tertiary)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            ForEach(strands) { strand in
                strandRow(strand)
            }
            Colophon(
                text: "Consistency makes the next review easier to interpret. It does not prove effectiveness."
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planStrands")
    }

    private var overallHeadline: String {
        guard let overall, overall.scored > 0 else { return "30-day consistency" }
        return "\(overall.percent)% consistency"
    }

    private var overallCount: String {
        guard let overall else { return "No planned actions yet" }
        guard overall.scored > 0 else { return "Not enough due actions yet" }
        return "\(overall.completed) of \(overall.scored) due · \(overall.planned) planned"
    }

    @ViewBuilder
    private func strandRow(_ strand: PlanStrand) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(strand.name)
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.ink)
                Spacer(minLength: 8)
                Text(strandTrailing(strand))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Clinical.secondary)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            if strand.isScheduled && !strand.isUnscored, let thirtyDay = strand.thirtyDay {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Clinical.hairline)
                        Capsule()
                            .fill(Clinical.sage)
                            .frame(width: max(2, proxy.size.width * thirtyDay.fraction))
                    }
                }
                .frame(height: 3)
                Text(strandCount(strand))
                    .font(Clinical.caption(10.5))
                    .foregroundStyle(Clinical.tertiary)
                    .monospacedDigit()
            } else if strand.isUnscored {
                Capsule()
                    .stroke(Clinical.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strandAccessibility(strand))
    }

    private func strandTrailing(_ strand: PlanStrand) -> String {
        guard strand.isScheduled else { return "Recorded per use" }
        guard !strand.isUnscored else { return "Not enough due actions yet" }
        return strand.thirtyDay.map { "\($0.percent)% · 30 days" } ?? "Starting"
    }

    private func strandCount(_ strand: PlanStrand) -> String {
        guard let thirtyDay = strand.thirtyDay else { return "" }
        let sevenDay = strand.sevenDay.map { value in
            value.scored > 0
                ? " · This week \(value.completed) of \(value.scored) due · \(value.planned) planned"
                : " · This week not enough due actions yet"
        } ?? ""
        return "\(thirtyDay.completed) of \(thirtyDay.scored) due · \(thirtyDay.planned) planned\(sevenDay)"
    }

    private func strandAccessibility(_ strand: PlanStrand) -> String {
        guard strand.isScheduled else {
            return "\(strand.name), recorded per use, no schedule to measure"
        }
        guard !strand.isUnscored else {
            return "\(strand.name), not enough due actions yet"
        }
        guard let thirtyDay = strand.thirtyDay else {
            return "\(strand.name), starting"
        }
        return "\(strand.name), \(thirtyDay.percent) percent of due actions over thirty days, "
            + "\(thirtyDay.completed) completed of \(thirtyDay.scored) due, "
            + "\(thirtyDay.planned) planned through today"
    }

    // MARK: - Entrance

    private func enterIfNeeded(reset: Bool = false) {
        entranceTask?.cancel()
        if reset {
            revealsRail = false
            revealsNodes = false
            settlesCurrent = false
        }
        guard !isStatic, enteredKey != entranceKey else {
            revealsRail = true
            revealsNodes = true
            settlesCurrent = true
            enteredKey = entranceKey
            return
        }

        revealsRail = true
        revealsNodes = true
        settlesCurrent = true
        let key = entranceKey
        entranceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(MotionSpec.evidencePath.total))
            guard !Task.isCancelled, entranceKey == key else { return }
            enteredKey = key
        }
    }
}

private struct EvidenceConnector: Shape {
    let bend: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        path.move(to: CGPoint(x: x, y: 0))
        path.addCurve(
            to: CGPoint(x: x, y: rect.maxY),
            control1: CGPoint(x: x + bend, y: rect.height * 0.34),
            control2: CGPoint(x: x - bend, y: rect.height * 0.68)
        )
        return path
    }
}
