//
//  LabProposalTests.swift
//  Hair Compass AI 5Tests
//
//  LabProposal.for(_:) is the honest lab→proposal mapper: a supplement only for a lab-confirmed
//  deficiency (ferritin / vitamin D / vitamin B12, each below its reference range), and a
//  clinician-only note for anything medical (thyroid, or any test that comes back above range).
//  It must never invent a product for a test it doesn't recognize, and an in-range result must
//  never produce a card.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct LabProposalTests {

    private let calendar = Calendar.current
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
    }

    // MARK: - Lab-confirmed deficiencies → supplement (iron also carries a clinician caution)

    @Test func lowFerritinProposesIronWithAClinicianCaution() {
        let result = LabResult(test: .ferritin, value: 18, collectedAt: now)   // < 30 → below
        let proposal = LabProposal.for(result)
        #expect(proposal?.kind == .both)
        #expect(proposal?.productIDs == ["iron"])
        #expect(proposal?.clinicianNote != nil)
    }

    @Test func lowVitaminDProposesTheVitaminDProductOnlyNoClinicianNote() {
        let result = LabResult(test: .vitaminD, value: 18, collectedAt: now)   // < 30 → below
        let proposal = LabProposal.for(result)
        #expect(proposal?.kind == .supplement)
        #expect(proposal?.productIDs == ["vitamind"])
        #expect(proposal?.clinicianNote == nil)
    }

    @Test func lowVitaminB12ProposesTheB12ProductOnlyNoClinicianNote() {
        let result = LabResult(test: .vitaminB12, value: 150, collectedAt: now)   // < 200 → below
        let proposal = LabProposal.for(result)
        #expect(proposal?.kind == .supplement)
        #expect(proposal?.productIDs == ["b12"])
        #expect(proposal?.clinicianNote == nil)
    }

    // MARK: - Medical findings → clinician only, never a sale

    @Test func outOfRangeThyroidRoutesToAClinicianWithNoProductsEitherDirection() {
        let high = LabResult(test: .tsh, value: 6.0, collectedAt: now)   // > 4.0 → above
        let low = LabResult(test: .tsh, value: 0.1, collectedAt: now)    // < 0.4 → below
        for result in [high, low] {
            let proposal = LabProposal.for(result)
            #expect(proposal?.kind == .clinician)
            #expect(proposal?.productIDs.isEmpty == true)
            #expect(proposal?.clinicianNote != nil)
        }
    }

    @Test func outOfRangeFreeT4AlsoRoutesToAClinician() {
        let result = LabResult(test: .freeT4, value: 2.5, collectedAt: now)   // > 1.8 → above
        let proposal = LabProposal.for(result)
        #expect(proposal?.kind == .clinician)
        #expect(proposal?.productIDs.isEmpty == true)
    }

    @Test func aboveRangeFerritinRoutesToAClinicianNeverASale() {
        let result = LabResult(test: .ferritin, value: 400, collectedAt: now)   // > 300 → above
        let proposal = LabProposal.for(result)
        #expect(proposal?.kind == .clinician)
        #expect(proposal?.productIDs.isEmpty == true)
    }

    @Test func aboveRangeVitaminB12RoutesToAClinicianNeverASale() {
        let result = LabResult(test: .vitaminB12, value: 1000, collectedAt: now)   // > 900 → above
        let proposal = LabProposal.for(result)
        #expect(proposal?.kind == .clinician)
        #expect(proposal?.productIDs.isEmpty == true)
    }

    // MARK: - In range → no card, ever

    @Test func inRangeFerritinNeverProposesACard() {
        let result = LabResult(test: .ferritin, value: 80, collectedAt: now)   // 30...300 → normal
        #expect(LabProposal.for(result) == nil)
    }

    @Test func inRangeThyroidNeverProposesACard() {
        let result = LabResult(test: .tsh, value: 2.0, collectedAt: now)   // 0.4...4.0 → normal
        #expect(LabProposal.for(result) == nil)
    }

    @Test func inRangeVitaminDAndB12NeverProposeACard() {
        let d = LabResult(test: .vitaminD, value: 50, collectedAt: now)     // 30...100 → normal
        let b12 = LabResult(test: .vitaminB12, value: 500, collectedAt: now) // 200...900 → normal
        #expect(LabProposal.for(d) == nil)
        #expect(LabProposal.for(b12) == nil)
    }

    // MARK: - Never invents a product outside the three known, lab-gated ids

    @Test func neverInventsAProductIDOutsideTheKnownThree() {
        let known: Set<String> = ["iron", "vitamind", "b12"]
        let lowCases: [(LabTest, Double)] = [(.ferritin, 5), (.vitaminD, 5), (.vitaminB12, 5)]
        for (test, value) in lowCases {
            let result = LabResult(test: test, value: value, collectedAt: now)
            let ids = LabProposal.for(result)?.productIDs ?? []
            #expect(ids.allSatisfy { known.contains($0) })
        }
    }
}
