import Foundation

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

    /// True when an API key is configured (env var → UserDefaults; never committed to the repo).
    var hasKey: Bool { AIConfig.claudeKey?.isEmpty == false }

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
        // Belt and braces: no code path may send data off-device without explicit consent.
        // The UI gates the entry point; this is the last line of defense.
        guard AIConsent.isGranted(defaults) else {
            throw ChatError(message: "Chat is off: sending your tracking summary off-device needs your consent first. You can manage this in your profile's Privacy section.")
        }
        guard let key = AIConfig.claudeKey, !key.isEmpty else {
            throw ChatError(message: "No API key configured. Chat needs a Claude API key (set it in the run scheme).")
        }

        let history = HairChatPrompt.cappedHistory(messages).map {
            ["role": $0.role.rawValue, "content": $0.text]
        }
        let body: [String: Any] = [
            "model": "claude-fable-5",
            "max_tokens": 700,
            "fallbacks": [["model": "claude-opus-4-8"]],
            "system": HairChatPrompt.system(contextJSON: context, focus: focus),
            "messages": history
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-06-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ChatError(message: "Unexpected response from the chat service.")
        }
        guard (200...299).contains(http.statusCode) else {
            let apiMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
            throw ChatError(message: apiMessage ?? "Chat failed (HTTP \(http.statusCode)).")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatError(message: "Couldn't read the chat response.")
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
