import SwiftUI

/// What the free tier sees instead of its own history: a count that grows every day.
///
/// This is the conversion mechanic of the whole free tier. It is deliberately not a locked
/// button — the check-in above it always works, so the number keeps climbing, and the offer
/// gets stronger the longer someone stays. Never show it at zero: "0 days recorded" reads as a
/// bug rather than an invitation.
struct LockedHistoryCard: View {
    let lockedCount: Int
    var onUnlock: () -> Void

    static func shouldShow(lockedCount: Int) -> Bool { lockedCount > 0 }

    static func headline(lockedCount: Int) -> String {
        "\(lockedCount) day\(lockedCount == 1 ? "" : "s") recorded"
    }

    var body: some View {
        if Self.shouldShow(lockedCount: lockedCount) {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .font(Clinical.caption(13))
                            .foregroundStyle(Clinical.tertiary)
                        Text(Self.headline(lockedCount: lockedCount))
                            .font(Clinical.headline(17))
                            .foregroundStyle(Clinical.ink)
                    }
                    Text("You haven't seen any of it yet. Unlock to read your own record.")
                        .font(Clinical.caption(13))
                        .foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Unlock my history", action: onUnlock)
                        .buttonStyle(ClinicalButtonStyle())
                        .accessibilityIdentifier("lockedHistoryUnlock")
                }
            }
            .accessibilityIdentifier("lockedHistoryCard")
        }
    }
}
