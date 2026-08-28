import Foundation
import OSLog
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What the agent path needs that the on-device path doesn't: a live `ModelContext` (its tools
/// read the record straight from SwiftData) and the conversation's identity (so session-scoped
/// memories stay inside the conversation that wrote them).
///
/// Deliberately NOT `#if DEBUG` even though only the DEBUG-only agent path reads it: it appears
/// in `send`'s signature, so Release must still be able to compile the type. The privacy promise
/// is carried by `AgentBridge` (fully DEBUG-gated) — in Release this struct is accepted and
/// ignored, and no agent code exists to receive it.
@MainActor
struct AgentChatContext {
    let modelContext: ModelContext
    let sessionID: String
}

/// One turn of the hair-science chat. Text only — photos never enter this feature.
struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    /// What this answer was read from, in the person's own vocabulary — "your recent entries",
    /// "the evidence library". Empty for the on-device path, which is handed one prebuilt
    /// context rather than choosing what to look at.
    ///
    /// This is the app's central claim made checkable. "Grounded in your own numbers, never a
    /// diagnosis" is on the paywall; an answer that shows which numbers it actually opened is
    /// the difference between saying that and demonstrating it.
    let sources: [String]

    init(id: UUID = UUID(), role: Role, text: String, sources: [String] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.sources = sources
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
        You are a careful hair-science explainer inside a personal hair-tracking app. The person is looking at their own tracking data — sometimes a specific chart, sometimes their whole record — and wants to understand it.

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

    /// Which entry point opened the chat — shapes which starter questions read naturally.
    /// `chartComparison`: opened over a specific two-signal chart (Compare). `fullRecord`:
    /// opened over the whole tracking record with no single chart on screen (Today, deep
    /// analysis follow-up).
    enum StarterKind { case chartComparison, fullRecord }

    /// Three tappable starter questions for the empty chat, shaped by where the chat was
    /// opened from. For a chart comparison, the last one is keyed off the focus line when it
    /// mentions the lag control; for the full record, the starters stay general instead of
    /// presupposing a two-signal relationship that isn't on screen.
    static func starters(focus: String, kind: StarterKind = .chartComparison) -> [String] {
        switch kind {
        case .chartComparison:
            let third = focus.localizedCaseInsensitiveContains("lag")
                ? "How do time lags work for hair?"
                : "What usually drives shedding changes?"
            return [
                "What could explain this relationship?",
                "Is this change meaningful, or just noise?",
                third,
            ]
        case .fullRecord:
            return [
                "What patterns stand out in my record?",
                "What should I keep an eye on?",
                "What usually drives shedding changes?",
            ]
        }
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

/// The hair-science chat behind the Compare screen's "Ask AI" chip: an on-device conversation
/// (Apple Intelligence) over the canonical `AIContext` JSON. Text only — no photos, ever — and
/// nothing leaves the device: no key, no proxy, no consent. Unavailable (with a clear message)
/// on hardware without Apple Intelligence; there is no cloud fallback.
@MainActor
@Observable
final class HairChatService {
    private(set) var messages: [ChatMessage] = []
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    /// The assistant's reply as it streams in token-by-token, cumulative from an empty string.
    /// Nil until the first token of a turn arrives, and cleared back to nil once the finished
    /// reply lands in `messages` — the UI shows this in place of the thinking dots.
    private(set) var streamingText: String?
    /// What the agent is *doing*, as opposed to what it is saying — "Reading your record…" while
    /// a tool wave runs on the device. Kept separate from `streamingText` because they are
    /// different kinds of thing: streaming text is Wren's answer arriving, this is machinery.
    /// Rendering activity in a message bubble reads as Wren having said it, which is a lie.
    private(set) var activityNote: String?
    /// Carries the just-finished turn's sources from `request` to the message it belongs to.
    /// `request` returns only text, and widening its return type to thread this through would
    /// complicate the on-device path, which has no sources to report.
    private var lastSources: [String] = []

    init() {}

    /// The specific reason on-device chat is (or isn't) usable right now — see
    /// `OnDeviceAvailability` in OnDeviceAnalysisService.swift. Read fresh each access, since
    /// Apple Intelligence can be enabled/disabled or finish downloading while the app is open.
    var availability: OnDeviceAvailability { OnDeviceAvailability.current }

    /// True when chat can run on this device — Apple Intelligence is available. There is no cloud
    /// fallback, so this is false on hardware without on-device AI, and the UI shows a clear card
    /// (see `availability` for exactly which of the three reasons applies).
    var isAvailable: Bool {
        #if DEBUG
        // The agent runs on a server, so Apple Intelligence availability says nothing about
        // whether chat can work. Without this the sheet shows its "needs Apple Intelligence"
        // card and never reaches the agent at all.
        if AgentBridge.isEnabled { return true }
        #endif
        return availability.isAvailable
    }

    struct ChatError: Error { let message: String }

    #if DEBUG
    /// One honest line per agent failure — never a transport detail or a server message.
    static func message(for error: AgentClient.AgentError) -> String {
        switch error {
        case .transport:
            return "Couldn't reach the agent server. Is it running on port 8100?"
        case .unauthenticated:
            return "The agent session expired. Close and reopen this chat."
        case .upgradeRequired:
            return "This build is too old for that agent server."
        case .badResponse(let status):
            return "The agent server returned \(status)."
        }
    }
    #endif

    /// Append the user's message and ask the model for the next turn. `context` is the
    /// `AIContext.jsonString()` snapshot; `focus` is one line describing what's on screen.
    ///
    /// `agentContext` opts this turn into the agent platform (DEBUG + `HC_AGENT` only — see
    /// `AgentBridge`). The agent doesn't take the prebuilt `AIContext`: it asks the device for
    /// what it needs through tools, so the record is read on demand rather than sent wholesale.
    func send(
        _ text: String,
        context: String,
        focus: String,
        agentContext: AgentChatContext? = nil
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        isRunning = true
        errorMessage = nil
        streamingText = nil
        defer { isRunning = false; streamingText = nil; activityNote = nil }
        do {
            let reply = try await request(context: context, focus: focus, agentContext: agentContext)
            messages.append(ChatMessage(role: .assistant, text: reply, sources: lastSources))
            lastSources = []
        } catch let e as ChatError {
            errorMessage = e.message
        } catch {
            errorMessage = "Couldn't generate a reply on this device. Try again."
        }
    }

    // MARK: - Request

    private func request(
        context: String,
        focus: String,
        agentContext: AgentChatContext? = nil
    ) async throws -> String {
        #if DEBUG
        // Ahead of everything else: when the agent is driving, the on-device model is not
        // involved at all — this is a different system, not a fallback for the same one.
        if AgentBridge.isEnabled, let agentContext {
            let question = messages.last(where: { $0.role == .user })?.text ?? ""
            do {
                let turn = try await AgentBridge.run(
                    userText: question,
                    context: agentContext.modelContext,
                    sessionID: agentContext.sessionID,
                    onProgress: { [weak self] line in self?.activityNote = line }
                )
                // `served: false` arrives as nil and is explicitly not an error — the safety
                // layer stripped it or the loop stopped on something it couldn't verify.
                guard let reply = turn.answer, !reply.isEmpty else {
                    throw ChatError(message: "The agent didn't return an answer for that one. Try rephrasing.")
                }
                // Same deterministic gate the on-device path passes through — a remote model is
                // not more trusted than a local one; if anything it is less. Validated against
                // the tool payloads *as well as* the context: the agent's numbers come from the
                // tools, and a gate that can't see them rejects correct answers.
                lastSources = turn.toolsUsed.compactMap(AgentBridge.sourceLabel(for:))
                let facts = context + " " + turn.facts
                #if DEBUG
                if !AIOutputValidator.isSafe(reply, suppliedFacts: facts) {
                    // Name the ungrounded numbers directly. "The gate said no" is not a
                    // diagnosis; "the answer says 9 and the facts never do" is one.
                    let canonical: (String) -> String = { raw in
                        Double(raw).map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? raw
                    }
                    let inFacts = Set(facts.matches(of: /\b\d+(?:\.\d+)?\b/).map { canonical(String($0.output)) })
                    let ungrounded = reply.matches(of: /\b\d+(?:\.\d+)?\b/)
                        .map { canonical(String($0.output)) }
                        .filter { $0 != "24" && !inFacts.contains($0) }
                    Logger(subsystem: "harib.Hair-Compass-AI-5", category: "agent")
                        .error("GATE_REJECTED ungrounded=\(Set(ungrounded).sorted(), privacy: .public) answer=\(reply, privacy: .public)")
                }
                #endif
                return AIOutputValidator.safeText(reply, suppliedFacts: facts)
            } catch let error as AgentClient.AgentError {
                throw ChatError(message: Self.message(for: error))
            }
        }
        #endif
        let system = HairChatPrompt.system(contextJSON: context, focus: focus)
        let turns = HairChatPrompt.cappedHistory(messages).map {
            (role: $0.role.rawValue, text: $0.text)
        }

        // On-device only — Apple Intelligence answers with NOTHING leaving the device, so it needs
        // no consent, no key, and no proxy. There is no cloud fallback: hardware without on-device
        // AI gets a clear, reason-specific message instead (the UI also gates on `isAvailable` up
        // front, via `availability`).
        let status = availability
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), status.isAvailable {
            if let reply = await OnDeviceChat.reply(
                system: system, turns: turns,
                // Generated prose is not shown before the deterministic post-generation gate.
                onPartial: { _ in }
            ), !reply.isEmpty {
                return AIOutputValidator.safeText(reply, suppliedFacts: context)
            }
            throw ChatError(message: "Couldn't get a reply. Please try again.")
        }
        #endif

        throw ChatError(message: status.message)
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

    /// Answer the latest turn on-device, streaming as it generates. `system` is the
    /// grounding/instructions; `turns` is the capped conversation (oldest→newest, ending on the
    /// user's message). `onPartial` fires on the main actor with the cumulative text so far after
    /// every new snapshot, so the UI can show the reply as it's written instead of a blind wait.
    /// Returns nil when the model is unavailable or the request fails, so the caller can surface
    /// a clear message.
    static func reply(
        system: String,
        turns: [(role: String, text: String)],
        onPartial: @MainActor (String) -> Void = { _ in }
    ) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let rendered = turns
            .map { "\($0.role == "assistant" ? "Assistant" : "User"): \($0.text)" }
            .joined(separator: "\n\n")
        let session = LanguageModelSession(instructions: system)
        do {
            let stream = session.streamResponse(to: rendered + "\n\nAssistant:")
            var latest = ""
            for try await snapshot in stream {
                latest = snapshot.content
                let trimmed = latest.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { await onPartial(trimmed) }
            }
            let text = latest.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
#endif
