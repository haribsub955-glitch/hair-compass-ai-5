import Foundation

/// The client half of the agent protocol.
///
/// One turn is not one request. The server opens an SSE stream, pushes `tool_request` events down
/// it, and expects each result back as its own POST:
///
///     POST /v1/turn            -> SSE: open, tool_request…, answer, done
///     POST /v1/turn/result     <- one per call, keyed by the id the SERVER issued
///
/// Two rules this client must never break, both enforced on the server but cheaper to get right
/// here than to have refused there:
///
/// 1. **Answer with the id you were given.** Call ids are namespaced per run by the server
///    (`{run_id}:{model_id}`). Echoing anything else is refused as "no such call" and the turn
///    hangs to its deadline.
/// 2. **Advertise only what this build actually implements.** `availableCapabilities` can only ever
///    *remove* tools from what the server offers. Claiming one you cannot run wins nothing and
///    guarantees a timeout when the server dispatches it.
///
/// Foundation-only, and it lives inside this app target rather than in a package: Hair Compass
/// permits Apple frameworks exclusively (no SPM, no CocoaPods), and the project's
/// `PBXFileSystemSynchronizedRootGroup` means a `.swift` file on disk joins the target by folder
/// with no `project.pbxproj` edit. The wire contract it implements is versioned server-side, so
/// the two stay in step through `protocol_version`, not through a shared build artefact.
public actor AgentClient {

    public struct Configuration: Sendable {
        /// e.g. `http://192.168.68.132:8010` in development, the hosted URL later. This single
        /// value is the entire difference between a laptop on the LAN and a datacenter.
        public var baseURL: URL
        /// Stable per install. Survives app restarts; changes on reinstall.
        ///
        /// Sent to `/v1/session` and **nowhere else**. It says which install is asking, but it is
        /// not a credential: the app generates it, so anyone who learned it could otherwise act as
        /// that user. The session token is the credential.
        public var installationID: String
        /// StoreKit JWS. Ignored in development, verified server-side in production.
        public var subscriptionToken: String
        /// Current app build, so the server can tell a stale client to update.
        public var appBuild: String
        /// Pre-shared key for the deployment itself, sent on EVERY request as `X-Access-Key`.
        ///
        /// Not authentication of a user — a front door on the whole server while it is reachable
        /// from the internet for testing. Without it every endpoint returns 401, including
        /// `/health`. Read from the scheme's run environment so it never lands in the repository;
        /// ask Mohammed for the value.
        public var accessKey: String

        public init(
            baseURL: URL,
            installationID: String,
            subscriptionToken: String = "",
            appBuild: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            accessKey: String = ProcessInfo.processInfo.environment["HC_ACCESS_KEY"] ?? ""
        ) {
            self.baseURL = baseURL
            self.installationID = installationID
            self.subscriptionToken = subscriptionToken
            self.appBuild = appBuild
            self.accessKey = accessKey
        }
    }

    /// What the app must do when the agent asks for a tool.
    ///
    /// The client owns this because the tools reach data that never leaves the device — SwiftData,
    /// HealthKit, the photo store. The server knows the *names*; only this knows how to run them.
    public protocol ToolExecutor: Sendable {
        /// Tools this build implements. Sent at turn start; can only narrow what the server offers.
        var implementedTools: [String] { get }
        /// Run one call. Throwing is fine and expected — it becomes a `failed` result for that call
        /// alone, not a failed turn.
        func run(tool: String, arguments: [String: Any]) async throws -> [String: Any]
    }

    public enum Event: Sendable {
        case opened(runID: String)
        /// A wave of tool calls. `parallel` means run them concurrently and submit each as it
        /// finishes — a fast read must not wait behind a slow one.
        case toolsRequested(count: Int, parallel: Bool)
        case answer(String, served: Bool, safety: String)
        case failed(String)
        case finished
    }

    public enum AgentError: Error, Sendable {
        case badResponse(status: Int)
        case transport(String)
        /// The session expired or was refused. Recoverable: open a new one and retry once.
        case unauthenticated
        /// This build may no longer talk to this server.
        case upgradeRequired
    }

    /// What `/v1/session` established.
    public struct Session: Sendable {
        public let token: String
        public let entitlement: String
        /// `current`, `encouraged` or `required` — so the app can nag before it is ever cut off.
        public let upgrade: String
        /// Tool names this build may run: the server's allowlist intersected with what we
        /// advertised. It only ever narrows.
        public let tools: [String]
    }

    private let configuration: Configuration
    private let session: URLSession
    /// Held for the process lifetime and re-obtained on expiry. Deliberately not persisted: it is
    /// a bearer credential with a short life, and the installation id can always mint a new one.
    private var current: Session?

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Every request carries the deployment key. One place, so a new endpoint cannot forget it —
    /// the same reasoning that put the server's own gate in middleware rather than per-route.
    private func stamp(_ request: inout URLRequest) {
        if !configuration.accessKey.isEmpty {
            request.setValue(configuration.accessKey, forHTTPHeaderField: "X-Access-Key")
        }
    }

    // MARK: - Session

    /// Open a session and keep the token. Safe to call repeatedly; only the first does work.
    ///
    /// This is the ONLY request that carries the installation id. Everything afterwards proves
    /// itself with the returned token, which the server signed — so knowing someone's installation
    /// id no longer lets you act as them.
    @discardableResult
    public func startSession(force: Bool = false) async throws -> Session {
        if let current, !force { return current }

        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        stamp(&request)
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "installation_id": configuration.installationID,
            "subscription_token": configuration.subscriptionToken,
            "hints": [
                "platform": "ios",
                "app_build": configuration.appBuild,
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                "available_capabilities": [] as [String],
            ],
        ])

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 426 { throw AgentError.upgradeRequired }
        guard status == 200 else { throw AgentError.badResponse(status: status) }

        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let token = payload["session_token"] as? String, !token.isEmpty else {
            throw AgentError.unauthenticated
        }
        let principal = payload["principal"] as? [String: Any] ?? [:]
        let established = Session(
            token: token,
            entitlement: principal["entitlement"] as? String ?? "free",
            upgrade: payload["upgrade"] as? String ?? "current",
            tools: (payload["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        )
        current = established
        return established
    }

    // MARK: - One turn

    /// Run a turn, executing tool calls through `executor`, reporting progress through `onEvent`.
    ///
    /// Returns the final answer, or `nil` when the server served nothing — which is not an error.
    /// It means the safety layer stripped the response or the loop stopped on something it could
    /// not verify, and the app should render its own deterministic summary instead. Treating that
    /// as a failure would show the user an error where a perfectly good local answer exists.
    @discardableResult
    public func runTurn(
        userText: String,
        executor: ToolExecutor,
        onEvent: @Sendable (Event) -> Void = { _ in }
    ) async throws -> String? {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/turn"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        stamp(&request)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "session_token": try await startSession().token,
            "user_text": userText,
            "platform": "ios",
            "available_capabilities": executor.implementedTools,
        ])

        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 401 {
            // The token expired mid-session, which is ordinary after a day. Drop it and surface
            // the error rather than retrying here: a silent retry re-sends a turn the user may
            // already have been metered for.
            current = nil
            throw AgentError.unauthenticated
        }
        if status == 426 { throw AgentError.upgradeRequired }
        guard status == 200 else { throw AgentError.badResponse(status: status) }

        var answer: String?
        var event = ""

        for try await line in bytes.lines {
            if line.hasPrefix("event: ") {
                event = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data: ") {
                let payload = Self.decode(String(line.dropFirst(6)))
                switch event {
                case "open":
                    onEvent(.opened(runID: payload["run_id"] as? String ?? ""))

                case "tool_request":
                    let calls = payload["calls"] as? [[String: Any]] ?? []
                    let parallel = payload["parallel"] as? Bool ?? true
                    onEvent(.toolsRequested(count: calls.count, parallel: parallel))
                    await execute(calls: calls, parallel: parallel, using: executor)

                case "answer":
                    let text = payload["text"] as? String ?? ""
                    let served = payload["served"] as? Bool ?? false
                    onEvent(.answer(text, served: served,
                                    safety: payload["safety"] as? String ?? "allow"))
                    answer = served && !text.isEmpty ? text : nil

                case "error":
                    onEvent(.failed(payload["message"] as? String ?? "The turn failed."))

                case "done":
                    onEvent(.finished)
                    return answer

                default:
                    break
                }
            }
        }
        return answer
    }

    // MARK: - Tool execution

    /// Run a wave and submit each result as it lands.
    ///
    /// A parallel wave really is run in parallel — that is the whole reason the server bothers to
    /// group independent reads. Running them serially here would throw away the latency win and
    /// leave the difference invisible, because the turn would still complete.
    private func execute(
        calls: [[String: Any]],
        parallel: Bool,
        using executor: ToolExecutor
    ) async {
        if parallel {
            await withTaskGroup(of: Void.self) { group in
                for call in calls {
                    group.addTask { await self.runAndSubmit(call, using: executor) }
                }
            }
        } else {
            // Serial waves hold exactly one mutating call. Never batch them — see docs/DISPATCH.md
            // on why two concurrent writes leave a state nobody can reconstruct.
            for call in calls {
                await runAndSubmit(call, using: executor)
            }
        }
    }

    private func runAndSubmit(_ call: [String: Any], using executor: ToolExecutor) async {
        // The server's id, echoed back exactly. Never re-derived, never the model's own id.
        let callID = call["id"] as? String ?? ""
        let tool = call["tool"] as? String ?? ""
        let arguments = call["arguments"] as? [String: Any] ?? [:]

        var status = "succeeded"
        var payload: [String: Any] = [:]
        var errorText = ""
        do {
            payload = try await executor.run(tool: tool, arguments: arguments)
        } catch {
            // One tool failing is one failed call, not a failed turn. The server decides whether
            // that is recoverable, using the tool's own declaration.
            status = "failed"
            errorText = String(describing: error)
        }
        await submit(callID: callID, status: status, payload: payload, error: errorText)
    }

    private func submit(
        callID: String, status: String, payload: [String: Any], error: String
    ) async {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/turn/result"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        stamp(&request)
        request.timeoutInterval = 30
        // No principal, no run id, no tool name: the server already knows all three from the call
        // id it issued. Anything stated here would be a claim it has to verify.
        guard let token = current?.token else { return }
        let body: [String: Any] = [
            "session_token": token,
            "result": [
                "call_id": callID,
                "status": status,
                "payload": status == "succeeded" ? payload : NSNull(),
                "error": error,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = data
        // Submission is idempotent server-side, so a retry here is safe. Swallowing the failure is
        // deliberate: the turn expires on its own deadline, which is a better outcome than an
        // exception unwinding a task group mid-wave.
        _ = try? await session.data(for: request)
    }

    private static func decode(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}
