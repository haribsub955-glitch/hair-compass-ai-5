//
//  TodayPlanCopyTests.swift
//  Hair Compass AI 5Tests
//
//  The plan section's copy is data. Pinned so it stays record-keeping: no diagnosis words, no
//  directives, no exclamation marks, no shame vocabulary.
//

import Testing
@testable import Hair_Compass_AI_5

struct TodayPlanCopyTests {

    private var everyLine: [String] {
        [
            TodayPlanCopy.eyebrow, TodayPlanCopy.closureTitle, TodayPlanCopy.closureBody,
            TodayPlanCopy.quietTitle, TodayPlanCopy.quietBody, TodayPlanCopy.skippedLabel,
            TodayPlanCopy.undo, TodayPlanCopy.recordedLine(1), TodayPlanCopy.recordedLine(3),
            TodayPlanCopy.weekEyebrow, TodayPlanCopy.weekLine(completed: 6, expected: 7),
            TodayPlanCopy.weekEmpty, TodayPlanCopy.viewPlan,
            TodayPlanCopy.skipTitle, TodayPlanCopy.skipMessage,
            TodayPlanCopy.pauseTitle("Minoxidil"), TodayPlanCopy.pauseMessage, TodayPlanCopy.pauseAction
        ]
    }

    @Test func copyStaysRecordKeeping() {
        let banned = ["diagnos", "cure", "you have", "prescrib", "you should", "you must",
                      "failed", "poor", "non-compliant", "streak", "!"]
        for line in everyLine {
            let lower = line.lowercased()
            for word in banned {
                #expect(!lower.contains(word), "\(line) contains \(word)")
            }
        }
    }

    @Test func closureSaysNothingElseIsNeeded() {
        #expect(TodayPlanCopy.closureBody.lowercased().contains("nothing else"))
        #expect(TodayPlanCopy.recordedLine(1) == "1 action recorded")
        #expect(TodayPlanCopy.recordedLine(2) == "2 actions recorded")
        #expect(TodayPlanCopy.weekLine(completed: 6, expected: 7) == "6 of 7 planned actions")
    }
}
