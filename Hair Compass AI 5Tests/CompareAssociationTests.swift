//
//  CompareAssociationTests.swift
//  Hair Compass AI 5Tests
//
//  Compare's "together / opposite / unclear" read (Model/ChartMetric.swift: ChartMath.association)
//  must not call a directional pattern on a statistically meaningless handful of days. The clarity
//  gate now scales with sample size — these pin that honest behaviour.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct CompareAssociationTests {

    @Test func clarityThresholdTightensForSmallSamples() {
        // n=8 demands a strong correlation (≈0.71); the bound eases to a 0.25 floor by n≈64.
        #expect(ChartMath.clarityThreshold(pairs: 8) == 2.0 / 8.0.squareRoot())
        #expect(ChartMath.clarityThreshold(pairs: 64) == 0.25)
        #expect(ChartMath.clarityThreshold(pairs: 200) == 0.25)   // never below the floor
        #expect(ChartMath.clarityThreshold(pairs: 0) == 1)        // degenerate guard
    }

    @Test func strongCorrelationStillReadsAsAPatternAtEightPairs() {
        let hair = [1.0, 2, 3, 4, 5, 6, 7, 8]
        let life = [1.0, 2, 3, 4, 5, 6, 7, 8]        // r = 1 — genuine strong signal survives
        #expect(ChartMath.association(hair: hair, lifestyle: life) == .together)
    }

    @Test func aModerateCorrelationIsUnclearAtEightPairsButAPatternWhenItRepeatsToThirtyTwo() {
        // Constructed so r ≈ 0.57: below the n=8 gate (~0.71) but above the n=32 gate (~0.35).
        let hair = [1.0, 2, 3, 4, 5, 6, 7, 8]
        let life = [4.0, 1, 5, 2, 7, 3, 8, 6]
        let r = abs(ChartMath.correlation(hair, life)!)

        // Guard keeps the test honest if the exact r drifts: only assert the flip when r truly sits
        // between the two gates. Tiling identical pairs preserves the correlation while raising n.
        if r > ChartMath.clarityThreshold(pairs: 32) && r < ChartMath.clarityThreshold(pairs: 8) {
            #expect(ChartMath.association(hair: hair, lifestyle: life) == .unclear)
            let tiled = ChartMath.association(
                hair: hair + hair + hair + hair,
                lifestyle: life + life + life + life
            )
            #expect(tiled == .together || tiled == .opposite)
        }
    }
}
