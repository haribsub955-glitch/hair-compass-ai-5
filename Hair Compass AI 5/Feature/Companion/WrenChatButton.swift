import SwiftData
import SwiftUI

/// The always-available way to reach Wren: a small avatar button that sits above the tab bar and,
/// when tapped, expands into a bubble naming what she can do *on the screen you're actually on*
/// (`Companion.openingLine(for:)`). Tapping the expanded bubble opens the chat with that screen's
/// focus already set, so the first answer lands on what's in front of you.
///
/// Two states, deliberately:
/// - **Collapsed** — just Wren's portrait. Small enough to ignore, and it never covers content
///   (it sits in the tab bar's inset, right-aligned, clear of the bar's own labels).
/// - **Expanded** — the contextual line beside her. Auto-collapses after a few seconds so it can't
///   sit on top of the screen indefinitely.
///
/// It builds the same canonical `AIContext` snapshot at open time that `TodayView` and
/// `CompareView` do, from its own queries, so `RootView` doesn't grow five more of them.
struct WrenChatButton: View {
    let tab: AppTab
    let profile: Profile?
    var canIntroduce = true
    var onGuideAction: (CompanionGuideAction) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query private var snapshots: [HealthSnapshot]
    @Query private var triggers: [TriggerEvent]
    @Query private var labs: [LabResult]
    @Query private var sideEffects: [SideEffectLog]
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]
    @Query private var progressCheckIns: [ProgressCheckIn]

    @State private var expanded = false
    @State private var showGuide = false
    @State private var showChat = false
    @State private var chatIsNewcomerGuide = false
    @State private var contextJSON = ""
    /// Bumped on every expand so a later auto-collapse can tell whether it's still the current one.
    @State private var expansionID = 0
    @AppStorage("wren.newcomerGuideIntroduced.v1") private var newcomerGuideIntroduced = false

    private var line: String { Companion.openingLine(for: tab) }
    private var forceNewcomerGuide: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("HC_WREN_GUIDE")
        #else
        false
        #endif
    }
    private var newcomerGuide: CompanionNewcomerGuide? {
        guard let profile else { return nil }
        return Companion.newcomerGuide(
            profileCreatedAt: forceNewcomerGuide ? .now : profile.createdAt,
            firstEntryDate: forceNewcomerGuide ? .now : entries.last?.date,
            hasOnboarded: forceNewcomerGuide ? true : profile.hasOnboarded,
            // The launch flag is a deterministic visual-QA state: onboarding's seeded check-in
            // is ready, while the two genuinely optional setup actions are still untouched.
            hasLoggedToday: forceNewcomerGuide
                || entries.contains { Calendar.current.isDateInToday($0.date) },
            hasRoutine: forceNewcomerGuide ? false : !treatments.isEmpty,
            hasBaselinePhoto: forceNewcomerGuide ? false : !photos.isEmpty
        )
    }
    private var introductionTaskID: String {
        "\(canIntroduce)|\(newcomerGuide?.dayNumber ?? 0)|\(forceNewcomerGuide)"
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showChat) {
            HairChatSheet(
                contextJSON: contextJSON,
                focus: chatIsNewcomerGuide
                    ? "The person is opening Wren's first-week guide and wants calm, practical help learning what to track."
                    : Companion.chatFocus(for: tab),
                eyebrow: chatIsNewcomerGuide ? "First week with Wren" : "Ask \(Companion.name)",
                starterKind: chatIsNewcomerGuide ? .newcomer : .fullRecord
            )
        }
        .sheet(isPresented: $showGuide) {
            if let newcomerGuide {
                WrenNewcomerGuideSheet(
                    guide: newcomerGuide,
                    onAction: onGuideAction,
                    onAskWren: openNewcomerChat
                )
            }
        }
        // Introduce Wren once, after onboarding/lock/launch ritual have genuinely cleared. The
        // compact invitation is enough to be noticed and still retracts, so it does not become a
        // second onboarding screen the person must dismiss.
        .task(id: introductionTaskID) {
            guard canIntroduce, newcomerGuide != nil,
                  !newcomerGuideIntroduced || forceNewcomerGuide else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard canIntroduce, newcomerGuide != nil else { return }
            if !forceNewcomerGuide { newcomerGuideIntroduced = true }
            reveal()
        }
        // A new screen invalidates whatever she was offering about the old one.
        .onChange(of: tab) { _, _ in collapse() }
    }

    @ViewBuilder
    private var control: some View {
        if expanded {
            if let newcomerGuide {
                Button {
                    collapse()
                    showGuide = true
                } label: {
                    HStack(spacing: 10) {
                        avatar
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FIRST WEEK WITH WREN")
                                .font(Clinical.eyebrow(9))
                                .foregroundStyle(Clinical.accent)
                            Text(newcomerGuide.invitation)
                                .font(Clinical.caption(12.5))
                                .foregroundStyle(Clinical.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Image(systemName: "chevron.right")
                            .font(Clinical.caption(11))
                            .foregroundStyle(Clinical.accent)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(bubbleBackground)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wrenGuideInvite")
                .accessibilityLabel("First week with Wren. \(newcomerGuide.invitation)")
                .accessibilityHint("Opens three instructions for getting started")
                .transition(expandedTransition)
            } else {
                Button(action: openChat) {
                    HStack(spacing: 10) {
                        avatar
                        Text(line)
                            .font(Clinical.caption(12.5))
                            .foregroundStyle(Clinical.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .font(Clinical.caption(11))
                            .foregroundStyle(Clinical.accent)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(bubbleBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask \(Companion.name). \(line)")
                .accessibilityHint("Opens the chat about this screen")
                .transition(expandedTransition)
            }
        } else {
            Button(action: expand) {
                avatar
                    .padding(5)
                    .background(bubbleBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask \(Companion.name)")
            .accessibilityHint("Shows what \(Companion.name) can tell you about this screen")
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    private var expandedTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.86, anchor: .trailing).combined(with: .opacity)
    }

    private var avatar: some View {
        CompanionView(moment: .greeting, variant: .avatar, size: 34)
            .overlay(alignment: .bottomTrailing) {
                // The chat affordance the request asked for: she reads as a message button at a
                // glance, without losing the character.
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Clinical.surface)
                    .padding(3)
                    .background(Clinical.accent, in: Circle())
                    .overlay(Circle().strokeBorder(Clinical.canvas, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
    }

    private var bubbleBackground: some View {
        Capsule(style: .continuous)
            .fill(Clinical.surface)
            .overlay(Capsule(style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
            .shadow(color: Clinical.cardShadow, radius: 10, y: 4)
    }

    private func expand() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        reveal()
    }

    private func reveal() {
        withAnimation(motion) { expanded = true }
        expansionID += 1
        let id = expansionID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            // Only retract the expansion this task opened — a re-tap in the meantime wins.
            guard id == expansionID, expanded else { return }
            withAnimation(motion) { expanded = false }
        }
    }

    private func collapse() {
        expansionID += 1
        guard expanded else { return }
        withAnimation(motion) { expanded = false }
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.78)
    }

    /// Snapshot the canonical context at open time — same pattern as `TodayView.openChat()`.
    private func openChat() {
        presentChat(asNewcomerGuide: false)
    }

    private func openNewcomerChat() {
        presentChat(asNewcomerGuide: true)
    }

    private func presentChat(asNewcomerGuide: Bool) {
        contextJSON = AIContext.build(
            entries: entries, treatments: treatments, doses: doses,
            snapshots: snapshots, triggers: triggers,
            labs: labs, sideEffects: sideEffects, photos: photos,
            profile: profile, progressCheckIns: progressCheckIns, now: .now
        ).jsonString()
        collapse()
        chatIsNewcomerGuide = asNewcomerGuide
        showChat = true
    }
}

/// Wren's newcomer hand-off is intentionally a guide, not a tutorial carousel. Every row says
/// why the action matters, reflects completion from the real record, and leads directly to the
/// relevant surface. The final sentence counters the most harmful first-week behaviour here:
/// repeatedly checking for a result before hair biology has had time to move.
private struct WrenNewcomerGuideSheet: View {
    let guide: CompanionNewcomerGuide
    let onAction: (CompanionGuideAction) -> Void
    let onAskWren: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    introduction
                    personaStrip

                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR FIRST WEEK")
                            .font(Clinical.eyebrow(10))
                            .foregroundStyle(Clinical.accent)
                        Text("Three small things. Then let the record breathe.")
                            .font(Clinical.headline(24))
                            .foregroundStyle(Clinical.ink)
                    }

                    VStack(spacing: 10) {
                        ForEach(Array(guide.steps.enumerated()), id: \.element.id) { index, step in
                            guideRow(step, number: index + 1)
                                .staggeredEntrance(index: index)
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hourglass")
                            .font(Clinical.body(14, weight: .semibold))
                            .foregroundStyle(Clinical.sage)
                            .padding(.top, 2)
                        Text(Companion.newcomerReassurance)
                            .font(Clinical.body(14, weight: .medium))
                            .foregroundStyle(Clinical.ink)
                    }
                    .padding(14)
                    .background(Clinical.sage.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }

            Button {
                dismissThen(onAskWren)
            } label: {
                Label("Ask Wren about getting started", systemImage: "bubble.left.and.text.bubble.right")
            }
            .buttonStyle(ClinicalButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Clinical.canvas)
            .accessibilityIdentifier("wrenGuideAsk")
        }
        .clinicalScreen()
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("wrenNewcomerGuide")
    }

    private var header: some View {
        HStack(spacing: 10) {
            CompanionView(moment: .greeting, variant: .avatar, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(Companion.name)
                    .font(Clinical.headline(20))
                    .foregroundStyle(Clinical.ink)
                Text("DAY \(guide.dayNumber) · \(guide.completedCount) OF \(guide.steps.count) READY")
                    .font(Clinical.eyebrow(9))
                    .foregroundStyle(Clinical.tertiary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(Clinical.body(13, weight: .semibold))
                    .foregroundStyle(Clinical.secondary)
                    .frame(width: 32, height: 32)
                    .background(Clinical.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Close first-week guide")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var introduction: some View {
        HStack(alignment: .center, spacing: 14) {
            CompanionView(moment: .listening, variant: .pose, size: 88)
            VStack(alignment: .leading, spacing: 5) {
                Text(Companion.role.uppercased())
                    .font(Clinical.eyebrow(10))
                    .foregroundStyle(Clinical.accent)
                Text(Companion.introduction)
                    .font(Clinical.body(14))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var personaStrip: some View {
        HStack(spacing: 8) {
            personaTrait("Calm", symbol: "wind")
            personaTrait("Honest", symbol: "scope")
            personaTrait("One step", symbol: "arrow.right")
        }
    }

    private func personaTrait(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(Clinical.caption(11))
            .foregroundStyle(Clinical.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Clinical.surface)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    private func guideRow(_ step: CompanionGuideStep, number: Int) -> some View {
        Button {
            guard !step.isComplete else { return }
            dismissThen { onAction(step.action) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(step.isComplete ? Clinical.sage.opacity(0.16) : Clinical.accentSoft)
                        .frame(width: 38, height: 38)
                    Image(systemName: step.isComplete ? "checkmark" : step.action.symbol)
                        .font(Clinical.body(14, weight: .semibold))
                        .foregroundStyle(step.isComplete ? Clinical.positive : Clinical.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(number). \(step.action.title)")
                        .font(Clinical.body(15, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                    Text(step.action.instruction)
                        .font(Clinical.caption(12.5))
                        .foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.isComplete ? "Ready" : step.action.buttonTitle)
                        .font(Clinical.caption(11).weight(.semibold))
                        .foregroundStyle(step.isComplete ? Clinical.positive : Clinical.accent)
                        .padding(.top, 2)
                }
                Spacer(minLength: 4)
                if !step.isComplete {
                    Image(systemName: "arrow.up.right")
                        .font(Clinical.caption(11).weight(.semibold))
                        .foregroundStyle(Clinical.accent)
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.clinicalPressable)
        .disabled(step.isComplete)
        .accessibilityIdentifier("wrenGuide.\(step.action.rawValue)")
        .accessibilityValue(step.isComplete ? "Ready" : "Not ready")
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            action()
        }
    }
}
