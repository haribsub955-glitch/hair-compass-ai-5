import SwiftUI

/// The Trends consistency card — the gamification surface. Level, XP progress, streak and
/// the most recent badges, all computed purely from the tracked record via `Gamification.swift`.
/// Everything here rewards the effort of tracking; nothing reads the hair outcome.
struct ConsistencyCard: View {
    let entries: [DailyEntry]
    let treatments: [Treatment]
    let doses: [TreatmentDose]
    let photos: [PhotoRecord]
    let labs: [LabResult]
    let triggers: [TriggerEvent]
    @Binding var showAllBadges: Bool

    /// Titles of badges newly earned since the user last saw this card (quiet celebration).
    @State private var freshBadges: [Achievement] = []

    /// UserDefaults key for badge ids the user has already been shown. Shared with
    /// CheckInCelebration, which marks badges it celebrates so they aren't re-celebrated here.
    static let seenKey = "seenAchievements"

    private var sideEffects: [SideEffectLog] { treatments.flatMap(\.sideEffects) }

    private var xp: Int {
        XP.total(entries: entries, doses: doses, photos: photos, labs: labs, triggers: triggers)
    }

    private var earned: [(achievement: Achievement, date: Date)] {
        Achievement.earnedList(
            entries: entries, treatments: treatments, doses: doses,
            photos: photos, labs: labs, sideEffects: sideEffects
        )
    }

    var body: some View {
        let xp = self.xp
        let level = GamificationLevel.level(for: xp)
        let progress = GamificationLevel.progressToNext(xp: xp)
        let streak = HairAnalytics.loggingStreak(entryDates: entries.map(\.date))
        let earned = self.earned

        ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                if let fresh = freshBadges.first {
                    newBadgeCapsule(fresh, extra: freshBadges.count - 1)
                }

                HStack {
                    Eyebrow(text: "Consistency")
                    Spacer()
                    Button {
                        showAllBadges = true
                    } label: {
                        HStack(spacing: 3) {
                            Text("All badges").font(Clinical.eyebrow(10))
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Clinical.accent)
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(level.name)
                        .font(Clinical.headline(24)).foregroundStyle(Clinical.ink)
                    Text("Level \(level.index)")
                        .font(Clinical.eyebrow(10)).tracking(1)
                        .foregroundStyle(Clinical.tertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ProgressBar(value: progress.fraction, tint: Clinical.gold)
                        .frame(height: 8)
                    HStack {
                        if let next = progress.next {
                            Text("\(xp) / \(next.threshold)")
                                .font(Clinical.number(13)).foregroundStyle(Clinical.ink)
                            Spacer()
                            Text("\(progress.remaining) XP to \(next.name)")
                                .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        } else {
                            Text("\(xp) XP")
                                .font(Clinical.number(13)).foregroundStyle(Clinical.ink)
                            Spacer()
                            Text("Top of the ladder")
                                .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        }
                    }
                }

                Label(
                    streak > 0
                        ? "\(streak)-day logging streak"
                        : "No current streak — any day you log starts one",
                    systemImage: "flame"
                )
                .font(.system(size: 12)).foregroundStyle(streak > 0 ? Clinical.accent : Clinical.tertiary)

                if !earned.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(earned.suffix(3).reversed(), id: \.achievement) { item in
                                badgeChip(item.achievement)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { registerNewBadges(earned.map(\.achievement)) }
    }

    // MARK: Pieces

    private func badgeChip(_ badge: Achievement) -> some View {
        HStack(spacing: 6) {
            BadgeIcon(badge: badge, size: 11, tint: Clinical.gold)
            Text(badge.title).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Clinical.gold)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Clinical.gold.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Clinical.gold.opacity(0.35), lineWidth: 1))
    }

    /// The quiet celebration: a small gold capsule, a success haptic, no modal, no confetti.
    private func newBadgeCapsule(_ badge: Achievement, extra: Int) -> some View {
        Label(
            extra > 0 ? "New badge — \(badge.title) +\(extra) more" : "New badge — \(badge.title)",
            systemImage: "sparkle"
        )
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Clinical.surface)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Clinical.gold, in: Capsule())
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Compares earned ids against the UserDefaults-persisted "seen" set; surfaces any new
    /// ones once, then remembers them. Purely additive — nothing is ever revoked.
    private func registerNewBadges(_ earnedNow: [Achievement]) {
        let defaults = UserDefaults.standard
        let seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
        let fresh = earnedNow.filter { !seen.contains($0.rawValue) }
        guard !fresh.isEmpty else { return }
        defaults.set(seen.union(earnedNow.map(\.rawValue)).sorted(), forKey: Self.seenKey)
        withAnimation(.easeOut(duration: 0.3)) { freshBadges = fresh.reversed() } // newest first
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            withAnimation(.easeOut(duration: 0.4)) { freshBadges = [] }
        }
    }
}

// MARK: - Badge icon

/// A badge's icon: the custom gouache illustration when its `art` asset is present in the bundle,
/// otherwise the SF-symbol fallback — so the app looks correct before any illustration ships, and
/// each drops in simply by adding its imageset. The tint applies to the symbol path only; a
/// full-colour illustration renders as-is (desaturated + faded when the badge is still locked).
struct BadgeIcon: View {
    let badge: Achievement
    var size: CGFloat = 18
    var tint: Color = Clinical.gold
    var dimmed: Bool = false

    var body: some View {
        if let art = UIImage(named: badge.art) {
            Image(uiImage: art)
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.55, height: size * 1.55)
                .saturation(dimmed ? 0.4 : 1)
                .opacity(dimmed ? 0.45 : 1)
        } else {
            Image(systemName: badge.symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(dimmed ? Clinical.tertiary.opacity(0.6) : tint)
        }
    }
}

// MARK: - All badges

/// The full badge wall: earned ones in gold with their date, unearned ones simply dimmed —
/// no locks, no countdowns, no pressure. The footer states the honesty rule out loud.
struct AchievementsSheet: View {
    let entries: [DailyEntry]
    let treatments: [Treatment]
    let doses: [TreatmentDose]
    let photos: [PhotoRecord]
    let labs: [LabResult]
    @Environment(\.dismiss) private var dismiss

    private var earnedDates: [Achievement: Date] {
        Dictionary(uniqueKeysWithValues: Achievement.earnedList(
            entries: entries, treatments: treatments, doses: doses,
            photos: photos, labs: labs, sideEffects: treatments.flatMap(\.sideEffects)
        ).map { ($0.achievement, $0.date) })
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let earnedDates = self.earnedDates
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Consistency")
                        Text("Badges")
                            .font(Clinical.headline(28)).foregroundStyle(Clinical.ink)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Clinical.tertiary, Clinical.surface)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 20)
                // Unboxed sprig bleeding from the sheet's top-right, behind the title —
                // a background, so the dismiss button above it stays tappable.
                .background(alignment: .topTrailing) { CornerSprig(width: 180, opacity: 0.45) }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Achievement.allCases) { badge in
                        badgeCell(badge, earnedOn: earnedDates[badge])
                    }
                }

                Text("XP and badges reward the consistency of your tracking — never how your hair is doing. A hard week costs nothing.")
                    .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .clinicalScreen()
    }

    private func badgeCell(_ badge: Achievement, earnedOn: Date?) -> some View {
        let isEarned = earnedOn != nil
        return VStack(alignment: .leading, spacing: 8) {
            BadgeIcon(badge: badge, size: 18, tint: Clinical.gold, dimmed: !isEarned)
                .frame(width: 40, height: 40)
                .background(
                    (isEarned ? Clinical.gold.opacity(0.14) : Clinical.canvas),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            Text(badge.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEarned ? Clinical.ink : Clinical.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let earnedOn {
                Text(earnedOn.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Clinical.eyebrow(9)).tracking(0.6)
                    .foregroundStyle(Clinical.gold)
            } else {
                Text(badge.caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Clinical.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Clinical.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isEarned ? Clinical.gold.opacity(0.3) : Clinical.hairline, lineWidth: 1)
        )
        .opacity(isEarned ? 1 : 0.72)
    }
}
