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

    /// `deepseek-reasoner` (a supported `HC_AI_MODEL` override, not just the default
    /// `deepseek-chat`) 400s on a conversation that repeats a role two turns running. That
    /// shape happens for real: `HairChatService` leaves an unanswered user message in history
    /// after a failed turn, so the next `send` appends a second user turn right behind it —
    /// pin that `requestBody` folds the pair into one message instead of shipping
    /// `[system, ..., user, user]`.
    @Test func requestBodyFoldsConsecutiveSameRoleMessagesAfterAFailedTurn() {
        let body = CloudAI.requestBody(
            system: "s",
            turns: [
                CloudAI.Turn(role: "user", text: "first question"),
                CloudAI.Turn(role: "user", text: "second question, sent after the first turn failed"),
            ],
            config: config,
            maxTokens: 100
        )
        #expect(body.messages.map(\.role) == ["system", "user"])
        #expect(body.messages.last?.content == "first question\n\nsecond question, sent after the first turn failed")
    }

    /// A run of three-plus same-role messages folds into one, not a fold-then-refold artifact,
    /// and the join order is preserved.
    @Test func requestBodyFoldsLongerRunsOfTheSameRoleInOrder() {
        let body = CloudAI.requestBody(
            system: "s",
            turns: [
                CloudAI.Turn(role: "user", text: "a"),
                CloudAI.Turn(role: "user", text: "b"),
                CloudAI.Turn(role: "user", text: "c"),
            ],
            config: config,
            maxTokens: 100
        )
        #expect(body.messages.map(\.role) == ["system", "user"])
        #expect(body.messages.last?.content == "a\n\nb\n\nc")
    }
}

// MARK: - Cancellation

/// Fails every request immediately with `URLError.cancelled` — simulates a URLSession task
/// torn down mid-flight by Swift Concurrency cancellation (see the `CancellableTask` doc
/// comment in CloudAI.swift) without making any real network call.
private final class CancelledURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

/// `CloudAI.reply` used to consume a budget slot before any cancellation-aware suspension
/// point, and mapped a cancelled transport call to the offline `ServiceError` — which could
/// then trigger a pointless on-device fallback in the services for a request nobody is
/// waiting for anymore. Two distinct fixes, two distinct tests: a task already cancelled
/// before `reply` runs must never touch the budget at all, and a transport failure that's
/// actually a cancellation must surface as `CancellationError`, not `ServiceError`.
struct CloudAICancellationTests {
    private let config = CloudAIConfig(
        baseURLString: "https://api.deepseek.com/v1", model: "deepseek-chat", apiKey: "sk-test")

    private func makeDefaults() -> (UserDefaults, cleanup: () -> Void) {
        let suite = "cloudai-cancel-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func replyNeverTouchesTheBudgetWhenTheTaskIsAlreadyCancelled() async throws {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }

        let task = Task {
            try await CloudAI.reply(system: "s", turns: [], config: config, budgetDefaults: defaults)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        // A task cancelled before `reply` ever ran must not have spent a slot from the shared
        // daily ceiling on a call nobody is waiting for anymore.
        #expect(defaults.integer(forKey: CloudAIBudget.countDefaultsKey) == 0)
    }

    @Test func replyMapsATransportCancellationToCancellationErrorNotServiceError() async throws {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancelledURLProtocol.self]
        let session = URLSession(configuration: configuration)

        await #expect(throws: CancellationError.self) {
            _ = try await CloudAI.reply(system: "s", turns: [], config: config, session: session, budgetDefaults: defaults)
        }
        // Cancellation here happens mid-flight, after the budget slot was already spent —
        // the one case the pre-flight `Task.checkCancellation()` above can't (and shouldn't
        // try to) avoid.
        #expect(defaults.integer(forKey: CloudAIBudget.countDefaultsKey) == 1)
    }
}
