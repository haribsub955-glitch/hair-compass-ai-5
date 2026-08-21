//
//  CloudAILiveTests.swift
//  Hair Compass AI 5Tests
//
//  OPT-IN end-to-end proof that `CloudAI.reply` — the exact code path the app ships — completes
//  a real turn against the DeepSeek API. The normal suite never opts in: xcodebuild's
//  TEST_RUNNER_ environment does not reliably reach Swift Testing under parallel clones, so the
//  opt-in is a host file marker instead (the Simulator shares the host filesystem):
//
//    touch /tmp/hc-ai-live-test
//    xcodebuild test ... -only-testing:"Hair Compass AI 5Tests/CloudAILiveTests"
//    cat /tmp/hc-ai-live-test-reply   # the model's actual words — proof the pass wasn't vacuous
//    rm /tmp/hc-ai-live-test*
//
//  The key comes from the test host app's own Info.plist (`CloudAIConfig.current`), i.e. the
//  same build-time injection the shipping app uses. Without the marker file the test passes
//  vacuously and makes no network call.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct CloudAILiveTests {

    private static let markerPath = "/tmp/hc-ai-live-test"
    private static let replyPath = "/tmp/hc-ai-live-test-reply"

    @MainActor
    @Test func liveChatCompletionRoundTrip() async throws {
        guard FileManager.default.fileExists(atPath: Self.markerPath) else {
            return // Not opted in — the offline suite stays offline.
        }
        let config = CloudAIConfig.current
        #expect(config.isConfigured, "Live test opted in but the test host has no embedded key — is Config/Secrets.local.xcconfig present?")
        guard config.isConfigured else { return }

        let reply = try await CloudAI.reply(
            system: "You are a test probe. Reply with exactly the word: pong",
            turns: [CloudAI.Turn(role: "user", text: "ping")],
            maxTokens: 10,
            config: config
        )
        try? reply.write(toFile: Self.replyPath, atomically: true, encoding: .utf8)
        #expect(!reply.isEmpty)
        #expect(reply.lowercased().contains("pong"))
    }
}
