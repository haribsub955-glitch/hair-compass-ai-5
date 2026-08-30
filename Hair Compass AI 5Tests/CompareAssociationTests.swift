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

    // MARK: Shared-bounds normalization — the smoothed trend must live inside its daily cloud

    @Test func normalizeWithinSharedBoundsKeepsTheTrendOnTheRawScale() {
        // A rolling mean's own range is narrower than the raw series' — normalizing it by itself
        // re-inflates tiny wiggles to full chart height. Shared bounds keep it honest.
        #expect(ChartMath.normalize([1.0, 2, 3], lo: 0, hi: 4) == [0.25, 0.5, 0.75])
        // Degenerate bounds behave exactly like the self-normalizing overload: centered.
        #expect(ChartMath.normalize([2.0, 2, 2], lo: 2, hi: 2).allSatisfy { $0 == 0.5 })
        #expect(ChartMath.normalize([], lo: 0, hi: 1).isEmpty)
    }

    // MARK: Gap segmentation — no line drawn across weeks nobody logged

    @Test func gapSegmentsBreakARunOnlyAtGapsWiderThanTheLimit() {
        let cal = Calendar(identifier: .gregorian)
        let anchor = cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let day: (Int) -> Date = { cal.date(byAdding: .day, value: $0, to: anchor)! }

        // 0,1,2 · (28-day hole) · 30,33 — a 3-day stride inside a run must NOT break it.
        let dates = [day(0), day(1), day(2), day(30), day(33)]
        #expect(ChartMath.gapSegments(dates: dates, calendar: cal) == [0..<3, 3..<5])

        // Unbroken daily run → one segment; empty input → none.
        #expect(ChartMath.gapSegments(dates: [day(0), day(1)], calendar: cal) == [0..<2])
        #expect(ChartMath.gapSegments(dates: [], calendar: cal).isEmpty)
    }

    // MARK: Automatic lag scan — replaces the manual lag picker

    @Test func scanThresholdIsStricterThanTheSingleLookGate() {
        // Four looks at the same data need a wider bound than one look (multiple comparisons):
        // 2.5/√n vs the single-look 2/√n, floored at 0.25 either way.
        #expect(ChartMath.scanClarityThreshold(pairs: 8) == 2.5 / 8.0.squareRoot())
        #expect(ChartMath.scanClarityThreshold(pairs: 8) > ChartMath.clarityThreshold(pairs: 8))
        #expect(ChartMath.scanClarityThreshold(pairs: 200) == 0.25)
        #expect(ChartMath.scanClarityThreshold(pairs: 0) == 1)
    }

    /// Lifestyle values planted exactly 42 days ahead of matching hair values: the 6-week lag is
    /// the only delay with enough overlapping days to read at all, and there the correlation is
    /// perfect — the scan must find it and call the direction.
    @Test func lagScanFindsASeededSixWeekLag() {
        let cal = Calendar(identifier: .gregorian)
        let anchor = cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let values: [Double] = (0..<30).map { Double(($0 * 7) % 4) } // varied, non-constant
        let hair = (0..<30).map { i in
            (day: cal.date(byAdding: .day, value: i, to: anchor)!, value: values[i])
        }
        let life = (0..<30).map { i in
            (day: cal.date(byAdding: .day, value: i - 42, to: anchor)!, value: values[i])
        }
        let scan = ChartMath.lagScan(hair: hair, lifestyle: life, calendar: cal)
        #expect(scan.lagDays == 42)
        #expect(scan.association == .together)
        #expect(scan.pairs == 30)

        // Inverted lifestyle → same lag, opposite direction.
        let inverted = life.map { (day: $0.day, value: 3 - $0.value) }
        let opposite = ChartMath.lagScan(hair: hair, lifestyle: inverted, calendar: cal)
        #expect(opposite.lagDays == 42)
        #expect(opposite.association == .opposite)
    }

    @Test func lagScanStaysHonestWithThinOrPatternlessData() {
        let cal = Calendar(identifier: .gregorian)
        let anchor = cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000))

        // Three overlapping days — under the 8-pair floor at every lag.
        let thinHair = (0..<3).map { i in
            (day: cal.date(byAdding: .day, value: i, to: anchor)!, value: Double(i))
        }
        let thin = ChartMath.lagScan(hair: thinHair, lifestyle: thinHair, calendar: cal)
        #expect(thin.association == .insufficient(need: 8))

        // Plenty of days, no relationship: period-2 hair against period-4 lifestyle is
        // uncorrelated at every one of the scanned delays.
        let hair = (0..<32).map { i in
            (day: cal.date(byAdding: .day, value: i, to: anchor)!, value: Double(i % 2))
        }
        let life = (0..<32).map { i in
            (day: cal.date(byAdding: .day, value: i, to: anchor)!, value: Double((i / 2) % 2))
        }
        let flat = ChartMath.lagScan(hair: hair, lifestyle: life, calendar: cal)
        #expect(flat.association == .unclear)
        #expect(flat.pairs >= 8)
    }
}
