//
//  AgentBridgeTests.swift
//  Hair Compass AI 5Tests
//
//  The pure parts of the agent bridge: how tool names become the "Read …" provenance line
//  under an answer, and how tool payloads are rendered for the output gate.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct AgentBridgeTests {

    /// Raw tool names are an implementation detail. Seeing "read_lab_results" in a chat would be
    /// a leak of how the thing is built into a screen about someone's hair.
    @Test func everyReadToolHasAHumanLabel() {
        for tool in ["recall_memory", "read_recent_entries", "read_lab_results",
                     "read_health_signals", "read_hair_science"] {
            let label = AgentBridge.sourceLabel(for: tool)
            #expect(label != nil, "\(tool) has no label and would vanish from the source line")
            #expect(label?.contains("_") == false, "\(tool)'s label still looks like a tool name")
        }
    }

    /// A write is not a source. Listing `log_entry` under "Read …" would tell the person the
    /// answer was read from a change it had just made — a plain misdescription of what happened.
    @Test func aWriteIsNeverListedAsASource() {
        #expect(AgentBridge.sourceLabel(for: "log_entry") == nil)
    }

    /// An unknown tool is dropped rather than shown raw: a server that adds a tool this build
    /// doesn't know should not put its identifier on screen.
    @Test func anUnknownToolIsDroppedRatherThanShownRaw() {
        #expect(AgentBridge.sourceLabel(for: "read_something_new") == nil)
    }

    /// The gate compares the answer's numbers against these facts, so the rendering has to match
    /// what the model was shown. `JSONSerialization` writes the Double 7.4 as
    /// `7.400000000000000355`; the model, fed the same value through the server, reads `7.4` and
    /// writes `7.4`. Held apart, a correct answer gets replaced by the "couldn't safely
    /// summarize" text — which looks like a safety failure and is really number formatting.
    @Test func factsRenderNumbersTheWayTheModelReadsThem() async {
        let recorder = ToolFactRecorder()
        await recorder.record("read_health_signals", payload: ["sleep_hours_avg": 7.4, "days": 30])
        let facts = await recorder.joined()

        #expect(facts.contains("7.4"))
        #expect(!facts.contains("7.400000"), "full float precision leaked into the fact set")
        // Whole numbers must not arrive as "30.0" either — the model writes "30".
        #expect(facts.contains("30") && !facts.contains("30.0"))
    }

    /// `NSNumber` boxes Bool alongside the numeric types. Rendering `true` as `1` would slip a
    /// number into the fact set that the model never saw, quietly widening what the gate allows.
    @Test func booleansAreNotRenderedAsNumbers() async {
        let recorder = ToolFactRecorder()
        await recorder.record("read_health_signals", payload: ["available": true])
        let facts = await recorder.joined()

        #expect(facts.contains("true"))
        #expect(!facts.contains("1"))
    }

    /// A schedule stored as "21:00" is written by a model as "9pm" — correct, and helpful. But
    /// then "9" is in the prose while only "21" is in the facts, and `AIOutputValidator` throws
    /// the whole answer away as containing an invented number. Both readings must be published.
    @Test func scheduleIsPublishedInBothClockForms() {
        #expect(AgentToolExecutor.twelveHour("08:00,21:00") == "8am, 9pm")
        #expect(AgentToolExecutor.twelveHour("00:00") == "12am")
        #expect(AgentToolExecutor.twelveHour("12:00") == "12pm")
        #expect(AgentToolExecutor.twelveHour("07:30") == "7:30am")
        #expect(AgentToolExecutor.twelveHour("") == "")
    }

    /// One tool used twice in a turn is still one source; a repeated name reads as a stutter.
    @Test func aToolUsedTwiceIsListedOnce() async {
        let recorder = ToolFactRecorder()
        await recorder.record("read_recent_entries", payload: ["days": 30])
        await recorder.record("read_recent_entries", payload: ["days": 14])
        #expect(await recorder.tools() == ["read_recent_entries"])
    }
}
