//
//  ProjectionModelTests.swift
//  Hair Compass AI 5Tests
//
//  The end-of-onboarding paywall projection: the only quantitative curve is the published
//  male-AGA combination-therapy average, every other profile gets qualitative milestones, and
//  the honest disclaimer is present for every condition/sex combination.
//

import Testing
@testable import Hair_Compass_AI_5

@Test func maleAGAGetsTheOnlyQuantitativeCurve() {
    let p = ProjectionModel.make(condition: .androgenetic, sex: .male)
    let curve = try! #require(p.evidenceCurve)
    #expect(curve.first?.hairsPerCm2 == 0)
    #expect(abs((curve.last?.hairsPerCm2 ?? 0) - 29.7) < 0.01)
    #expect(curve.map(\.hairsPerCm2) == curve.map(\.hairsPerCm2).sorted())  // monotonic
}

@Test func everyoneElseGetsMilestonesOnly() {
    for c in HairCondition.allCases where !(c == .androgenetic) {
        for s in BiologicalSex.allCases {
            let p = ProjectionModel.make(condition: c, sex: s)
            #expect(p.evidenceCurve == nil)
            #expect(!p.milestones.isEmpty)
            #expect(!p.citation.isEmpty)
        }
    }
    #expect(ProjectionModel.make(condition: .androgenetic, sex: .female).evidenceCurve == nil)
}

@Test func disclaimerIsAlwaysPresentAndHonest() {
    for c in HairCondition.allCases {
        for s in BiologicalSex.allCases {
            let p = ProjectionModel.make(condition: c, sex: s)
            #expect(p.disclaimer.contains("not a prediction"))
        }
    }
}
