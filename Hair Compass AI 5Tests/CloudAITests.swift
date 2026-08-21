//
//  CloudAITests.swift
//  Hair Compass AI 5Tests
//
//  The cloud engine's pure parts: configuration resolution, the wire request we actually send,
//  and response parsing. No test here makes a network call.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct CloudAIConfigTests {

    /// The happy path: the xcconfig-fed Info.plist value becomes the key, defaults fill in the
    /// endpoint and model.
    @Test func plistKeyConfiguresTheDefaultEndpoint() {
        let config = CloudAIConfig.resolve(infoPlistKey: "sk-test-123")
        #expect(config.isConfigured)
        #expect(config.apiKey == "sk-test-123")
        #expect(config.baseURLString == "https://api.deepseek.com/v1")
        #expect(config.model == "deepseek-chat")
        #expect(config.chatCompletionsURL?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
    }

    /// A build without `Config/Secrets.local.xcconfig` ships the *unexpanded* `$(…)` literal in
    /// Info.plist. That must read as "no key" — treating it as a key would send a garbage
    /// Authorization header instead of falling back to on-device.
    @Test func missingSecretsFileReadsAsNotConfigured() {
        #expect(CloudAIConfig.resolve(infoPlistKey: nil).isConfigured == false)
        #expect(CloudAIConfig.resolve(infoPlistKey: "").isConfigured == false)
        #expect(CloudAIConfig.resolve(infoPlistKey: "$(HC_DEEPSEEK_API_KEY)").isConfigured == false)
        #expect(CloudAIConfig.resolve(infoPlistKey: "  ").isConfigured == false)
    }

    /// The QA escape hatches (DEBUG-only, which is what the test host runs): env overrides for
    /// key/endpoint/model, and `HC_AI_CLOUD_OFF` to force the no-cloud build's behaviour on a
    /// machine whose build embeds the real key.
    @Test func debugOverridesWinAndCloudOffForcesUnconfigured() {
        let overridden = CloudAIConfig.resolve(
            infoPlistKey: "sk-plist",
            environment: ["HC_AI_KEY": "sk-env", "HC_AI_BASE_URL": "https://proxy.example.com/v1", "HC_AI_MODEL": "deepseek-reasoner"]
        )
        #expect(overridden.apiKey == "sk-env")
        #expect(overridden.baseURLString == "https://proxy.example.com/v1")
        #expect(overridden.model == "deepseek-reasoner")

        let off = CloudAIConfig.resolve(infoPlistKey: "sk-plist", arguments: ["HC_AI_CLOUD_OFF"])
        #expect(off.isConfigured == false)
    }

    /// The endpoint must be HTTPS — a misconfigured plain-HTTP base URL silently disables the
    /// cloud rather than sending health data in the clear.
    @Test func plainHTTPBaseURLIsRejected() {
        var config = CloudAIConfig.resolve(infoPlistKey: "sk-test")
        config.baseURLString = "http://api.deepseek.com/v1"
        #expect(config.isConfigured == false)
        #expect(config.chatCompletionsURL == nil)
    }
}

struct CloudAIRequestTests {

    private let config = CloudAIConfig(
        baseURLString: "https://api.deepseek.com/v1", model: "deepseek-chat", apiKey: "sk-test")

    /// The exact wire shape DeepSeek's OpenAI-compatible endpoint expects: system first, the
    /// conversation in order, roles mapped, streaming off (the validator gates full replies —
    /// partial prose is never shown, so there is nothing to stream to).
    @Test func requestBodyPutsSystemFirstAndKeepsTurnOrder() {
        let body = CloudAI.requestBody(
            system: "You are a careful explainer.",
            turns: [
                CloudAI.Turn(role: "user", text: "first question"),
                CloudAI.Turn(role: "assistant", text: "first answer"),
                CloudAI.Turn(role: "user", text: "second question"),
            ],
            config: config,
            maxTokens: 500
        )
        #expect(body.model == "deepseek-chat")
        #expect(body.stream == false)
        #expect(body.maxTokens == 500)
        #expect(body.messages.map(\.role) == ["system", "user", "assistant", "user"])
        #expect(body.messages.first?.content == "You are a careful explainer.")
        #expect(body.messages.last?.content == "second question")
    }

    /// Unknown roles never reach the wire — anything that isn't the assistant is sent as the
    /// user, matching how the on-device path renders the same turns.
    @Test func unknownRolesAreSentAsUser() {
        let body = CloudAI.requestBody(
            system: "s", turns: [CloudAI.Turn(role: "tool", text: "x")], config: config, maxTokens: 100)
        #expect(body.messages.map(\.role) == ["system", "user"])
    }

    /// `max_tokens` is the field DeepSeek reads; an encoder that wrote `maxTokens` would
    /// silently fall back to the server default and truncate nothing — until it truncated
    /// everything. Pin the JSON.
    @Test func maxTokensEncodesSnakeCased() throws {
        let body = CloudAI.requestBody(system: "s", turns: [], config: config, maxTokens: 321)
        let json = String(data: try JSONEncoder().encode(body), encoding: .utf8) ?? ""
        #expect(json.contains("\"max_tokens\":321"))
        #expect(!json.contains("maxTokens"))
    }

    @Test func replyTextReadsTheFirstChoiceAndTrims() {
        let payload = #"{"choices":[{"message":{"role":"assistant","content":"  An answer.  "}}]}"#
        #expect(CloudAI.replyText(from: Data(payload.utf8)) == "An answer.")

        #expect(CloudAI.replyText(from: Data(#"{"choices":[]}"#.utf8)) == nil)
        #expect(CloudAI.replyText(from: Data("not json".utf8)) == nil)
        #expect(CloudAI.replyText(from: Data(#"{"error":{"message":"x"}}"#.utf8)) == nil)
    }
}
