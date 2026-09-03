//
//  CompassScoreExplanationTests.swift
//  Hair Compass AI 5Tests
//
//  The score's explanation is generated from the same weights the score uses, so the words on
//  screen cannot drift from the arithmetic.
//

import Testing
@testable import Hair_Compass_AI_5

struct CompassScoreExplanationTests {
    @Test func explanationNamesEveryFactorAndItsWeight() {
        let text = CompassScore.explanation
        #expect(text.contains("check-in"))
        #expect(text.contains("doses"))
        #expect(text.contains("photo"))
        #expect(text.contains("\(Int(CompassScore.Weights.log))"))
        #expect(text.contains("\(Int(CompassScore.Weights.care))"))
        #expect(text.contains("\(Int(CompassScore.Weights.lens))"))
        #expect(text.lowercased().contains("never") && text.lowercased().contains("hair"), "it must say the score is not about hair health")
        #expect(text.contains("On days with nothing scheduled, the check-in and the photo share the whole 100."),
                "it must say what happens on a day with nothing scheduled")
    }

    @Test func weightsStillProduceTheKnownScores() {
        #expect(CompassScore(hasLoggedToday: true, medsDone: 0, medsTotal: 0, hasPhotoThisWeek: false).score == 71)
        #expect(CompassScore(hasLoggedToday: true, medsDone: 2, medsTotal: 2, hasPhotoThisWeek: true).score == 100)
        #expect(CompassScore(hasLoggedToday: false, medsDone: 0, medsTotal: 2, hasPhotoThisWeek: false).score == 0)
    }
}
