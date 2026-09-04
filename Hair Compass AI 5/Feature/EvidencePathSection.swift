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
    let signals: [EvidenceSignal]
    let strands: [PlanStrand]
    let overall: PlanAdherence.Consistency?
    let onAction: (EvidenceSignal.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("evidencePath.enteredKey") private var enteredKey = ""
    @State private var expandedWeek: Int?
    @State private var revealsRail = false
    @State private var revealsNodes = false
    @State private var settlesCurrent = false
    @State private var entranceTask: Task<Void, Never>?
    @State private var selectedSignal: EvidenceSignal.Kind = .treatment
    @State private var strandsExpanded = false
    @Namespace private var signalSelection

    private var isStatic: Bool { reduceMotion || MotionQA.isStatic }
    private var entranceKey: String {
        "\(Int(phase.start.timeIntervalSince1970))|\(phase.week)|\(phase.nextReviewWeek)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            path
            signalsBlock
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

    // MARK: - Evidence lenses

    /// Six compact selectors replace a permanently-expanded stack of generic trackers. One lens
    /// stays open at a time, making the special rule and next action visible without turning Plan
    /// back into an endless page.
    private var signalsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Six signals · six rules")
                    .font(Clinical.body(15, weight: .semibold))
                    .foregroundStyle(Clinical.ink)
                Text("Choose a lens to see what makes that evidence readable.")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
            }

            if let suggestedSignal {
                suggestedStep(suggestedSignal)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(signals) { signal in
                    signalButton(signal)
                }
            }

            if let signal = signals.first(where: { $0.kind == selectedSignal }) ?? signals.first {
                signalDetail(signal)
                    .id(signal.kind)
                    .transition(.opacity.combined(with: .offset(y: 5)))

                if signal.kind == .treatment {
                    strandsDisclosure
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: selectedSignal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evidenceSignals")
    }

    /// Only one item earns this extra prominence. Safety/review signals come first, followed by
    /// unfinished core tracking. Optional empty labs and life events do not become synthetic
    /// chores simply because the fields exist.
    private var suggestedSignal: EvidenceSignal? {
        if let review = signals.first(where: { $0.state == .discuss }) { return review }
        let core: [EvidenceSignal.Kind] = [.treatment, .shedding, .scalp, .photos]
        return signals.first { core.contains($0.kind) && $0.state != .readable }
    }

    private func suggestedStep(_ signal: EvidenceSignal) -> some View {
        let tint = stateColor(signal.state)
        let isReview = signal.state == .discuss
        return Button { select(signal.kind) } label: {
            suggestedStepLabel(signal, tint: tint, isReview: isReview)
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel("Suggested: \(signal.kind.title), \(signal.status)")
        .accessibilityHint("Selects this evidence lens")
        .accessibilityIdentifier("evidenceSuggested.\(signal.kind.rawValue)")
    }

    private func suggestedStepLabel(
        _ signal: EvidenceSignal,
        tint: Color,
        isReview: Bool
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: isReview ? "heart.text.clipboard" : "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isReview ? "WORTH A LOOK" : "BEST NEXT STEP")
                    .font(Clinical.eyebrow(8.5))
                    .tracking(0.7)
                    .foregroundStyle(Clinical.tertiary)
                Text("\(signal.kind.title) · \(signal.status)")
                    .font(Clinical.caption(12.5))
                    .foregroundStyle(Clinical.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Clinical.tertiary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func signalButton(_ signal: EvidenceSignal) -> some View {
        let selected = signal.kind == selectedSignal
        let border = selected ? Clinical.accent.opacity(0.42) : Clinical.hairline
        return Button(action: { select(signal.kind) }) {
            signalButtonLabel(signal, selected: selected)
                .background { signalButtonBackground(selected: selected) }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel("\(signal.kind.title), \(signal.status)")
        .accessibilityValue(selected ? "Selected" : stateLabel(signal))
        .accessibilityHint("Shows the special logic for \(signal.kind.title.lowercased()) evidence")
        .accessibilityIdentifier("evidenceLens.\(signal.kind.rawValue)")
    }

    private func select(_ kind: EvidenceSignal.Kind) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            if kind != .treatment { strandsExpanded = false }
            selectedSignal = kind
        }
    }

    private func signalButtonLabel(_ signal: EvidenceSignal, selected: Bool) -> some View {
        let tint = selected ? Clinical.accent : stateColor(signal.state)
        let weight: Font.Weight = selected ? .semibold : .medium
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: signal.kind.symbol)
                    .font(Clinical.body(13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 4)
                Circle()
                    .fill(stateColor(signal.state))
                    .frame(width: 6, height: 6)
            }
            Text(signal.kind.title)
                .font(Clinical.caption(11.5))
                .fontWeight(weight)
                .foregroundStyle(Clinical.ink)
                .lineLimit(1)
            Text(stateLabel(signal))
                .font(Clinical.eyebrow(8.5))
                .tracking(0.55)
                .foregroundStyle(stateColor(signal.state))
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func signalButtonBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Clinical.surface.opacity(0.72))
        if selected {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Clinical.accent.opacity(0.085))
                .matchedGeometryEffect(id: "evidenceSignalSelection", in: signalSelection)
        }
    }

    private func signalDetail(_ signal: EvidenceSignal) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(stateColor(signal.state))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(signal.status)
                    .font(Clinical.body(14, weight: .semibold))
                    .foregroundStyle(Clinical.ink)
                Spacer(minLength: 8)
                Text(stateLabel(signal).uppercased())
                    .font(Clinical.eyebrow(9))
                    .tracking(0.7)
                    .foregroundStyle(stateColor(signal.state))
            }

            Text(signal.summary)
                .font(Clinical.caption(12.5))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Clinical.hairline).frame(height: 1)

            signalDetailLine("READS BY", symbol: "slider.horizontal.3", signal.rule)
            signalDetailLine("NEXT", symbol: "arrow.right", signal.nextAction)

            Button { onAction(signal.action) } label: {
                HStack(spacing: 8) {
                    Image(systemName: signal.action.symbol)
                    Text(signal.action.title)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.7)
                }
                .font(Clinical.body(12.5, weight: .semibold))
                .foregroundStyle(Clinical.surface)
                .padding(.horizontal, 13)
                .frame(minHeight: 42)
                .background(Clinical.accent, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.clinicalPressable)
            .accessibilityHint("Opens the place to do this")
            .accessibilityIdentifier("evidenceAction.\(signal.kind.rawValue)")
        }
        .padding(13)
        .background(Clinical.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evidenceLensDetail.\(signal.kind.rawValue)")
    }

    private func signalDetailLine(_ label: String, symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(Clinical.caption(10.5))
                .foregroundStyle(Clinical.sage)
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Clinical.eyebrow(8.5))
                    .tracking(0.7)
                    .foregroundStyle(Clinical.tertiary)
                Text(text)
                    .font(Clinical.caption(11.5))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stateLabel(_ signal: EvidenceSignal) -> String {
        switch signal.state {
        case .standby:
            switch signal.kind {
            case .photos: return "Baseline"
            case .labs, .events: return "Optional"
            case .treatment: return "Setup"
            case .shedding, .scalp: return "Start"
            }
        case .building: return "Building"
        case .readable: return "Readable"
        case .discuss: return "Discuss"
        }
    }

    private func stateColor(_ state: EvidenceSignal.State) -> Color {
        switch state {
        case .standby: return Clinical.tertiary
        case .building: return Clinical.accent
        case .readable: return Clinical.sage
        case .discuss: return Clinical.warning
        }
    }

    private var strandsDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    strandsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(Clinical.caption(11))
                        .foregroundStyle(Clinical.sage)
                    Text("Treatment by treatment")
                        .font(Clinical.caption(12.5))
                        .foregroundStyle(Clinical.ink)
                    Spacer(minLength: 8)
                    Text(strands.isEmpty ? "None" : "\(strands.count)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Clinical.tertiary)
                    Image(systemName: "chevron.down")
                        .font(Clinical.caption(9))
                        .foregroundStyle(Clinical.tertiary)
                        .rotationEffect(.degrees(strandsExpanded ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Clinical.sage.opacity(0.055), in: Capsule())
                .overlay { Capsule().strokeBorder(Clinical.hairline, lineWidth: 1) }
                .contentShape(Capsule())
            }
            .buttonStyle(.clinicalPressable)
            .accessibilityValue(strandsExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the separate consistency record for each treatment")
            .accessibilityIdentifier("planStrandsToggle")

            if strandsExpanded {
                strandsBlock
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
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
