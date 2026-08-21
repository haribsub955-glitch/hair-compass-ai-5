import Foundation
import os

// MARK: - Configuration

/// Build-time configuration for the cloud AI. DeepSeek today — but only the URL, model and key
/// are configuration, so any OpenAI-compatible `/chat/completions` endpoint (a proxy in front
/// of DeepSeek included) is a one-line change here, not a rewrite.
///
/// The key travels: `Config/Secrets.local.xcconfig` (gitignored — this repo is public) →
/// `Config/AI.xcconfig` → the `HC_DEEPSEEK_API_KEY` build setting → Info.plist
/// (`HCDeepSeekAPIKey`) → `current`. A build without the secrets file resolves an empty key,
/// `isConfigured` reads false, and every AI feature falls back to the on-device model exactly
/// as it behaved before the cloud path existed.
///
/// `nonisolated`: pure value resolution over Bundle/ProcessInfo, with no actor affinity — and
/// it needs to be callable as a default-parameter value from the now-`nonisolated` `CloudAI`
/// client without forcing a MainActor hop just to read a URL string.
nonisolated struct CloudAIConfig: Equatable, Sendable {
    var baseURLString: String
    var model: String
    var apiKey: String

    static let defaultBaseURLString = "https://api.deepseek.com/v1"
    static let defaultModel = "deepseek-chat"

    /// Info.plist key whose value is `$(HC_DEEPSEEK_API_KEY)` — expanded at build time from
    /// `Config/AI.xcconfig`.
    static let infoPlistKeyName = "HCDeepSeekAPIKey"

    /// Whether the cloud path can be attempted at all. Requests can still fail (offline, the
    /// service down) — per-request errors are handled where they happen; this only says a key
    /// and a well-formed endpoint exist.
    var isConfigured: Bool { !apiKey.isEmpty && chatCompletionsURL != nil }

    var chatCompletionsURL: URL? {
        guard let base = URL(string: baseURLString), base.scheme == "https" else { return nil }
        return base.appending(path: "chat/completions")
    }

    static var current: CloudAIConfig {
        resolve(
            infoPlistKey: Bundle.main.object(forInfoDictionaryKey: infoPlistKeyName) as? String,
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    /// Pure resolution over explicit inputs so `CloudAITests` can cover every branch. The DEBUG
    /// overrides mirror the app's other `HC_*` QA flags and are compiled out of release.
    static func resolve(
        infoPlistKey: String?,
        environment: [String: String] = [:],
        arguments: [String] = []
    ) -> CloudAIConfig {
        var key = (infoPlistKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // A missing xcconfig leaves the literal, unexpanded "$(HC_DEEPSEEK_API_KEY)" in the
        // Info.plist value — that is "no key", never a key.
        if key.hasPrefix("$(") { key = "" }
        var base = defaultBaseURLString
        var model = defaultModel
        #if DEBUG
        if let k = environment["HC_AI_KEY"], !k.isEmpty { key = k }
        if let b = environment["HC_AI_BASE_URL"], !b.isEmpty { base = b }
        if let m = environment["HC_AI_MODEL"], !m.isEmpty { model = m }
        // Forces the no-cloud build for QA — the only way to see the on-device-only states on a
        // machine whose build embeds the real key.
        if arguments.contains("HC_AI_CLOUD_OFF") { key = "" }
        #endif
        return CloudAIConfig(baseURLString: base, model: model, apiKey: key)
    }
}

// MARK: - Consent

/// The person's standing answer to "may AI features send your tracking summary off this device?"
///
/// Absence of the key means undecided — the AI surfaces show a consent card before the first
/// cloud request and record the choice here. Deciding is never final: the Baseline screen keeps
/// a toggle (`CloudAISettingsSection`) that rewrites this at any time. The payload the consent
/// covers is the same `AIContext` JSON the on-device model already saw: numbers, dates and
/// logged notes — never the person's name, contact details, or photos (`AIContextBuilder`
/// structurally has no identifier or image fields).
enum CloudAIConsent {
    static let defaultsKey = "cloudAIConsentGranted"

    static func isDecided(_ defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        if forcedDecision() != nil { return true }
        #endif
        return defaults.object(forKey: defaultsKey) != nil
    }

    static func isGranted(_ defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        if let forced = forcedDecision() { return forced }
        #endif
        return defaults.bool(forKey: defaultsKey)
    }

    static func record(_ granted: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(granted, forKey: defaultsKey)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    #if DEBUG
    /// `HC_CLOUD_CONSENT granted | denied` — jumps QA and screenshot runs past the consent card.
    /// Same shape as `HC_TIER` / `HC_AI_STATUS`, and compiled out of release.
    static func forcedDecision(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool? {
        guard let i = arguments.firstIndex(of: "HC_CLOUD_CONSENT"), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "granted": return true
        case "denied": return false
        default: return nil
        }
    }
    #endif
}

// MARK: - Engine decision

/// Which engine an AI feature would use right now. One resolution shared by chat, deep analysis
/// and the ingredient reader, so the three surfaces can never disagree about what runs.
///
/// Cloud leads whenever it is configured: DeepSeek answers on every iPhone, which is the whole
/// reason the cloud path exists — the on-device model only runs on Apple-Intelligence hardware
/// and proved unreliable even there. On-device remains as the no-consent path and the offline
/// fallback; nothing here ever silently routes to the cloud before consent is recorded.
enum AIEngine: Equatable {
    /// DeepSeek over the network — configured, and consent granted.
    case cloud
    /// Apple Intelligence on this device — cloud unconfigured or declined.
    case onDevice
    /// Cloud could run but the person hasn't been asked yet. Surfaces show the consent card.
    case needsCloudConsent
    /// Nothing can run. Carries the user-facing explanation for the notice card.
    case unavailable(message: String)

    var canRun: Bool {
        switch self {
        case .cloud, .onDevice: true
        case .needsCloudConsent, .unavailable: false
        }
    }

    static var current: AIEngine {
        resolve(
            cloudConfigured: CloudAIConfig.current.isConfigured,
            consentDecided: CloudAIConsent.isDecided(),
            consentGranted: CloudAIConsent.isGranted(),
            onDevice: OnDeviceAvailability.current
        )
    }

    static func resolve(
        cloudConfigured: Bool,
        consentDecided: Bool,
        consentGranted: Bool,
        onDevice: OnDeviceAvailability
    ) -> AIEngine {
        if cloudConfigured {
            if consentDecided && consentGranted { return .cloud }
            if !consentDecided { return .needsCloudConsent }
            // Declined: honour it — on-device or a message that names the choice, never a
            // silent cloud call.
            if onDevice.isAvailable { return .onDevice }
            return .unavailable(message: Self.cloudDeclinedMessage)
        }
        if onDevice.isAvailable { return .onDevice }
        return .unavailable(message: onDevice.message)
    }

    static let cloudDeclinedMessage = "Cloud AI is switched off, and this iPhone can't run "
        + "on-device AI. Turn cloud AI on from the You tab (Cloud AI) to use this feature. "
        + "Everything else in Hair Compass works fully on this device."
}

// MARK: - Client-side daily budget

/// A deterministic guard against one runaway or abusive client draining the shared DeepSeek
/// balance sitting behind the key embedded in this binary. This is NOT billing enforcement —
/// DeepSeek's own account controls are that — it only makes sure a single misbehaving install
/// (a retry loop, a tampered build hammering the endpoint) can't run up unlimited cloud
/// inference on one shared account while the taster is unlimited-by-design for everyone else.
/// The limit is deliberately generous: ordinary use (a handful of chat turns and deep analyses
/// a day) sits far under it, so a real person should never see the refusal message it produces.
/// When it does trip, the caller's existing on-device fallback is what makes the refusal
/// harmless rather than a dead end — on-device inference is free and unmetered.
nonisolated enum CloudAIBudget {
    static let dailyLimit = 100
    static let dayDefaultsKey = "cloudAIBudgetDay"
    static let countDefaultsKey = "cloudAIBudgetCount"

    /// "yyyy-MM-dd" in the given calendar — pure component math (no formatter state), so the
    /// day boundary lands exactly at local midnight.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Records one cloud request against today's count and reports whether it was allowed.
    /// There's no midnight timer — the rollover to a fresh count of zero happens lazily, the
    /// first time a call sees a day string that no longer matches what's stored. `now`/
    /// `defaults` are explicit so `CloudAITests` can pin a fixed clock and a throwaway suite.
    @discardableResult
    static func consume(now: Date = Date(), defaults: UserDefaults = .standard, calendar: Calendar = .current) -> Bool {
        let today = dayString(now, calendar: calendar)
        let count = defaults.string(forKey: dayDefaultsKey) == today ? defaults.integer(forKey: countDefaultsKey) : 0
        guard count < dailyLimit else { return false }
        defaults.set(today, forKey: dayDefaultsKey)
        defaults.set(count + 1, forKey: countDefaultsKey)
        return true
    }
}

// MARK: - Cancellation

/// Type-erases `Task<Success, Never>` so a service can hold "whatever generation task is
/// currently running" in one stored property regardless of what it returns, and cancel it
/// generically from a `cancel()` method. `HairAnalysisService` and `HairChatService` both use
/// this so a dismissed sheet can stop an in-flight — and billed — cloud call instead of letting
/// it run to completion unobserved.
protocol CancellableTask: Sendable { func cancel() }
extension Task: CancellableTask where Failure == Never {}

// MARK: - Client

/// The DeepSeek client: one non-streaming `/chat/completions` call per request.
///
/// Deliberately non-streaming — generated prose is never shown before `AIOutputValidator`
/// passes it (the on-device paths already discard partials for the same reason), so a stream
/// would buy latency-to-first-token the UI is not allowed to display anyway.
///
/// `nonisolated`: the app default-isolates new declarations to `@MainActor`, but this client's
/// networking and JSON (de)serialization have no business running on the main thread — marking
/// the enum `nonisolated` keeps every static member here off the main actor. `Turn` and
/// `ServiceError` are `Sendable`, so the `await CloudAI.reply(...)` call sites in the
/// (`@MainActor`) services still cross the actor boundary safely.
nonisolated enum CloudAI {
    struct Turn: Equatable, Sendable {
        var role: String   // "user" | "assistant"
        var text: String
    }

    /// A user-facing failure. `isNetwork` distinguishes "you're offline" (worth an on-device
    /// fallback, and worth surfacing over a generic on-device failure message if that fallback
    /// then also fails — "check your connection" is the actionable diagnosis) from "the service
    /// answered badly" (retrying locally won't help the caller decide anything, but the
    /// fallback is still tried).
    struct ServiceError: Error, Equatable {
        let message: String
        let isNetwork: Bool
    }

    private static let logger = Logger(subsystem: "harib.Hair-Compass-AI-5", category: "CloudAI")

    static let offlineMessage = "Couldn't reach the AI service. Check your connection and try again."
    static let serviceDownMessage = "The AI service is temporarily unavailable. Please try again in a moment."
    static let emptyReplyMessage = "The answer came back empty. Please try again."
    static let budgetExceededMessage = "Today's AI limit is reached — it resets tomorrow. On-device answers still work where supported."

    /// Ephemeral on purpose: health-derived JSON payloads (shedding levels, lab values, dates)
    /// shouldn't linger in the shared on-disk `URLCache` or pick up cookies from other requests
    /// this app makes, and there is nothing here worth caching across launches anyway. Tests
    /// inject a different session via the `session:` parameter.
    private static let defaultSession = URLSession(configuration: .ephemeral)

    /// One completed turn. `system` grounds the model; `turns` is the capped conversation,
    /// oldest → newest, ending on the user's message.
    static func reply(
        system: String,
        turns: [Turn],
        maxTokens: Int = 600,
        config: CloudAIConfig = .current,
        session: URLSession = defaultSession,
        now: Date = Date(),
        calendar: Calendar = .current,
        budgetDefaults: UserDefaults = .standard
    ) async throws -> String {
        guard config.isConfigured, let url = config.chatCompletionsURL else {
            throw ServiceError(message: serviceDownMessage, isNetwork: false)
        }
        // Client-side abuse containment, not billing enforcement — see `CloudAIBudget`. Checked
        // before building the request so a tripped budget never touches the network at all.
        guard CloudAIBudget.consume(now: now, defaults: budgetDefaults, calendar: calendar) else {
            throw ServiceError(message: budgetExceededMessage, isNetwork: false)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(requestBody(system: system, turns: turns, config: config, maxTokens: maxTokens))
        } catch {
            // `try?` here would silently POST with a nil body — a request DeepSeek would then
            // (correctly) reject, but with an error message that blames the service instead of
            // the payload. Fail closed with the same message a misconfigured client gets.
            throw ServiceError(message: serviceDownMessage, isNetwork: false)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("Cloud AI transport failure: \((error as NSError).code, privacy: .public)")
            throw ServiceError(message: offlineMessage, isNetwork: true)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Status only — response bodies can carry account details that don't belong in logs.
            logger.error("Cloud AI HTTP \(http.statusCode, privacy: .public)")
            throw ServiceError(message: serviceDownMessage, isNetwork: false)
        }

        guard let text = replyText(from: data), !text.isEmpty else {
            throw ServiceError(message: emptyReplyMessage, isNetwork: false)
        }
        return text
    }

    // MARK: Wire shapes — internal so `CloudAITests` can pin the request we actually send.

    struct ChatMessagePayload: Codable, Equatable {
        let role: String
        let content: String
    }

    struct ChatRequestPayload: Codable, Equatable {
        let model: String
        let messages: [ChatMessagePayload]
        let temperature: Double
        let maxTokens: Int
        let stream: Bool

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature, stream
            case maxTokens = "max_tokens"
        }
    }

    static func requestBody(system: String, turns: [Turn], config: CloudAIConfig, maxTokens: Int) -> ChatRequestPayload {
        var messages = [ChatMessagePayload(role: "system", content: system)]
        for turn in turns {
            messages.append(ChatMessagePayload(role: turn.role == "assistant" ? "assistant" : "user", content: turn.text))
        }
        return ChatRequestPayload(
            model: config.model,
            messages: foldConsecutiveSameRole(messages),
            // Low-variance factual prose: the validator rejects invention, so don't invite it.
            temperature: 0.5,
            maxTokens: maxTokens,
            stream: false
        )
    }

    /// Folds consecutive messages that share a role into one, joining their text with a blank
    /// line and preserving order. Exists because `deepseek-reasoner` — a supported
    /// `HC_AI_MODEL` override, not just the default `deepseek-chat` — 400s on a conversation
    /// that repeats a role two turns running. That shape happens for real: when a turn fails,
    /// `HairChatService` leaves the unanswered user message in history, so the next `send`
    /// appends a second user turn right after it and the payload would read
    /// `[system, ..., user, user]`. Folding keeps every request role-alternating without
    /// dropping any of the text that was going to be sent.
    static func foldConsecutiveSameRole(_ messages: [ChatMessagePayload]) -> [ChatMessagePayload] {
        var folded: [ChatMessagePayload] = []
        for message in messages {
            if let last = folded.last, last.role == message.role {
                folded[folded.count - 1] = ChatMessagePayload(role: last.role, content: last.content + "\n\n" + message.content)
            } else {
                folded.append(message)
            }
        }
        return folded
    }

    struct ChatResponsePayload: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
        }
        let choices: [Choice]?
    }

    static func replyText(from data: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(ChatResponsePayload.self, from: data) else { return nil }
        return decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
