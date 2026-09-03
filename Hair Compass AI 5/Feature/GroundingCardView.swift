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
//  same curve. A new card (a different headline) re-enters; a reopen of the same card does not.
//

import SwiftUI

struct GroundingCardView: View {
    let card: GroundingCard
    var onPrimary: (GroundingCard.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsReason = false

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
                    CompanionView(moment: .resting, variant: .avatar, size: 28)
                    Eyebrow(text: card.eyebrow, color: card.kind == .safety ? Clinical.warning : Clinical.secondary)
                }
                .groundingEntrance(id: card.headline)
                Text(card.headline)
                    .font(Clinical.headline(22, weight: .semibold))
                    .foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("groundingHeadline")
                    .groundingEntrance(id: card.headline)
                Text(card.body)
                    .font(Clinical.body(14.5))
                    .foregroundStyle(Clinical.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .groundingEntrance(id: card.headline)
                if let anchor = card.evidenceAnchor {
                    Text(anchor)
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                        .monospacedDigit()
                        .groundingEntrance(id: card.headline)
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
                    .groundingEntrance(id: card.headline, delay: MotionSpec.note.actionDelay)
                }
                Text(card.closure)
                    .font(Clinical.caption(12.5))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .groundingEntrance(id: card.headline)
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
                .groundingEntrance(id: card.headline, delay: MotionSpec.note.actionDelay)
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
