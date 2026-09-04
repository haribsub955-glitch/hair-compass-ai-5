//
//  AgentSessionParsingTests.swift
//  Hair Compass AI 5Tests
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct AgentSessionParsingTests {
    private let payload: [String: Any] = [
        "session_token": "tok",
        "principal": ["principal_id": "p_1", "entitlement": "pro", "plan_id": "trial"],
        "upgrade": "current",
        "features": ["photo_analysis", "daily_grounding"],
        "offer": [
            "products": ["m", "y"],
            "default_product": "y",
            "trial_days": 3,
            "free_days": 3
        ],
        "tools": [["name": "read_treatments"], ["name": "log_entry"]]
    ]

    @Test func planFeaturesOfferAndToolsArePreserved() throws {
        let session = try AgentClient.parseSession(payload)
        #expect(session.token == "tok")
        #expect(session.planID == "trial")
        #expect(session.features == ["photo_analysis", "daily_grounding"])
        #expect(session.tools == ["read_treatments", "log_entry"])
        let offer = try #require(session.offerJSON)
        let decoded = try #require(try JSONSerialization.jsonObject(with: offer) as? [String: Any])
        #expect(decoded["default_product"] as? String == "y")
    }

    @Test func optionalFieldsDefaultWithoutInventingCapability() throws {
        let session = try AgentClient.parseSession(["session_token": "tok"])
        #expect(session.planID == "free")
        #expect(session.entitlement == "free")
        #expect(session.features.isEmpty)
        #expect(session.offerJSON == nil)
        #expect(session.tools.isEmpty)
        #expect(throws: AgentClient.AgentError.self) {
            try AgentClient.parseSession([:])
        }
    }
}
