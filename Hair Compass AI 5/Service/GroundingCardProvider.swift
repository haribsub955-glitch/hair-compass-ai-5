//
//  GroundingCardProvider.swift
//  Hair Compass AI 5
//
//  Who supplies today's grounding card. The deterministic provider always answers and is the
//  exact fallback the spec requires (§10); a validated server card (G5) can sit in front of it.
//

import Foundation

@MainActor
protocol GroundingCardProvider {
    func card(input: GroundingInput, now: Date) async -> GroundingCard?
}

struct DeterministicGroundingProvider: GroundingCardProvider {
    func card(input: GroundingInput, now: Date) async -> GroundingCard? {
        GroundingCards.select(input)
    }
}
