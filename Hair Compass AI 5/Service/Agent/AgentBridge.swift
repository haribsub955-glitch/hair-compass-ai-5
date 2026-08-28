import Foundation
import SwiftData

#if DEBUG
/// Routes Wren's chat through the agent platform instead of the on-device model.
///
/// `MOOSAWI_HANDOVER.md` §6b records that `AgentClient` was referenced by zero views: the shipped
/// chat and the agent built to replace it lived side by side, connected to nothing. This is that
/// connection, taken the way §6b recommends — keep `HairChatSheet`, swap what sits behind it —
/// rather than building the agent a second surface.
///
/// **Behind `HC_AGENT`, and DEBUG-only.** The agent talks to a server; the shipped app's promise
/// is that its AI is on-device with no network egress. Until that promise is deliberately
/// renegotiated (privacy policy, `PrivacyInfo.xcprivacy`, the App Store data declaration, a
/// consent flow), this must not be reachable in a Release build — so it isn't compiled into one.
///
/// One turn is a stream with tool round-trips in the middle, which the one-shot chat never had
/// to show. `progress` narrates those waves so the sheet can render something truthful while the
/// device is answering the server's questions.
enum AgentBridge {

    /// `HC_AGENT` — route chat turns through the agent platform.
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("HC_AGENT") }

    /// `HC_AGENT_URL <url>` overrides the server. Defaults to the local stand-in on loopback,
    /// which the Simulator reaches directly because it shares the host's network stack. A
    /// physical device needs the Mac's LAN address here instead.
    static var baseURL: URL {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "HC_AGENT_URL"), i + 1 < args.count,
           let url = URL(string: args[i + 1]) {
            return url
        }
        return URL(string: "http://localhost:8100")!
    }

    /// Stable per install, as the contract requires — it identifies which install is asking.
    /// Not a credential: the session token is. Persisted so it survives app restarts.
    static var installationID: String {
        let key = "agentInstallationID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    private static var client: AgentClient?

    static func shared() -> AgentClient {
        if let client { return client }
        let made = AgentClient(
            configuration: .init(baseURL: baseURL, installationID: installationID)
        )
        client = made
        return made
    }

    /// Human-readable narration for a tool wave. The user should never see raw tool names —
    /// "read_lab_results" is an implementation detail, "Checking your lab results" is the truth
    /// about what the device is doing on their behalf.
    static func progressLine(count: Int) -> String {
        count <= 1 ? "Reading your record…" : "Reading your record (\(count) checks)…"
    }

    /// What one agent turn produced: the answer, and every fact the device handed the model.
    ///
    /// The facts matter as much as the answer. `AIOutputValidator` rejects any number that isn't
    /// in the material it was given, and the agent's numbers come from *tool results*, not from
    /// the prebuilt `AIContext`. Validating the answer against the context alone therefore
    /// rejects correct, well-grounded output — which is exactly what it did the first time this
    /// was wired. The tool payloads are the ground truth the model actually saw, so they are
    /// what the gate has to be shown.
    struct TurnResult: Sendable {
        let answer: String?
        let facts: String
        /// Which tools this turn actually ran, in call order and de-duplicated — the raw
        /// material for the "read from" line under the answer.
        let toolsUsed: [String]
    }

    /// Tool names are an implementation detail; nobody should read "read_lab_results" in a chat.
    /// These are the same things named the way the rest of the app names them.
    static func sourceLabel(for tool: String) -> String? {
        switch tool {
        case "recall_memory":       return "what you've told me"
        case "read_recent_entries": return "your recent entries"
        case "read_lab_results":    return "your lab results"
        case "read_health_signals": return "Apple Health"
        case "read_hair_science":   return "the evidence library"
        case "read_treatments":     return "your plan"
        case "read_procedures":     return "your procedures"
        case "read_triggers":       return "your logged triggers"
        case "read_progress_checkins": return "your progress check-ins"
        case "read_photo_history":  return "your photo history"
        case "read_profile":        return "your profile"
        // A write is not a source and must never be listed as one — saying an answer was "read
        // from" a change it just made would misdescribe what happened.
        case "log_entry":           return nil
        default:                    return nil
        }
    }

    /// Run one turn against the agent, executing its tool calls against this device's SwiftData.
    ///
    /// `onProgress` fires on the main actor as waves come and go, so the sheet can show movement
    /// during what is otherwise a long silence. A nil answer means the server served nothing,
    /// which the contract is explicit is not an error.
    @MainActor
    static func run(
        userText: String,
        context: ModelContext,
        sessionID: String,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws -> TurnResult {
        let recorder = ToolFactRecorder()
        let executor = RecordingToolExecutor(
            inner: AgentToolExecutor(
                context: context,
                sessionID: sessionID,
                idempotency: IdempotencyLog()
            ),
            recorder: recorder
        )
        let answer = try await shared().runTurn(userText: userText, executor: executor) { event in
            switch event {
            case .toolsRequested(let count, _):
                Task { @MainActor in onProgress(progressLine(count: count)) }
            case .answer, .finished, .failed, .opened:
                break
            }
        }
        return TurnResult(
            answer: answer,
            facts: await recorder.joined(),
            toolsUsed: await recorder.tools()
        )
    }
}

/// Accumulates every tool payload this turn returned, so the output gate can be shown the same
/// facts the model was. An actor because a parallel wave really does run its calls concurrently.
actor ToolFactRecorder {
    private var payloads: [String] = []
    private var toolNames: [String] = []

    func record(_ tool: String, payload: [String: Any]) {
        payloads.append(Self.flatten(payload))
        // First-use order, not call order: the same tool can run twice in one turn, and a source
        // list that repeats itself reads like a stutter.
        if !toolNames.contains(tool) { toolNames.append(tool) }
    }

    func joined() -> String { payloads.joined(separator: " ") }

    func tools() -> [String] { toolNames }

    /// Renders a payload the way the *model* will read it, not the way `JSONSerialization`
    /// happens to print it.
    ///
    /// This distinction is the whole reason this function exists. `JSONSerialization` writes the
    /// Double 7.4 as `7.400000000000000355`; the server hands the same value to the model through
    /// Python, which writes `7.4`. The model quotes `7.4`, and a gate holding the long form sees
    /// an invented number and replaces a perfectly good answer. Swift's `String(describing:)`
    /// for `Double` gives the same shortest round-trip form Python does, so both ends agree.
    private static func flatten(_ value: Any) -> String {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted()
                .map { "\($0)=\(flatten(dictionary[$0]!))" }
                .joined(separator: " ")
        case let array as [Any]:
            return array.map(flatten).joined(separator: " ")
        case let number as NSNumber:
            // `NSNumber` boxes Bool as well as the numeric types; a stray "1" for `true` would
            // enter the fact set as a number the model never saw.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            let double = number.doubleValue
            return double.rounded() == double ? String(Int(double)) : String(double)
        default:
            return String(describing: value)
        }
    }
}

/// Passes tool calls through untouched while recording what came back. Deliberately a wrapper
/// rather than a change to `AgentToolExecutor`: the executor's job is to answer the server, and
/// bookkeeping for the app's safety gate is not its concern.
struct RecordingToolExecutor: AgentClient.ToolExecutor {
    let inner: AgentToolExecutor
    let recorder: ToolFactRecorder
    /// Snapshotted at construction rather than forwarded: the protocol requirement is
    /// nonisolated, and the wrapped executor's own property is main-actor isolated. The value
    /// is a fixed list for a given build, so capturing it once loses nothing.
    let implementedTools: [String]

    @MainActor
    init(inner: AgentToolExecutor, recorder: ToolFactRecorder) {
        self.inner = inner
        self.recorder = recorder
        self.implementedTools = inner.implementedTools
    }

    func run(tool: String, arguments: [String: Any]) async throws -> [String: Any] {
        let payload = try await inner.run(tool: tool, arguments: arguments)
        await recorder.record(tool, payload: payload)
        return payload
    }
}
#endif
