//
//  DeterministicGroundingProviderTests.swift
//  Hair Compass AI 5Tests
//
//  The provider seam (G2 task-4 amendment): the deterministic fallback always answers with
//  exactly the card `GroundingCards.select` would choose — a future validated server card (G5)
//  can sit in front of it without Today changing at all.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct DeterministicGroundingProviderTests {
    @Test func returnsTheSelectorsCard() async {
        let input = GroundingInput(
            flags: [], plan: PlanAdherence.TodayPlan(occurrences: []), missedYesterday: 0, phase: nil,
            photo: .upcoming(daysUntil: 12), photoWithinTwoWeeks: true,
            consistency30: nil, sheddingAboveUsual: false, loggedToday: true
        )
        let provider = DeterministicGroundingProvider()
        let card = await provider.card(input: input, now: .now)
        #expect(card == GroundingCards.select(input))
    }
}
