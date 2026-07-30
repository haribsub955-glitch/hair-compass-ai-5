import Foundation
import SwiftData

/// Runs the agent's tool calls against this device's own data.
///
/// This is the `ClientIntegration` half of the platform split: the server knows a tool is called
/// `read_lab_results` and that its output is untrusted; only this file knows that means a
/// `FetchDescriptor<LabResult>` and how to shape the answer.
///
/// **The field names here are a contract with the server's prompt pack.** Rename one and nothing
/// fails — no test, no gate, no crash. The model simply starts answering with less information,
/// and the regression stays invisible until someone reads a bad answer. Keep the shapes in step,
/// and bump the envelope schema version when one has to change.
///
/// **Every value the agent sees is computed by `HairAnalytics`, never by the model.** The scalp
/// total, the lab flag, the rapid-weight-loss threshold — the app decides all of them, and the
/// agent's job is to explain a finding the app already made. That is the standing rule from the
/// project's own stance, and it is what keeps the AI from inventing numbers.
@MainActor
struct AgentToolExecutor: AgentClient.ToolExecutor {

    let context: ModelContext
    /// Conversation identity, so session-scoped memories stay inside the conversation that wrote
    /// them. Provenance, not visibility — see `AgentMemory`.
    let sessionID: String
    var calendar: Calendar = .current
    var now: () -> Date = { .now }

    /// Guards the effects a mutation would otherwise repeat after a lost acknowledgement.
    let idempotency: IdempotencyLog

    var healthAvailable: Bool = true

    /// What this build can do. Subtractive only — the server intersects it with what it would
    /// offer anyway, so naming something extra gains nothing and guarantees a timeout when the
    /// server dispatches it.
    var implementedTools: [String] {
        var tools = ["recall_memory", "read_recent_entries", "read_lab_results", "log_entry"]
        if healthAvailable { tools.append("read_health_signals") }
        return tools
    }

    enum ExecutorError: Error {
        case unknownTool(String)
        case missingIdempotencyKey(String)
    }

    func run(tool: String, arguments: [String: Any]) async throws -> [String: Any] {
        switch tool {
        case "recall_memory":       return try recallMemory(arguments)
        case "read_recent_entries": return try readRecentEntries(arguments)
        case "read_lab_results":    return try readLabResults(arguments)
        case "read_health_signals": return try readHealthSignals(arguments)
        case "log_entry":           return try await logEntry(arguments)
        default:
            // Unreachable while `implementedTools` and this switch agree. Reaching it means they
            // drifted, which deserves an error rather than a silent empty result.
            throw ExecutorError.unknownTool(tool)
        }
    }

    // MARK: - Reads

    private func recallMemory(_ arguments: [String: Any]) throws -> [String: Any] {
        let query = (arguments["query"] as? String) ?? ""
        let limit = min((arguments["limit"] as? Int) ?? AgentMemoryStore.defaultLimit, 20)
        let scope = (arguments["scope"] as? String).flatMap(AgentMemoryScope.init(rawValue:))

        let all = try context.fetch(FetchDescriptor<AgentMemory>())
        let hits = AgentMemoryStore.recall(
            all, scope: scope, sessionID: sessionID, query: query, limit: limit
        )
        AgentMemoryStore.markRecalled(hits, at: now())

        return [
            "hits": hits.map { hit in
                ["text": hit.text, "kind": hit.kind.rawValue, "recorded": iso(hit.createdAt)]
            },
            "total_stored": all.filter { !$0.isForgotten }.count,
        ]
    }

    private func readRecentEntries(_ arguments: [String: Any]) throws -> [String: Any] {
        let days = min(max((arguments["days"] as? Int) ?? 30, 1), 365)
        let since = calendar.date(byAdding: .day, value: -days, to: now()) ?? now()
        let entries = try context.fetch(
            FetchDescriptor<DailyEntry>(
                predicate: #Predicate { $0.date >= since },
                sortBy: [SortDescriptor(\DailyEntry.date, order: .reverse)]
            )
        )

        var facts: [String: Any] = [
            "days_requested": days,
            "entry_count": entries.count,
            "streak_days": HairAnalytics.loggingStreak(
                entryDates: entries.map(\.date), now: now(), calendar: calendar
            ),
        ]
        guard !entries.isEmpty else { return facts }

        // Two windows, so the model can state a direction rather than one number it has to
        // interpret. A trend is the thing a person actually asked about.
        let midpoint = calendar.date(byAdding: .day, value: -days / 2, to: now()) ?? now()
        let recent = entries.filter { $0.date >= midpoint }
        let previous = entries.filter { $0.date < midpoint }

        // Shed is a self-reported BAND (`ShedLevel`), not a hair count. Reporting it as a number
        // would invite the model to say "42 hairs a day", which this app never claims to measure.
        if let band = modalShed(recent) { facts["shed_band_recent"] = band }
        if let band = modalShed(previous) { facts["shed_band_previous"] = band }

        // `scalpTotal` is HairAnalytics' 16-point scale, computed by the app.
        if let average = mean(recent.map { Double($0.scalpTotal) }) {
            facts["scalp_score_16pt_recent"] = Int(average.rounded())
        }
        if let average = mean(previous.map { Double($0.scalpTotal) }) {
            facts["scalp_score_16pt_previous"] = Int(average.rounded())
        }
        facts["scalp_scale_max"] = 16

        // Wash days show more shed. Handing the model the count without the confound is how it
        // reads a heavy wash week as a real change.
        facts["wash_days_recent"] = recent.filter(\.washedHair).count
        return facts
    }

    private func readLabResults(_ arguments: [String: Any]) throws -> [String: Any] {
        let limit = min((arguments["limit"] as? Int) ?? 20, 50)
        var descriptor = FetchDescriptor<LabResult>(
            sortBy: [SortDescriptor(\LabResult.collectedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let results = try context.fetch(descriptor)

        return [
            "results": results.map { result -> [String: Any] in
                var row: [String: Any] = [
                    "test": result.test.rawValue,
                    "value": result.value,
                    "collected": iso(result.collectedAt),
                ]
                // The flag comes from HairAnalytics against the test's own reference range — or
                // the user's recorded range when they entered one, which is the more honest
                // comparison since reference ranges differ by lab.
                if let low = result.refLow, let high = result.refHigh, low < high {
                    row["flag"] = String(describing: HairAnalytics.flag(for: result.value, range: low...high))
                    row["ref_low"] = low
                    row["ref_high"] = high
                } else {
                    row["flag"] = String(describing: HairAnalytics.flag(for: result.value, test: result.test))
                }
                return row
            }
        ]
    }

    private func readHealthSignals(_ arguments: [String: Any]) throws -> [String: Any] {
        let days = min(max((arguments["days"] as? Int) ?? 30, 1), 365)
        let since = calendar.date(byAdding: .day, value: -days, to: now()) ?? now()
        let snapshots = try context.fetch(
            FetchDescriptor<HealthSnapshot>(
                predicate: #Predicate { $0.date >= since },
                sortBy: [SortDescriptor(\HealthSnapshot.date, order: .reverse)]
            )
        )
        guard !snapshots.isEmpty else { return ["available": false] }

        var facts: [String: Any] = ["available": true, "days_requested": days]
        if let sleep = mean(snapshots.compactMap(\.sleepHours)) {
            facts["sleep_hours_avg"] = (sleep * 10).rounded() / 10
        }
        if let hrv = mean(snapshots.compactMap(\.hrvSDNN)) {
            facts["hrv_sdnn_avg"] = Int(hrv.rounded())
        }
        // Rapid loss is a documented telogen-effluvium trigger. The threshold is the app's.
        let masses = snapshots.compactMap { snapshot -> (date: Date, massKg: Double)? in
            snapshot.bodyMassKg.map { (date: snapshot.date, massKg: $0) }
        }
        if let percent = HairAnalytics.rapidWeightLossPercent(samples: masses) {
            facts["weight_change_percent"] = (percent * 10).rounded() / 10
        }
        return facts
    }

    // MARK: - Mutations

    private func logEntry(_ arguments: [String: Any]) async throws -> [String: Any] {
        // The server refuses to dispatch a mutation without a key, so its absence means something
        // upstream is broken. Failing beats performing an effect a retry would repeat.
        guard let key = arguments["idempotency_key"] as? String, !key.isEmpty else {
            throw ExecutorError.missingIdempotencyKey("log_entry")
        }
        guard await idempotency.claim(key) else {
            // Already performed. Reporting success is correct — the effect the caller wanted has
            // happened; it simply happened on an earlier attempt.
            return ["logged": true, "duplicate": true]
        }

        let day = (arguments["date"] as? String).flatMap(parseDay) ?? now()
        let repository = DailyEntryRepository(context: context, calendar: calendar, now: now)
        let entry = try repository.upsert(day: day) { entry in
            // Shed arrives as a band name, never a count — the app does not measure hair counts.
            if let name = arguments["shed_band"] as? String, let level = Self.shedLevel(named: name) {
                entry.shed = level
            }
            if let note = arguments["note"] as? String, !note.isEmpty { entry.note = note }
        }
        return ["logged": true, "duplicate": false, "date": iso(entry.date)]
    }

    // MARK: - Helpers

    /// Most common band, not a mean — averaging ordinal self-report bands invents a precision the
    /// data does not have.
    private func modalShed(_ entries: [DailyEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        let counts = Dictionary(grouping: entries, by: { $0.shed.rawValue }).mapValues(\.count)
        guard let raw = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return ShedLevel(rawValue: raw).map { String(describing: $0) }
    }

    /// `ShedLevel` is Int-backed, but the wire carries the band's NAME — an integer on the wire
    /// would silently break the day someone reorders the cases.
    static func shedLevel(named name: String) -> ShedLevel? {
        ShedLevel.allCases.first { String(describing: $0).lowercased() == name.lowercased() }
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func parseDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}

/// Remembers which mutating calls this device has already performed.
///
/// The second half of the duplicate-effect defence: the server declines to retry a mutation whose
/// result never came back, and this declines to *repeat* one whose key it has already seen. Even a
/// retry arriving through some path nobody anticipated does nothing twice.
///
/// `UserDefaults` because it must survive a relaunch — the failure mode is a dropped
/// acknowledgement, and the app being killed is one way that happens.
actor IdempotencyLog {
    private let defaults: UserDefaults
    private let storageKey = "agent.performed_idempotency_keys"
    /// Bounded so it cannot grow forever. Ageing keys out is safe: the retry window is seconds, so
    /// a key this old belongs to a turn that ended long ago.
    private let limit = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True if this effect is new (and records it). False means it already happened — skip.
    func claim(_ key: String) -> Bool {
        var seen = defaults.stringArray(forKey: storageKey) ?? []
        guard !seen.contains(key) else { return false }
        seen.append(key)
        if seen.count > limit { seen.removeFirst(seen.count - limit) }
        defaults.set(seen, forKey: storageKey)
        return true
    }
}
