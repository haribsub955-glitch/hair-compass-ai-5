//
//  HairChatTests.swift
//  Hair Compass AI 5Tests
//
//  The hair-science chat's pure logic (HairChatService.swift): the system prompt that
//  restricts the model to hair topics, the starter chips, history capping, and the
//  refusal → gentle-redirect mapping. No networking is exercised here.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct HairChatTests {

    private let contextJSON = #"{"meta":{"entryCount":12},"schemaVersion":1}"#
    private let focus = "User is currently comparing: Shedding (hair fall) vs Sleep quality (lifestyle), 3M window, no time lag."

    // MARK: System prompt — the restriction lives here

    @Test func systemPromptRestrictsScopeToHair() {
        let prompt = HairChatPrompt.system(contextJSON: contextJSON, focus: focus)
        // The scope allowlist and the deflection instruction for everything else.
        #expect(prompt.contains("the only topics you discuss"))
        #expect(prompt.contains("hair biology"))
        #expect(prompt.contains("scalp health"))
        #expect(prompt.contains("reply with one friendly sentence redirecting the conversation back to hair topics, and nothing more"))
    }

    @Test func systemPromptCarriesHonestyRules() {
        let prompt = HairChatPrompt.system(contextJSON: contextJSON, focus: focus)
        #expect(prompt.contains("Never diagnose or name a condition"))
        #expect(prompt.contains("24-week"))
        #expect(prompt.contains("Correlation in the data is not causation"))
        #expect(prompt.contains("Never invent numbers"))
        #expect(prompt.contains("2–6 sentences"))
    }

    @Test func systemPromptEmbedsFocusAndContext() {
        let prompt = HairChatPrompt.system(contextJSON: contextJSON, focus: focus)
        #expect(prompt.contains(focus))
        #expect(prompt.contains(contextJSON))
        #expect(prompt.contains("schemaVersion \(AIContext.currentSchemaVersion)"))
    }

    // MARK: Starter chips

    @Test func startersAreThreeDistinctNonEmptyQuestions() {
        let starters = HairChatPrompt.starters(focus: focus)
        #expect(starters.count == 3)
        #expect(starters.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(Set(starters).count == 3)
    }

    @Test func startersHoldUpWithEmptyFocus() {
        let starters = HairChatPrompt.starters(focus: "")
        #expect(starters.count == 3)
        #expect(starters.allSatisfy { !$0.isEmpty })
        #expect(Set(starters).count == 3)
    }

    // MARK: Starter chips — full-record entry points (Today, deep-analysis follow-up)

    @Test func fullRecordStartersAreThreeDistinctNonEmptyQuestions() {
        let starters = HairChatPrompt.starters(
            focus: "User is asking from the Today screen about their overall record.", kind: .fullRecord)
        #expect(starters.count == 3)
        #expect(starters.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(Set(starters).count == 3)
    }

    @Test func fullRecordStartersDontPresupposeATwoSignalRelationship() {
        // The chart-comparison starters assume a specific two-signal relationship is on screen —
        // not true from Today or a deep-analysis follow-up, so the full-record set must not echo them.
        let starters = HairChatPrompt.starters(focus: "irrelevant", kind: .fullRecord)
        #expect(!starters.contains("What could explain this relationship?"))
        #expect(!starters.contains("Is this change meaningful, or just noise?"))
    }

    // MARK: History capping

    private func makeAlternatingHistory(count: Int) -> [ChatMessage] {
        (0..<count).map { i in
            ChatMessage(role: i.isMultiple(of: 2) ? .user : .assistant, text: "turn \(i)")
        }
    }

    @Test func cappedHistoryKeepsTheMostRecentTurns() {
        // 21 alternating turns ending on the just-appended user message.
        let history = makeAlternatingHistory(count: 21)
        let capped = HairChatPrompt.cappedHistory(history)
        #expect(capped.count <= HairChatPrompt.historyLimit)
        #expect(capped.last == history.last)
        // The oldest turns fell off the front; the kept ones are a contiguous suffix.
        #expect(capped == Array(history.suffix(capped.count)))
    }

    @Test func cappedHistoryOpensOnAUserTurn() {
        // suffix(12) of a 21-turn alternating list would start on an assistant turn —
        // the cap must trim it so the Messages API payload opens with the user.
        let history = makeAlternatingHistory(count: 21)
        let capped = HairChatPrompt.cappedHistory(history)
        #expect(capped.first?.role == .user)
    }

    @Test func shortHistoryPassesThroughUnchanged() {
        let history = makeAlternatingHistory(count: 5)
        #expect(HairChatPrompt.cappedHistory(history) == history)
    }

    // MARK: Refusal mapping

    @Test func refusalMapsToGentleRedirect() {
        let reply = HairChatPrompt.assistantReply(stopReason: "refusal", text: "ignored")
        #expect(reply == HairChatPrompt.refusalReply)
        #expect(reply.contains("hair"))
    }

    @Test func normalStopReasonPassesTextThrough() {
        #expect(HairChatPrompt.assistantReply(stopReason: "end_turn", text: "Shedding rises with stress.") == "Shedding rises with stress.")
        #expect(HairChatPrompt.assistantReply(stopReason: nil, text: "Hello") == "Hello")
    }
}
