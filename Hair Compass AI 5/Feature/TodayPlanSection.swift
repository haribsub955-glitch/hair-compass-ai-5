//
//  TodayPlanSection.swift
//  Hair Compass AI 5
//
//  Today's plan: one row per scheduled occurrence with a single obvious completion target, Undo
//  for five seconds after a check-off (and always in the long-press menu), Skip and Pause behind
//  the same menu so they never compete with completing, a seven-day continuity strip, and a calm
//  closure line once every occurrence is settled. The section renders and hands every write to
//  its owner; it never touches a ModelContext.
//

import SwiftUI
import UIKit

/// The section's copy, kept as data so tests can pin the framing rule.
enum TodayPlanCopy {
    static let eyebrow = "Today's plan"
    static let closureTitle = "Your plan is complete for today"
    static let closureBody = "You showed up. Nothing else needs to be checked today."
    static let settledTitle = "Today's plan is recorded"
    static let settledBody = "Every action today was skipped with a reason. Tomorrow is a clean place to restart."
    static let quietTitle = "Nothing is scheduled today"
    static let quietBody = "Your plan will list the next action when one is due."
    static let viewPlan = "View plan"
    static let skippedLabel = "Skipped"
    static let undo = "Undo"
    static func recordedLine(_ count: Int) -> String {
        count == 1 ? "1 action recorded" : "\(count) actions recorded"
    }
    static let weekEyebrow = "This week"
    static func weekLine(completed: Int, planned: Int) -> String {
        "\(completed) of \(planned) planned actions"
    }
    static let weekEmpty = "No planned actions yet this week"
    static let skipTitle = "Skip this one today?"
    static let skipMessage = "This records a skipped application. It does not change or start any treatment."
    static func pauseTitle(_ name: String) -> String { "Pause \(name)?" }
    static let pauseMessage = "It leaves today's plan until you resume it from the Plan tab. This records your decision; it does not advise one."
    static let pauseAction = "Pause"
}

struct TodayPlanSection: View {
    let plan: PlanAdherence.TodayPlan
    let week: [PlanAdherence.DayState]
    let weekSummary: PlanAdherence.Consistency?
    /// One Undo path (Important 9): set by the owner when the grounding card's own chip completed
    /// this occurrence (the write already happened there) — this section only shows the same
    /// Undo affordance a row tap would, on `.onChange`, without writing again.
    var externalCompletionID: String? = nil
    /// The owner's Close the Day gate (G2-R14: once per day) — replaces the section's own
    /// `plan.isComplete && plan.completedCount > 0` so the constellation never replays on a
    /// view recreation the same day it already celebrated.
    var celebrate: Bool = false
    var onComplete: (PlanAdherence.Occurrence) -> Void
    var onUndo: (PlanAdherence.Occurrence) -> Void
    var onSkip: (PlanAdherence.Occurrence) -> Void
    var onPause: (PlanAdherence.Occurrence) -> Void
    var onOpenDetail: (PlanAdherence.Occurrence) -> Void
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    /// True while the person has asked to see the recorded rows under the closure line.
    @State private var showsRecorded = false
    /// The occurrence whose inline Undo is still showing.
    @State private var undoableID: String?
    @State private var undoTimer: Task<Void, Never>?
    /// SwiftData can publish an insertion before it publishes the matching deletion. Keep Undo
    /// visibly immediate and deterministic while that query catches up; the occurrence's stable
    /// natural id lets this projection disappear as soon as the source reports the row open.
    @State private var optimisticallyOpenIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TodayPlanCopy.eyebrow)
                .font(Clinical.headline(24)).foregroundStyle(Clinical.ink)
                .padding(.bottom, 14)
            if plan.nothingExpected {
                quietLine
            } else if plan.isComplete && !showsRecorded && undoableID == nil && optimisticallyOpenIDs.isEmpty {
                // Holds back until the last row's five-second Undo has passed — tapping Undo on
                // the final row must land back on the rows, not on a closure line that already
                // claimed the day done.
                if plan.completedCount == 0 {
                    settled
                } else {
                    closure
                }
            } else {
                rows
                    .transition(.opacity)
            }
            ContinuityStrip(days: week, summary: weekSummary, celebrate: celebrate)
                .padding(.top, 14)
        }
        .padding(18)
        .background(alignment: .topTrailing) { BotanicalCardSprig(width: 94, opacity: 0.18) }
        .background(Clinical.surfaceWash, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Clinical.accent.opacity(0.20)))
        .shadow(color: Clinical.cardShadow, radius: 10, y: 4)
        .onChange(of: plan.isComplete) { _, complete in
            guard complete else { return }
            showsRecorded = false
            // A day where every action was skipped is recorded, not celebrated — no success
            // haptic without at least one real completion.
            guard plan.completedCount > 0 else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .onChange(of: externalCompletionID) { _, id in
            // One Undo path (Important 9): the owner already wrote the dose — this only shows
            // the same Undo affordance and starts the same 5 s window a row tap would.
            guard let id else { return }
            startUndoWindow(for: id)
        }
        .onChange(of: plan.occurrences.map { "\($0.id)|\($0.state.rawValue)" }) { _, _ in
            optimisticallyOpenIDs = optimisticallyOpenIDs.filter { id in
                plan.occurrences.first(where: { $0.id == id })?.isSettled == true
            }
        }
        .onDisappear { undoTimer?.cancel(); undoTimer = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayPlan")
    }

    // MARK: Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.occurrences.enumerated()), id: \.element.id) { index, occurrence in
                let displayedOccurrence = displayOccurrence(occurrence)
                PlanActionRow(
                    occurrence: displayedOccurrence,
                    index: index,
                    showsUndo: undoableID == occurrence.id,
                    settlesPlan: occurrence.isOpen && plan.openCount == 1,
                    onComplete: { complete(occurrence) },
                    onUndo: { undo(occurrence) },
                    onSkip: { onSkip(occurrence) },
                    onPause: { onPause(occurrence) },
                    onOpenDetail: { onOpenDetail(occurrence) }
                )
                if index < plan.occurrences.count - 1 {
                    Divider().overlay(Clinical.hairline)
                }
            }
            viewPlanButton
                .padding(.top, 10)
        }
    }

    private func complete(_ occurrence: PlanAdherence.Occurrence) {
        optimisticallyOpenIDs.remove(occurrence.id)
        onComplete(occurrence)
        startUndoWindow(for: occurrence.id)
    }

    /// The bookkeeping a completion shows: the inline Undo affordance, live for five seconds.
    /// Shared by a row tap (`complete(_:)`) and the grounding card's external completion — same
    /// window, same behavior, only one of the two ever also performs the write.
    private func startUndoWindow(for id: String) {
        undoableID = id
        undoTimer?.cancel()
        undoTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation((reduceMotion || MotionQA.isStatic) ? nil : .easeOut(duration: 0.2)) { undoableID = nil }
        }
    }

    private func undo(_ occurrence: PlanAdherence.Occurrence) {
        undoTimer?.cancel()
        undoableID = nil
        optimisticallyOpenIDs.insert(occurrence.id)
        onUndo(occurrence)
    }

    /// Returns the row state the person should see while an Undo deletion propagates through the
    /// SwiftData query. It retains the scheduled time and chooses due/upcoming from the same
    /// clock rule as the adherence engine; no count is fabricated or persisted here.
    private func displayOccurrence(_ occurrence: PlanAdherence.Occurrence) -> PlanAdherence.Occurrence {
        guard optimisticallyOpenIDs.contains(occurrence.id) else { return occurrence }
        let state: PlanAdherence.OccurrenceState = PlanAdherence.isReached(
            slot: occurrence.slot, now: .now, calendar: calendar
        ) ? .due : .upcoming
        return PlanAdherence.Occurrence(
            treatment: occurrence.treatment,
            day: occurrence.day,
            slot: occurrence.slot,
            state: state,
            completedAt: nil
        )
    }

    // MARK: Closure and quiet day

    private var closure: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Clinical.body(16))
                    .foregroundStyle(Clinical.sage)
                    .accessibilityHidden(true)
                Text(TodayPlanCopy.closureTitle)
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
            }
            Text(TodayPlanCopy.closureBody)
                .font(Clinical.caption(12.5))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation((reduceMotion || MotionQA.isStatic) ? nil : .easeOut(duration: 0.2)) { showsRecorded = true }
            } label: {
                Text("\(TodayPlanCopy.recordedLine(plan.settledCount)) · Show")
                    .font(Clinical.body(12, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityIdentifier("planClosureShow")
            viewPlanButton
        }
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .offset(y: 6)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planClosure")
    }

    /// An all-skipped day: every action was recorded, none completed. Distinct from `closure` —
    /// a neutral outline instead of the sage check, and no claim that the person "showed up".
    private var settled: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(Clinical.tertiary, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                Text(TodayPlanCopy.settledTitle)
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
            }
            Text(TodayPlanCopy.settledBody)
                .font(Clinical.caption(12.5))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation((reduceMotion || MotionQA.isStatic) ? nil : .easeOut(duration: 0.2)) { showsRecorded = true }
            } label: {
                Text("\(TodayPlanCopy.recordedLine(plan.settledCount)) · Show")
                    .font(Clinical.body(12, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityIdentifier("planClosureShow")
            viewPlanButton
        }
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .offset(y: 6)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planSettled")
    }

    private var quietLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TodayPlanCopy.quietTitle)
                .font(Clinical.body(15, weight: .medium))
                .foregroundStyle(Clinical.ink)
            Text(TodayPlanCopy.quietBody)
                .font(Clinical.caption(12.5))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            viewPlanButton
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planQuiet")
    }

    /// The one quiet way to reach the Plan tab from every day's state — under the closure/settled
    /// blocks and under the rows. Empty when `onOpenPlan` is nil (e.g. a preview with no owner).
    @ViewBuilder
    private var viewPlanButton: some View {
        if let onOpenPlan {
            Button(TodayPlanCopy.viewPlan, action: onOpenPlan)
                .font(Clinical.body(12, weight: .medium))
                .foregroundStyle(Clinical.accent)
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityIdentifier("planViewPlan")
        }
    }
}

// MARK: - Row

private struct PlanActionRow: View {
    let occurrence: PlanAdherence.Occurrence
    let index: Int
    let showsUndo: Bool
    /// True for the one row still open when it is the plan's last — the section's own `.success`
    /// notification (fired from `.onChange(of: plan.isComplete)`) is the single haptic that tap
    /// gets, so this row skips its own `.soft` impact.
    let settlesPlan: Bool
    let onComplete: () -> Void
    let onUndo: () -> Void
    let onSkip: () -> Void
    let onPause: () -> Void
    let onOpenDetail: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @State private var wash = false
    @State private var inkTrigger = false
    /// The check morph (M3): the circle scales 0.85 → 1.1 → 1 on completion while the checkmark
    /// fades in — the underdamped spring itself produces the overshoot, no phase sequencing
    /// needed. Both start at their settled values so an already-completed row (a fresh render,
    /// not a live completion) never morphs.
    @State private var checkScale: CGFloat = 1
    @State private var checkOpacity: Double = 1

    private var name: String {
        occurrence.treatment.name.isEmpty ? occurrence.treatment.treatmentClass.title : occurrence.treatment.name
    }

    private var classSubtitle: String? {
        let cls = occurrence.treatment.treatmentClass.title
        return name.localizedCaseInsensitiveContains(cls) ? nil : cls
    }

    private var slotTime: String? {
        PlanAdherence.slotDate(occurrence.slot, on: occurrence.day, calendar: calendar)
            .map { $0.formatted(date: .omitted, time: .shortened) }
    }

    private var timeLabel: String {
        switch occurrence.state {
        case .completed:
            return occurrence.completedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        case .skipped:
            return TodayPlanCopy.skippedLabel
        case .due:
            return slotTime.map { "Due \($0)" } ?? "Today"
        case .upcoming:
            return slotTime ?? "Today"
        case .missed, .notExpected:
            return ""
        }
    }

    private var circleValue: String {
        switch occurrence.state {
        case .completed: return "Completed at \(timeLabel)"
        case .skipped: return TodayPlanCopy.skippedLabel
        default: return "Not yet"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            circle
            Button(action: onOpenDetail) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Clinical.body(14, weight: occurrence.isSettled ? .regular : .medium))
                        .foregroundStyle(occurrence.isSettled ? Clinical.secondary : Clinical.ink)
                        .completionInkUnderline(trigger: $inkTrigger)
                    if let classSubtitle {
                        Text(classSubtitle)
                            .font(Clinical.caption(11.5))
                            .foregroundStyle(Clinical.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(timeLabel)")
            .accessibilityHint("Opens this treatment")
            .accessibilityIdentifier("planRowDetail.\(index)")
            if occurrence.state == .completed && showsUndo {
                Button(TodayPlanCopy.undo, action: onUndo)
                    .font(Clinical.body(12, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .accessibilityIdentifier("planRowUndo.\(index)")
            } else {
                Text(timeLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Clinical.secondary)
            }
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Clinical.sage.opacity(wash ? 0.14 : 0))
                .padding(.horizontal, -8)
        }
        .contextMenu {
            if occurrence.isSettled {
                Button(TodayPlanCopy.undo, systemImage: "arrow.uturn.backward", action: onUndo)
            }
            if occurrence.isOpen {
                Button("Skip today", systemImage: "forward.end", action: onSkip)
            }
            Button("Pause treatment", systemImage: "pause.circle", action: onPause)
            Button("Details", systemImage: "info.circle", action: onOpenDetail)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planRow.\(index)")
    }

    private var fill: Color {
        switch occurrence.state {
        case .completed: return Clinical.sage
        case .due: return Clinical.accent.opacity(0.06)
        default: return .clear
        }
    }

    private var stroke: Color {
        switch occurrence.state {
        case .completed: return Clinical.sage
        case .due: return Clinical.accent.opacity(0.5)
        case .skipped: return Clinical.tertiary.opacity(0.5)
        default: return Clinical.hairline
        }
    }

    private var circle: some View {
        Button {
            guard occurrence.isOpen else { return }
            complete()
        } label: {
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(stroke, lineWidth: 1.5)
                if occurrence.state == .completed {
                    Image(systemName: "checkmark")
                        .font(Clinical.body(10, weight: .bold))
                        .foregroundStyle(Clinical.surface)
                        .opacity(checkOpacity)
                }
                if occurrence.state == .skipped {
                    Capsule().fill(Clinical.tertiary).frame(width: 8, height: 1.5)
                }
            }
            .frame(width: 22, height: 22)
            .scaleEffect(checkScale)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel(occurrence.isOpen ? "Mark \(name) complete" : name)
        .accessibilityValue(circleValue)
        .accessibilityHint(occurrence.isOpen ? "Records this action as done" : "Use Undo to change it")
        .accessibilityIdentifier("planRowComplete.\(index)")
    }

    private func complete() {
        if !settlesPlan {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        onComplete()
        inkTrigger = true
        guard !(reduceMotion || MotionQA.isStatic) else { return }
        withAnimation(.easeOut(duration: 0.18)) { wash = true }
        Task {
            try? await Task.sleep(for: .seconds(MotionSpec.completion.washDuration))
            withAnimation(.easeIn(duration: 0.4)) { wash = false }
        }
        // Check morph: an underdamped spring from 0.85 overshoots past 1 on its own — the
        // "0.85 → 1.1 → 1" pop — while the checkmark fades in on its own short curve.
        checkScale = 0.85
        checkOpacity = 0
        withAnimation(.spring(response: MotionSpec.completion.popSpring.response,
                              dampingFraction: MotionSpec.completion.popSpring.damping)) {
            checkScale = 1
        }
        withAnimation(.easeOut(duration: 0.2)) {
            checkOpacity = 1
        }
    }
}

// MARK: - Continuity strip

/// Seven small day capsules for the current week: a sage check for a day whose planned actions
/// were all recorded, a copper dot for a partial day, a neutral dash when nothing was expected,
/// an outline for today and the days ahead, and a muted dot for a missed day — never red.
struct ContinuityStrip: View {
    let days: [PlanAdherence.DayState]
    let summary: PlanAdherence.Consistency?
    /// The owner passes its Close the Day gate (G2-R14: `plan.isComplete && plan.completedCount
    /// > 0 && celebratedDay != dayKey`) — rising edge only, and only for a day with at least one
    /// real completion (an all-skipped day never celebrates) that has not already celebrated.
    var celebrate: Bool = false

    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Guards the one-shot constellation (M4) so a reappearance of an already-celebrated strip
    /// never replays it.
    @State private var celebrated = false
    /// Flips once to drive every `.complete` capsule's own delayed pop — each capsule reads this
    /// single trigger through its own `.animation(_:value:)`, so the per-index delay lives on the
    /// view, not on a sequence of separate state writes.
    @State private var pops = false
    @State private var connectorProgress: CGFloat = 0
    @State private var connectorTask: Task<Void, Never>?

    private var isStatic: Bool { reduceMotion || MotionQA.isStatic }

    private var summaryLine: String {
        summary.map { TodayPlanCopy.weekLine(completed: $0.completed, planned: $0.planned) }
            ?? TodayPlanCopy.weekEmpty
    }

    /// Adjacent day-index pairs where both days are `.complete` — the segments the sage
    /// connector draws between.
    private var connectorSegments: [(Int, Int)] {
        guard days.count > 1 else { return [] }
        return (0..<(days.count - 1)).compactMap { i in
            days[i].mark == .complete && days[i + 1].mark == .complete ? (i, i + 1) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: TodayPlanCopy.weekEyebrow, color: Clinical.tertiary)
                Spacer(minLength: 8)
                Text(summaryLine)
                    .font(Clinical.caption(11.5))
                    .foregroundStyle(Clinical.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    VStack(spacing: 5) {
                        Text(initial(day.day))
                            .font(Clinical.caption(10))
                            .foregroundStyle(Clinical.tertiary)
                        DayCapsule(mark: day.mark)
                            .scaleEffect(capsuleScale(day: day))
                            .animation(capsuleAnimation(index: index, day: day), value: pops)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(day))
                }
            }
            .background(alignment: .bottom) {
                GeometryReader { geo in
                    connectorPath(in: geo.size)
                        .trim(from: 0, to: connectorProgress)
                        .stroke(Clinical.sage.opacity(0.4), lineWidth: 1)
                }
                .frame(height: 18)
                .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("continuityStrip")
        .onAppear { triggerCelebrationIfNeeded() }
        .onChange(of: celebrate) { _, _ in triggerCelebrationIfNeeded() }
        .onDisappear { connectorTask?.cancel(); connectorTask = nil }
    }

    private func initial(_ day: Date) -> String {
        String(day.formatted(.dateTime.weekday(.abbreviated)).prefix(1)).uppercased()
    }

    private func label(_ day: PlanAdherence.DayState) -> String {
        let name = day.day.formatted(.dateTime.weekday(.wide))
        switch day.mark {
        case .complete: return "\(name), all planned actions recorded"
        case .partial: return "\(name), \(day.completed) of \(day.expected) recorded"
        case .missed: return "\(name), planned actions not recorded"
        case .notExpected: return "\(name), nothing planned"
        case .today: return "\(name), today, \(day.completed) of \(day.expected) so far"
        case .upcoming: return "\(name), ahead"
        }
    }

    // MARK: Constellation (M4)

    /// Missed/partial/etc. days keep their marks and are never animated — only `.complete`
    /// capsules pop, and only while a celebration is in flight or has already played. Reduce
    /// Motion / static always reads 1 regardless of `pops` — otherwise the very first frame
    /// (rendered before `onAppear` has a chance to set `pops = true`) would flash the 0.7 shrink
    /// for one frame even though nothing is meant to animate.
    private func capsuleScale(day: PlanAdherence.DayState) -> CGFloat {
        guard day.mark == .complete, celebrate, !isStatic else { return 1 }
        return pops ? 1 : 0.7
    }

    private func capsuleAnimation(index: Int, day: PlanAdherence.DayState) -> Animation? {
        guard day.mark == .complete, celebrate, !isStatic else { return nil }
        return .spring(response: 0.28, dampingFraction: 0.6)
            .delay(Double(index) * MotionSpec.closeTheDay.capsuleStep)
    }

    private func connectorPath(in size: CGSize) -> Path {
        Path { path in
            guard !days.isEmpty else { return }
            let colWidth = size.width / CGFloat(days.count)
            let y = size.height / 2
            for (a, b) in connectorSegments {
                let xa = colWidth * (CGFloat(a) + 0.5)
                let xb = colWidth * (CGFloat(b) + 0.5)
                path.move(to: CGPoint(x: xa, y: y))
                path.addLine(to: CGPoint(x: xb, y: y))
            }
        }
    }

    private func triggerCelebrationIfNeeded() {
        guard celebrate, !celebrated else { return }
        celebrated = true
        guard !isStatic else {
            pops = true
            connectorProgress = 1
            return
        }
        pops = true
        connectorTask?.cancel()
        connectorTask = Task {
            try? await Task.sleep(for: .seconds(MotionSpec.closeTheDay.capsuleStep))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: MotionSpec.closeTheDay.connector)) {
                connectorProgress = 1
            }
        }
    }
}

private struct DayCapsule: View {
    let mark: PlanAdherence.DayMark

    var body: some View {
        ZStack {
            switch mark {
            case .complete:
                Circle().fill(Clinical.sage)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Clinical.surface)
            case .partial:
                Circle().strokeBorder(Clinical.accent.opacity(0.5), lineWidth: 1)
                Circle().fill(Clinical.accent).frame(width: 6, height: 6)
            case .missed:
                Circle().strokeBorder(Clinical.hairline, lineWidth: 1)
                Circle().fill(Clinical.tertiary.opacity(0.55)).frame(width: 6, height: 6)
            case .notExpected:
                Capsule().fill(Clinical.hairline).frame(width: 8, height: 1.5)
            case .today:
                Circle().strokeBorder(Clinical.accent, lineWidth: 1.5)
            case .upcoming:
                Circle().strokeBorder(Clinical.hairline, lineWidth: 1)
            }
        }
        .frame(width: 18, height: 18)
    }
}
