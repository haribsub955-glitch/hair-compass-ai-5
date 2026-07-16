import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One turn of the hair-science chat. Text only — photos never enter this feature.
struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// Pure prompt/plumbing builders for the chat — no networking, no state, fully testable.
/// THE SCOPE RESTRICTION LIVES IN `system(contextJSON:focus:)`: the model may only discuss
/// hair science and the person's own tracking record, and must deflect everything else.
enum HairChatPrompt {

    /// How many recent turns ride along with each request.
    static let historyLimit = 12

    /// The gentle in-chat line shown when the model declines a request — a conversational
    /// redirect, never an error banner.
    static let refusalReply = "I can't help with that one — ask me about your hair data."

    /// The top-level `system` field for every chat request. Scope restriction, honesty rules,
    /// the on-screen focus line, and the canonical `AIContext` JSON all live here.
    static func system(contextJSON: String, focus: String) -> String {
        """
        You are a careful hair-science explainer inside a personal hair-tracking app. The person is looking at charts of their own tracking data and wants to understand them.

        Scope — the only topics you discuss: hair biology and the hair growth cycle, shedding, scalp health, hair treatments and their evidence, and the relationships in the person's own tracking data (the JSON record below). If you are asked about anything outside that scope — coding, news, medical questions beyond hair, or anything else — reply with one friendly sentence redirecting the conversation back to hair topics, and nothing more.

        Honesty rules:
        - This is record-keeping and education, never diagnosis. Never diagnose or name a condition the person didn't state themselves.
        - A treatment cannot be judged before its 24-week point; say so if asked to judge one earlier.
        - Correlation in the data is not causation. When explaining a relationship, call it a pattern worth watching, not proof — many things affect hair.
        - Never invent numbers that are not present in the JSON record. Absent fields were simply not tracked.

        On screen right now: \(focus)

        Keep answers short: 2–6 sentences, plain language, warm and precise.

        The person's tracking record (schemaVersion \(AIContext.currentSchemaVersion) of the app's AI context; dates are yyyy-MM-dd; all statistics are precomputed on-device):
        \(contextJSON)
        """
    }

    /// Three tappable starter questions for the empty chat — generic enough to always apply,
    /// with the last one keyed off the focus line when it mentions the lag control.
    static func starters(focus: String) -> [String] {
        let third = focus.localizedCaseInsensitiveContains("lag")
            ? "How do time lags work for hair?"
            : "What usually drives shedding changes?"
        return [
            "What could explain this relationship?",
            "Is this change meaningful, or just noise?",
            third,
        ]
    }

    /// The payload history: the last `limit` turns, then trimmed so the first message is a
    /// user turn (the Messages API requires conversations to open with the user).
    static func cappedHistory(_ messages: [ChatMessage], limit: Int = historyLimit) -> [ChatMessage] {
        var recent = Array(messages.suffix(limit))
        while let first = recent.first, first.role != .user { recent.removeFirst() }
        return recent
    }

    /// Map a finished response to the assistant text to append: a refusal becomes the gentle
    /// redirect line; anything else passes through unchanged.
    static func assistantReply(stopReason: String?, text: String) -> String {
        stopReason == "refusal" ? refusalReply : text
    }
}

/// The hair-science chat behind the Compare screen's "Ask AI" chip: a consent-gated Claude
/// Messages conversation over the canonical `AIContext` JSON. Text only — no photos, ever.
///
/// Mirrors `CloudAnalysisService`'s Fable specifics: raw HTTPS, no `thinking`/`temperature`
/// params (they 400), `stop_reason == "refusal"` checked before reading content, and a
/// server-side fallback to `claude-opus-4-8` requested via the beta header.
@MainActor
@Observable
final class HairChatService {
    private(set) var messages: [ChatMessage] = []
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True when chat can run at all: on-device (Apple Intelligence) OR a reachable cloud model
    /// (the owner's proxy in release, a dev key locally).
    var hasKey: Bool {
        if AIGateway.isConfigured { return true }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceChat.isAvailable { return true }
        #endif
        return false
    }

    struct ChatError: Error { let message: String }

    /// Append the user's message and ask the model for the next turn. `context` is the
    /// `AIContext.jsonString()` snapshot; `focus` is one line describing what's on screen.
    func send(_ text: String, context: String, focus: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }
        do {
            let reply = try await request(context: context, focus: focus)
            messages.append(ChatMessage(role: .assistant, text: reply))
        } catch let e as ChatError {
            errorMessage = e.message
        } catch {
            errorMessage = "Couldn't reach the chat service. Check your connection and try again."
        }
    }

    // MARK: - Request

    private func request(context: String, focus: String) async throws -> String {
        let system = HairChatPrompt.system(contextJSON: context, focus: focus)
        let turns = HairChatPrompt.cappedHistory(messages).map {
            (role: $0.role.rawValue, text: $0.text)
        }

        // On-device first — Apple Intelligence answers with NOTHING leaving the device, so it needs
        // no off-device consent, no key, and no proxy. Falls through to the cloud if it declines.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceChat.isAvailable {
            if let reply = await OnDeviceChat.reply(system: system, turns: turns), !reply.isEmpty {
                return reply
            }
        }
        #endif

        // Cloud fallback (devices without on-device AI). This DOES leave the device, so it needs
        // consent, and it goes through the proxy (release) or a dev key (local).
        guard AIConsent.isGranted(defaults) else {
            throw ChatError(message: "Chat is off: sending your tracking summary off-device needs your consent first. You can manage this in your profile's Privacy section.")
        }
        guard AIGateway.isConfigured else {
            throw ChatError(message: "Chat isn't available in this build.")
        }

        let body: [String: Any] = [
            "model": "claude-fable-5",
            "max_tokens": 700,
            "fallbacks": [["model": "claude-opus-4-8"]],
            "system": system,
            "messages": turns.map { ["role": $0.role, "content": $0.text] }
        ]

        let json: [String: Any]
        do {
            json = try await AIGateway.postMessages(body)
        } catch let e as AIGateway.GatewayError {
            throw ChatError(message: e.message)
        }

        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Fable can decline via safety classifiers — mapped to a gentle in-chat line, not an error.
        let reply = HairChatPrompt.assistantReply(stopReason: json["stop_reason"] as? String, text: text)
        guard !reply.isEmpty else {
            throw ChatError(message: "The reply came back empty. Please try again.")
        }
        return reply
    }
}

#if canImport(FoundationModels)
/// On-device chat via Apple's FoundationModels (Apple Intelligence). Everything stays on the
/// device — no network, no key, no off-device consent — so it's the preferred path when available.
/// Mirrors `OnDeviceInsight` in InsightEngine.swift.
@available(iOS 26.0, *)
enum OnDeviceChat {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Answer the latest turn on-device. `system` is the grounding/instructions; `turns` is the
    /// capped conversation (oldest→newest, ending on the user's message). Returns nil to let the
    /// caller fall back to the cloud — e.g. if the model is unavailable or the context is too large.
    static func reply(system: String, turns: [(role: String, text: String)]) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let rendered = turns
            .map { "\($0.role == "assistant" ? "Assistant" : "User"): \($0.text)" }
            .joined(separator: "\n\n")
        let session = LanguageModelSession(instructions: system)
        do {
            let response = try await session.respond(to: rendered + "\n\nAssistant:")
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
#endif
