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
    /// True when today's plan just became complete with at least one real completion — the
    /// section passes `plan.isComplete && plan.completedCount > 0`. Only takes effect when
    /// `card.kind == .closure`.
    var celebrates: Bool = false
    var onPrimary: (GroundingCard.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsReason = false

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
                .groundingEntrance(id: entranceKey)
                Text(card.headline)
                    .font(Clinical.headline(22, weight: .semibold))
                    .foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("groundingHeadline")
                    .groundingEntrance(id: entranceKey)
                Text(card.body)
                    .font(Clinical.body(14.5))
                    .foregroundStyle(Clinical.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .groundingEntrance(id: entranceKey)
                if let anchor = card.evidenceAnchor {
                    Text(anchor)
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                        .monospacedDigit()
                        .groundingEntrance(id: entranceKey)
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
                    .groundingEntrance(id: entranceKey, delay: MotionSpec.note.actionDelay)
                }
                Text(card.closure)
                    .font(Clinical.caption(12.5))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .groundingEntrance(id: entranceKey)
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
                .groundingEntrance(id: entranceKey, delay: MotionSpec.note.actionDelay)
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
        .onAppear { triggerCelebrationIfNeeded() }
        .onChange(of: entranceKey) { _, _ in triggerCelebrationIfNeeded() }
        .onDisappear {
            halo2Task?.cancel(); halo2Task = nil
            breathTask?.cancel(); breathTask = nil
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

/// One-shot entrance for a grounding note: opacity 0 → 1 with a `MotionSpec.note.rise`-point
/// rise over `MotionSpec.note.duration`, keyed by `id` so a new card (a different identity)
/// re-enters while a reopen of the same live card does not. `delay` lets the action chip and
/// the footer row follow the headline group by `MotionSpec.note.actionDelay`. Reduce Motion and
/// `MotionQA.isStatic` drop the rise and animate opacity alone.
private struct GroundingEntrance: ViewModifier {
    let id: AnyHashable
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownID: AnyHashable?

    func body(content: Content) -> some View {
        let shown = shownID == id
        let staticGate = reduceMotion || MotionQA.isStatic
        content
            .opacity(shown ? 1 : 0)
            .offset(y: (shown || staticGate) ? 0 : MotionSpec.note.rise)
            .onAppear { trigger() }
            .onChange(of: id) { _, _ in trigger() }
    }

    private func trigger() {
        guard shownID != id else { return }
        // `HC_MOTION_STATIC` renders every one-shot in its final state — skip `withAnimation`
        // entirely rather than animating a motion QA is meant to prove doesn't happen.
        guard !MotionQA.isStatic else {
            shownID = id
            return
        }
        withAnimation(.easeOut(duration: MotionSpec.note.duration).delay(delay)) {
            shownID = id
        }
    }
}

private extension View {
    func groundingEntrance(id: some Hashable, delay: Double = 0) -> some View {
        modifier(GroundingEntrance(id: AnyHashable(id), delay: delay))
    }
}
