import SwiftUI
import UIKit

/// The calm reward moment shown right after a daily check-in is saved: the XP the check-in
/// earned, the streak, progress to the next level, and any badge just unlocked. Presented
/// as a medium bottom sheet (the app's whole flow is sheet-based, so the celebration reads
/// as the natural coda to the log sheet rather than a modal interruption).
///
/// Effort-only copy rule: everything here celebrates the act of tracking — never a hair
/// outcome. Auto-dismisses after ~3.5 s; tapping anywhere dismisses instantly.
struct CheckInCelebration: View {
    let reward: CheckInReward

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Clinical.canvas.ignoresSafeArea()
            LeafFallBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer(minLength: 0)

                LivingArtwork(
                    art: CompanionArt.celebrating,
                    contentMode: .fit,
                    travel: 2,
                    zoom: 0.025,
                    phase: 0.8
                )
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
                // The opening beat: nine petals lift out from behind Wren and fade, once,
                // then the ambient LeafFallBackdrop drift is all that remains. A staged
                // entrance is the one thing the hash-seeded Canvas flecks can't do — they
                // have no beginning. Still a breeze, never a confetti cannon: brand-token
                // petals, sub-second, gone. One-shots vanish under Reduce Motion (see
                // ClinicalLottie), same rule that holds the backdrop's flecks static.
                .background {
                    ClinicalLottie(name: "celebration-burst", mode: .once)
                        .frame(width: 220, height: 220)
                }

                if reward.leveledUp {
                    levelUpHeadline
                } else {
                    xpHeadline
                }

                if reward.streak > 0 {
                    streakChip
                }

                progressBlock
                    .padding(.horizontal, 36)

                if let badge = reward.newBadges.first {
                    newBadgeChip(badge, extra: reward.newBadges.count - 1)
                }

                Spacer(minLength: 0)

                Text("Done")
                    .font(Clinical.body(13, weight: .semibold))
                    .foregroundStyle(Clinical.tertiary)
                    .padding(.bottom, 18)
            }
            .padding(.top, 28)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            markNewBadgesSeen()
        }
        .task {
            // The quiet exit: linger long enough to be read, never long enough to nag.
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            dismiss()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    // MARK: Pieces

    /// The default spotlight: what this check-in earned, in gold serif, under an identity-framed
    /// line — "you're someone who shows up" reads as durable, never an outcome claim (research:
    /// identity-based copy outlasts outcome copy; see docs/research/2026-07-11-engagement-science).
    private var xpHeadline: some View {
        VStack(spacing: 6) {
            Text("+\(reward.xpGained) XP")
                .font(Clinical.headline(44))
                .foregroundStyle(Clinical.gold)
            Text(identityLine)
                .font(Clinical.body(13, weight: .medium))
                .foregroundStyle(Clinical.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    /// Effort/identity framing — never mentions shedding or scalp severity, only the act of
    /// showing up. Includes the streak day count once one exists (endowed-progress framing).
    private var identityLine: String {
        reward.streak > 0
            ? "You're someone who shows up for your hair — day \(reward.streak)."
            : "You're someone who shows up for your hair."
    }

    /// When the save crossed a rung, the new level takes the spotlight instead.
    private var levelUpHeadline: some View {
        VStack(spacing: 8) {
            Eyebrow(text: "Level \(reward.level.index) · +\(reward.xpGained) XP", color: Clinical.gold)
            Text("You've grown into a \(reward.level.name)")
                .font(Clinical.headline(30))
                .foregroundStyle(Clinical.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    /// Same chip language as the Today hero's streak chip.
    private var streakChip: some View {
        Label("\(reward.streak)-day streak", systemImage: "flame.fill")
            .font(Clinical.eyebrow(10))
            .foregroundStyle(Clinical.accent)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Clinical.surface.opacity(0.85), in: Capsule())
            .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    private var progressBlock: some View {
        VStack(spacing: 6) {
            ProgressBar(value: reward.progressToNext.fraction, tint: Clinical.gold)
                .frame(height: 8)
            HStack {
                Text("\(reward.totalXP) XP")
                    .font(Clinical.number(12)).foregroundStyle(Clinical.ink)
                Spacer()
                if let next = reward.progressToNext.next {
                    Text("\(reward.progressToNext.remaining) XP to \(next.name)")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                } else {
                    Text("Top of the ladder")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                }
            }
        }
    }

    /// Same gold-capsule language as ConsistencyCard's quiet badge celebration.
    private func newBadgeChip(_ badge: Achievement, extra: Int) -> some View {
        Label(
            extra > 0 ? "New badge — \(badge.title) +\(extra) more" : "New badge — \(badge.title)",
            systemImage: badge.symbol
        )
        .font(Clinical.body(12, weight: .semibold))
        .foregroundStyle(Clinical.surface)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Clinical.gold, in: Capsule())
    }

    /// Badges celebrated here are marked into the shared "seen" set so the Trends
    /// ConsistencyCard doesn't re-celebrate the same unlock (it only surfaces unseen ids).
    private func markNewBadgesSeen() {
        guard !reward.newBadges.isEmpty else { return }
        let defaults = UserDefaults.standard
        let seen = Set(defaults.stringArray(forKey: ConsistencyCard.seenKey) ?? [])
        defaults.set(
            seen.union(reward.newBadges.map(\.rawValue)).sorted(),
            forKey: ConsistencyCard.seenKey
        )
    }
}

/// Identity for `.sheet(item:)` presentation — derived from the reward's content.
extension CheckInReward: Identifiable {
    var id: String {
        "\(totalXP)-\(xpGained)-\(streak)-\(newBadges.map(\.rawValue).joined(separator: "."))"
    }
}

// MARK: - Backdrop

/// A quiet Canvas particle moment: a few gold/copper leaf-flecks drifting down — a breeze
/// through the botanicals, not a confetti cannon. Fully deterministic: every fleck's path is
/// a pure function of the timeline (hash-seeded positions, same hash family as LogMotifs /
/// HairPhysics), so there is no simulation state. Under Reduce Motion the timeline pauses
/// and the flecks hold a static hash-fixed scatter.
private struct LeafFallBackdrop: View {
    var fleckCount: Int = 14

    var body: some View {
        MotionTimeline(cadence: .ambient) { timeline, reduceMotion in
            Canvas { ctx, size in
                let t: CGFloat = reduceMotion
                    ? 0
                    : CGFloat(timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 3600))
                for k in 0..<fleckCount {
                    drawFleck(k, in: ctx, size: size, time: t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawFleck(_ k: Int, in ctx: GraphicsContext, size: CGSize, time t: CGFloat) {
        let travel = size.height + 40
        let speed: CGFloat = 11 + hash(k, 42) * 11          // 11–22 pt/s: drifting, not falling
        let phase = hash(k, 45) * 6.28
        let x = hash(k, 41) * size.width + sin(t * 0.5 + phase) * 12
        let y = (hash(k, 43) * travel + t * speed).truncatingRemainder(dividingBy: travel) - 20
        let r = 2.2 + hash(k, 44) * 2.8

        // Gold and copper flecks, with the odd sage leaf — brand tokens only, kept faint.
        let palette = [Clinical.gold, Clinical.accent, Clinical.gold, Clinical.sage]
        let color = palette[k % palette.count].opacity(0.20 + Double(hash(k, 46)) * 0.14)

        var c = ctx
        c.translateBy(x: x, y: y)
        c.rotate(by: .radians(Double(phase + t * 0.4)))
        c.fill(
            Path(ellipseIn: CGRect(x: -r, y: -r * 0.62, width: r * 2, height: r * 1.24)),
            with: .color(color)
        )
    }

    // Same deterministic hash family as LogMotifs / CountScrubber.
    private func hash(_ i: Int, _ salt: CGFloat) -> CGFloat {
        let x = sin(CGFloat(i + 1) * 127.1 + salt * 311.7) * 43758.5453
        return x - x.rounded(.down)
    }
}
