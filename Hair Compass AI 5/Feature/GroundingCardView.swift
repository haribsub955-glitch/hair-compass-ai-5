//
//  GroundingCardView.swift
//  Hair Compass AI 5
//
//  The Daily Grounding card as a reassuring note, not a dashboard tile: eyebrow, a small Wren
//  avatar, a serif headline, two or three sentences, an optional anchor from the record, one
//  action rendered as an outlined chip (never a second filled button on Today), the closure
//  line, and "Why this?" which reveals the one fact that chose the card.
//
//  Motion (G2 motion amendment M2): the note enters once per card identity — opacity 0 → 1 and
//  a 6 pt rise over 0.35 s — and the action chip and the footer row follow 80 ms later on the
//  same curve. A new card (a different `entranceKey`) re-enters; a reopen of the same card does
//  not. `entranceKey` is computed by the owner (Today) as day|kind|headline (G2-R10) so the
//  entrance fires once per day per card, again on a meaningful state change, never on a reopen.
//
//  Motion (G2 motion amendment M4, "Close the Day"): when `card.kind == .closure && celebrates`,
//  a botanical halo blooms behind the Wren avatar and Wren breathes once, on first appearance of
//  that card identity. One-shot; gated on Reduce Motion / `MotionQA.isStatic`.
//

import SwiftUI

struct GroundingCardView: View {
    let card: GroundingCard
    /// Owner-computed identity for the entrance animation — see G2-R10. Distinct from
    /// `card.headline` alone so the entrance also resets once per calendar day.
    var entranceKey: String
    /// False when Today has already persisted this exact day/kind/headline identity. In that
    /// case every child renders settled on the first frame; local view reconstruction never
    /// replays the note.
    var animatesEntrance: Bool = true
    /// True when today's plan just became complete with at least one real completion — the
    /// section passes `plan.isComplete && plan.completedCount > 0`. Only takes effect when
    /// `card.kind == .closure`.
    var celebrates: Bool = false
    var onEntranceCompleted: (String) -> Void = { _ in }
    var onPrimary: (GroundingCard.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsReason = false
    @State private var mainVisible = false
    @State private var followerVisible = false
    @State private var entranceTask: Task<Void, Never>?

    // MARK: Close the Day halo/breath (M4)
    @State private var celebratedKey: String?
    @State private var haloScale1: CGFloat = 0.6
    @State private var haloOpacity1: Double = 0
    @State private var haloScale2: CGFloat = 0.6
    @State private var haloOpacity2: Double = 0
    @State private var breathScale: CGFloat = 1
    @State private var halo2Task: Task<Void, Never>?
    @State private var breathTask: Task<Void, Never>?

    private var isStatic: Bool { reduceMotion || MotionQA.isStatic }
    private var showsHalo: Bool { celebrates && card.kind == .closure }
    private var showsMain: Bool { !animatesEntrance || mainVisible || isStatic }
    private var showsFollower: Bool { !animatesEntrance || followerVisible || isStatic }

    private var actionLabel: String? {
        switch card.primary {
        case .completePlanItem(_, let label): return label
        case .logCheckIn: return "Log today's check-in"
        case .openPhotos: return "Open photos"
        case .openPlan: return "See the evidence path"
        case .prepareVisit: return "Prepare your visit notes"
        case .none: return nil
        }
    }

    private var actionSymbol: String {
        switch card.primary {
        case .completePlanItem: return "circle"
        case .logCheckIn: return "square.and.pencil"
        case .openPhotos: return "camera"
        case .openPlan: return "point.topleft.down.curvedto.point.bottomright.up"
        case .prepareVisit: return "doc.text"
        case .none: return ""
        }
    }

    var body: some View {
        ClinicalCard(padding: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        if showsHalo {
                            Circle()
                                .strokeBorder(Clinical.sage.opacity(0.35), lineWidth: 1)
                                .frame(width: 28, height: 28)
                                .scaleEffect(haloScale1)
                                .opacity(haloOpacity1)
                            Circle()
                                .strokeBorder(Clinical.sage.opacity(0.18), lineWidth: 1)
                                .frame(width: 28, height: 28)
                                .scaleEffect(haloScale2)
                                .opacity(haloOpacity2)
                        }
                        CompanionView(moment: .resting, variant: .avatar, size: 28)
                            .scaleEffect(breathScale)
                    }
                    Eyebrow(text: card.eyebrow, color: card.kind == .safety ? Clinical.warning : Clinical.secondary)
                }
                .groundingEntrance(isVisible: showsMain, staticState: isStatic)
                Text(card.headline)
                    .font(Clinical.headline(22, weight: .semibold))
                    .foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("groundingHeadline")
                    .groundingEntrance(isVisible: showsMain, staticState: isStatic)
                Text(card.body)
                    .font(Clinical.body(14.5))
                    .foregroundStyle(Clinical.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .groundingEntrance(isVisible: showsMain, staticState: isStatic)
                if let anchor = card.evidenceAnchor {
                    Text(anchor)
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                        .monospacedDigit()
                        .groundingEntrance(isVisible: showsMain, staticState: isStatic)
                }
                if let actionLabel {
                    Button { onPrimary(card.primary) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: actionSymbol).font(Clinical.body(12, weight: .medium))
                            Text(actionLabel).font(Clinical.body(13, weight: .medium))
                        }
                        .foregroundStyle(Clinical.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Clinical.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.clinicalPressable)
                    .minimumHitTarget()
                    .accessibilityIdentifier("groundingAction")
                    // Differs from the plan row's own circle ("Mark <name> complete") — without
                    // this, VoiceOver reads two identically-labeled controls that do the same
                    // thing from two different places on the page.
                    .accessibilityLabel("\(actionLabel) from today's note")
                    .groundingEntrance(isVisible: showsFollower, staticState: isStatic)
                }
                Text(card.closure)
                    .font(Clinical.caption(12.5))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .groundingEntrance(isVisible: showsFollower, staticState: isStatic)
                HStack {
                    Button(showsReason ? "Hide" : "Why this?") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsReason.toggle() }
                    }
                    .font(Clinical.body(12, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .accessibilityIdentifier("groundingWhy")
                    Spacer(minLength: 0)
                }
                .groundingEntrance(isVisible: showsFollower, staticState: isStatic)
                if showsReason {
                    Text(card.reason)
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                        .accessibilityIdentifier("groundingReason")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("groundingCard")
        .onAppear {
            triggerEntranceIfNeeded()
            triggerCelebrationIfNeeded()
        }
        .onChange(of: entranceKey) { _, _ in
            triggerEntranceIfNeeded(reset: true)
            triggerCelebrationIfNeeded()
        }
        .onChange(of: celebrates) { _, _ in triggerCelebrationIfNeeded() }
        .onDisappear {
            entranceTask?.cancel(); entranceTask = nil
            halo2Task?.cancel(); halo2Task = nil
            breathTask?.cancel(); breathTask = nil
        }
    }

    /// One shared entrance state for the whole note. The previous implementation gave every row
    /// an independent local modifier, so recreating Today replayed several animations and could
    /// leave a static screenshot with a blank card. The owner persists completion only after the
    /// follower curve settles.
    private func triggerEntranceIfNeeded(reset: Bool = false) {
        entranceTask?.cancel()
        entranceTask = nil
        if reset {
            mainVisible = false
            followerVisible = false
        }

        guard animatesEntrance else {
            mainVisible = true
            followerVisible = true
            return
        }
        guard !isStatic else {
            mainVisible = true
            followerVisible = true
            onEntranceCompleted(entranceKey)
            return
        }

        withAnimation(.easeOut(duration: MotionSpec.note.duration)) {
            mainVisible = true
        }
        let key = entranceKey
        entranceTask = Task {
            try? await Task.sleep(for: .seconds(MotionSpec.note.actionDelay))
            guard !Task.isCancelled, entranceKey == key else { return }
            withAnimation(.easeOut(duration: MotionSpec.note.duration)) {
                followerVisible = true
            }
            try? await Task.sleep(for: .seconds(MotionSpec.note.duration))
            guard !Task.isCancelled, entranceKey == key else { return }
            onEntranceCompleted(key)
            entranceTask = nil
        }
    }

    /// Plays the halo + breath once per card identity, only for a closure card that just
    /// completed the plan. Reduce Motion / `MotionQA.isStatic` skip the motion entirely — no
    /// halo, no breath — matching M4's Reduce Motion contract.
    private func triggerCelebrationIfNeeded() {
        guard showsHalo, celebratedKey != entranceKey else { return }
        celebratedKey = entranceKey
        guard !isStatic else { return }
        haloScale1 = 0.6
        haloOpacity1 = 0.6
        withAnimation(.easeOut(duration: MotionSpec.closeTheDay.halo)) {
            haloScale1 = 1.5
            haloOpacity1 = 0
        }
        halo2Task?.cancel()
        halo2Task = Task {
            try? await Task.sleep(for: .seconds(0.12))
            guard !Task.isCancelled else { return }
            haloScale2 = 0.6
            haloOpacity2 = 0.3
            withAnimation(.easeOut(duration: MotionSpec.closeTheDay.halo)) {
                haloScale2 = 1.5
                haloOpacity2 = 0
            }
        }
        let half = MotionSpec.closeTheDay.breath / 2
        withAnimation(.easeInOut(duration: half)) {
            breathScale = 1.03
        }
        breathTask?.cancel()
        breathTask = Task {
            try? await Task.sleep(for: .seconds(half))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: half)) {
                breathScale = 1
            }
        }
    }
}

private extension View {
    func groundingEntrance(isVisible: Bool, staticState: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .offset(y: (isVisible || staticState) ? 0 : MotionSpec.note.rise)
    }
}
