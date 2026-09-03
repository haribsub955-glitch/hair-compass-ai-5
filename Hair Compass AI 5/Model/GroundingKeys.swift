//
//  GroundingKeys.swift
//  Hair Compass AI 5
//
//  Pure key functions for Today's grounding surface: the day key every other key is built from,
//  the entrance identity (G2-R10 — fires once per day per card, again on a meaningful change,
//  never on a reopen), and the fingerprint that keys the provider `.task` (Important 11). No
//  `Date.now`, no `Calendar.current` — every input arrives as a parameter, so these are testable
//  in isolation and reusable anywhere Today needs the same identity.
//

import Foundation

enum GroundingKeys {

    /// `yyyy-MM-dd` in `calendar`, built from components — not a locale- or UTC-dependent
    /// formatter — so it never drifts a day off local midnight.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// G2-R10: the grounding note's entrance fires once per day per card, again on a meaningful
    /// state change (a new kind or headline), never on a reopen of the same live card.
    static func entranceKey(dayKey: String, card: GroundingCard) -> String {
        "\(dayKey)|\(card.kind.rawValue)|\(card.headline)"
    }

    /// Whether this card still owes the person its single daily entrance. Keeping this policy
    /// pure lets Today persist the completed identity across tab teardown and cold launches
    /// without making the animation modifier itself own product state.
    static func shouldAnimateEntrance(persistedKey: String, currentKey: String) -> Bool {
        !currentKey.isEmpty && persistedKey != currentKey
    }

    /// Close-the-Day is a response to a newly completed plan, not an open-screen reward. This
    /// includes an initially-complete cold launch and remains false after today's key is saved.
    static func shouldCelebrate(
        isComplete: Bool,
        completedCount: Int,
        celebratedDay: String,
        dayKey: String
    ) -> Bool {
        isComplete && completedCount > 0 && celebratedDay != dayKey
    }

    /// Keys the provider `.task` — a change of *kind* (a flag firing, the plan settling, a photo
    /// coming due…) produces a new fingerprint; an unrelated data write that leaves every input
    /// unchanged does not re-resolve the card. Each flag's `since` folds in at day granularity
    /// (a UTC epoch-day bucket — this stays calendar-free, so the function needs no `Calendar`
    /// parameter of its own) rather than full precision: most flags fire with `since: now`, so a
    /// full timestamp would change the fingerprint on every single render instead of once a day.
    static func fingerprint(_ input: GroundingInput, dayKey: String) -> String {
        [
            dayKey,
            input.flags.map { "\($0.id)-\(epochDay($0.since))" }.joined(separator: "."),
            input.plan.occurrences.map { "\($0.id)-\($0.state.rawValue)" }.joined(separator: ","),
            "\(input.missedYesterday)",
            "\(input.phase?.dayNumber ?? -1)-\(input.phase?.week ?? -1)",
            "\(input.photo)",
            "\(input.photoWithinTwoWeeks)",
            "\(input.consistency30?.completed ?? -1)/\(input.consistency30?.planned ?? -1)/\(input.consistency30?.scored ?? -1)",
            "\(input.sheddingAboveUsual)",
            "\(input.loggedToday)",
        ].joined(separator: "|")
    }

    private static func epochDay(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 86400)
    }
}
