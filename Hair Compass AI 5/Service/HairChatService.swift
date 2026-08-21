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
    /// user turn — every chat/completions-style API this app talks to (DeepSeek included)
    /// requires a conversation to open with the user, not just Anthropic's Messages API.
    static func cappedHistory(_ messages: [ChatMessage], limit: Int = historyLimit) -> [ChatMessage] {
        var recent = Array(messages.suffix(limit))
        while let first = recent.first, first.role != .user { recent.removeFirst() }
        return recent
    }

    /// The fact set a reply is actually checked against — deliberately NOT the full `system`
    /// prompt. `system` also carries instruction boilerplate (the "2–6 sentences" length rule,
    /// the schema-version note) that reads as a plausible "fact" to `AIOutputValidator`'s
    /// numeric/term checks but isn't one — validating against it let a reply admit a number
    /// that only ever appeared in the app's own instructions. Built from exactly what grounds
    /// an honest answer instead: the on-screen focus line (can legitimately contain tokens
    /// like "3M"/"2wk"), the context JSON, and every turn actually sent — the last of those so
    /// an assistant reply that echoes a number the *person* just typed ("week 30 isn't in your
    /// record") isn't falsely rejected as invented just because it lives only in the
    /// conversation, not the record.
    static func validationFacts(contextJSON: String, focus: String, turns: [CloudAI.Turn]) -> String {
        ([focus, contextJSON] + turns.map(\.text)).joined(separator: "\n")
    }

    /// Map a finished response to the assistant text to append: a refusal becomes the gentle
    /// redirect line; anything else passes through unchanged.
    static func assistantReply(stopReason: String?, text: String) -> String {
        stopReason == "refusal" ? refusalReply : text
    }
}

/// The hair-science chat behind the Compare screen's "Ask AI" chip, over the canonical
/// `AIContext` JSON. Text only — no photos, ever.
///
/// Engine order (see `AIEngine`): the cloud model (DeepSeek) leads whenever it is configured
/// and the person has consented — it answers on every iPhone, not just Apple-Intelligence
/// hardware. The on-device model is the no-consent path and the offline fallback. Every reply,
/// from either engine, passes the same deterministic `AIOutputValidator` gate before the UI
/// shows it.
@MainActor
@Observable
final class HairChatService {
    private(set) var messages: [ChatMessage] = []
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    /// The currently in-flight turn, if any — held so `cancel()` can stop it (and the billed
    /// cloud request underneath it) when the chat sheet is dismissed mid-reply.
    private var currentTask: (any CancellableTask)?

    init() {}

    /// Cancels the in-flight turn, if any. Cooperative: `URLSession.data(for:)` observes Swift
    /// Concurrency cancellation and tears down the underlying network task when its enclosing
    /// `Task` is cancelled, so this actually stops a billed cloud call in flight rather than
    /// just abandoning the awaiting call site.
    func cancel() {
        currentTask?.cancel()
        // Nothing is still in flight for this handle once cancel() has been asked for it —
        // nil it out so a later `cancel()` (or a stray read) can't act on a stale, already-
        // dead task.
        currentTask = nil
    }

    /// The specific reason on-device chat is (or isn't) usable right now — see
    /// `OnDeviceAvailability` in OnDeviceAnalysisService.swift. Read fresh each access, since
    /// Apple Intelligence can be enabled/disabled or finish downloading while the app is open.
    var availability: OnDeviceAvailability { OnDeviceAvailability.current }

    /// Which engine a message would use right now — cloud, on-device, a pending consent
    /// question, or nothing. Read fresh each access: consent can be granted or revoked, and
    /// Apple Intelligence toggled, while the sheet is open.
    var engine: AIEngine { AIEngine.current }

    /// True when a message can actually be answered right now (cloud or on-device). False while
    /// the consent question is still open and when neither engine exists — the UI shows the
    /// consent card or a clear notice instead of the input bar.
    var isAvailable: Bool { engine.canRun }

    struct ChatError: Error { let message: String }

    /// Append the user's message and ask the model for the next turn. `context` is the
    /// `AIContext.jsonString()` snapshot; `focus` is one line describing what's on screen.
    func send(_ text: String, context: String, focus: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // `!isRunning` also guards against a double-tap firing a second billed cloud call
        // while the first turn is still in flight — and the guard and the flag it guards have
        // to happen together, synchronously, right here: setting `isRunning` from inside the
        // enqueued Task body left a window where two rapid taps could both pass the guard
        // before either body had actually run (reproduced: two billed calls).
        guard !trimmed.isEmpty, !isRunning else { return }
        isRunning = true
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: trimmed))
        let task = Task { [weak self] in
            guard let self else { return }
            // Also clears `currentTask`: a stale handle left behind after this Task finishes
            // could otherwise be cancelled or read by a later, unrelated turn.
            defer { self.isRunning = false; self.currentTask = nil }
            do {
                let reply = try await self.request(context: context, focus: focus)
                self.messages.append(ChatMessage(role: .assistant, text: reply))
            } catch is CancellationError {
                // The sheet is gone — nothing to show, and no fallback: cancellation means
                // the person no longer wants an answer, not that the turn failed.
            } catch let e as ChatError {
                self.errorMessage = e.message
            } catch {
                self.errorMessage = "Couldn't generate a reply. Try again."
            }
        }
        currentTask = task
        await task.value
    }

    // MARK: - Request

    private func request(context: String, focus: String) async throws -> String {
        let system = HairChatPrompt.system(contextJSON: context, focus: focus)
        let turns = HairChatPrompt.cappedHistory(messages).map {
            CloudAI.Turn(role: $0.role.rawValue, text: $0.text)
        }
        // Deliberately not the full `system` string — see `HairChatPrompt.validationFacts`'s
        // doc comment for why the instruction boilerplate in `system` doesn't belong in the
        // fact set, and why every turn actually sent (not just the record) has to be in it.
        let facts = HairChatPrompt.validationFacts(contextJSON: context, focus: focus, turns: turns)

        switch engine {
        case .cloud:
            do {
                let reply = try await CloudAI.reply(system: system, turns: turns, maxTokens: 500)
                return AIOutputValidator.safeText(reply, suppliedFacts: facts)
            } catch let cloudError as CloudAI.ServiceError {
                // A failed cloud turn falls back to the on-device model when this hardware has
                // one; otherwise the honest transport error surfaces as this turn's reply.
                guard OnDeviceAvailability.current.isAvailable else {
                    throw ChatError(message: cloudError.message)
                }
                // A cancellation landing in the gap between the cloud call failing and the
                // fallback starting (the sheet dismissed right as the cloud turn errored out)
                // must not kick off a second, on-device turn nobody is waiting for anymore.
                try Task.checkCancellation()
                do {
                    return try await onDeviceReply(system: system, turns: turns, facts: facts)
                } catch {
                    // Both engines failed. A network-caused cloud failure ("check your
                    // connection") is more actionable than the on-device fallback's generic
                    // "couldn't get a reply" — don't let the latter mask the real cause.
                    if cloudError.isNetwork { throw ChatError(message: cloudError.message) }
                    throw error
                }
            }
        case .onDevice:
            return try await onDeviceReply(system: system, turns: turns, facts: facts)
        case .needsCloudConsent:
            // The sheet gates the input bar behind the consent card, so a send in this state is
            // a logic error — answer it with the honest next step rather than trapping.
            throw ChatError(message: "Choose whether to use cloud AI first.")
        case .unavailable(let message):
            throw ChatError(message: message)
        }
    }

    private func onDeviceReply(system: String, turns: [CloudAI.Turn], facts: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceAvailability.current.isAvailable {
            // No `onPartial` passed: nothing reads partial prose (the deterministic
            // post-generation gate below is the sole publication boundary), so there's nothing
            // to feed it — `OnDeviceChat.reply` keeps its own no-op default for callers that
            // ever do want progress.
            if let reply = await OnDeviceChat.reply(system: system, turns: turns.map { (role: $0.role, text: $0.text) }),
               !reply.isEmpty {
                // Same `facts` validation as the cloud path just above.
                return AIOutputValidator.safeText(reply, suppliedFacts: facts)
            }
            // A cancelled generation (the sheet dismissed mid-run) surfaces here as the same
            // nil/empty result as a genuine on-device failure — check cancellation first so a
            // walked-away person gets silence (the `catch is CancellationError` in `send`
            // above), not an error card for a turn they didn't actually ask to fail.
            if Task.isCancelled { throw CancellationError() }
            throw ChatError(message: "Couldn't get a reply. Please try again.")
        }
        #endif
        throw ChatError(message: OnDeviceAvailability.current.message)
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
    /// capped conversation (oldest→newest, ending on the user's message). The underlying
    /// session always streams internally, and `onPartial`, if a caller supplies one, fires on
    /// the main actor with the cumulative text after every new snapshot — but nothing in the
    /// app does today: generated prose is never shown before the deterministic post-generation
    /// gate, so `HairChatService` keeps the no-op default and reads only the return value.
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
