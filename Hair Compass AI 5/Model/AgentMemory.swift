import Foundation
import SwiftData

/// What the agent remembers between conversations — stored on the device, like everything personal.
///
/// The agent runs on a server but its memory does not. A memory is the user's own words about their
/// own health; keeping it local means it is never transferred, which is both the honest privacy
/// position and the simplest PDPL answer. The server reads it the same way it reads anything else
/// on the phone: by asking, through `recall_memory`, and only the matching rows cross the wire.
///
/// **Scopes are visibility, not provenance.** A memory written during one conversation but scoped
/// `global` is visible in every later one; `session` memories stay inside the conversation that
/// created them. Those are different questions and conflating them is how a private aside from
/// three months ago ends up in an unrelated answer.
@Model
final class AgentMemory {

    /// Visibility. Stored as a String so renaming a case never breaks the schema — the same
    /// convention every other enum in this app follows.
    var scopeRaw: String = AgentMemoryScope.session.rawValue

    /// Which conversation produced this. Provenance, kept separate from scope on purpose: a
    /// `global` memory still records where it came from, so it can be shown, audited, or revoked
    /// per conversation.
    var sessionID: String = ""

    var text: String = ""

    /// What kind of thing this is, so retrieval can prefer facts over passing remarks.
    var kindRaw: String = AgentMemoryKind.fact.rawValue

    var createdAt: Date = Date.now
    /// Touched on every recall. Lets consolidation drop what is never read rather than what is
    /// merely old — a fact recalled weekly matters more than one written yesterday.
    var lastRecalledAt: Date?
    var recallCount: Int = 0

    /// Set when the user asks to forget something. Kept as a tombstone rather than deleted so a
    /// consolidation pass cannot resurrect it from an older summary.
    var forgottenAt: Date?

    init(
        scope: AgentMemoryScope = .session,
        sessionID: String = "",
        text: String = "",
        kind: AgentMemoryKind = .fact,
        createdAt: Date = .now
    ) {
        self.scopeRaw = scope.rawValue
        self.sessionID = sessionID
        self.text = text
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
    }

    var scope: AgentMemoryScope {
        get { AgentMemoryScope(rawValue: scopeRaw) ?? .session }
        set { scopeRaw = newValue.rawValue }
    }

    var kind: AgentMemoryKind {
        get { AgentMemoryKind(rawValue: kindRaw) ?? .fact }
        set { kindRaw = newValue.rawValue }
    }

    var isForgotten: Bool { forgottenAt != nil }
}

/// Where a memory can be seen.
enum AgentMemoryScope: String, CaseIterable, Sendable {
    /// Visible only inside the conversation that wrote it.
    case session
    /// Visible in every conversation. The default for anything durable about the person.
    case global
}

/// What a memory is, so retrieval can rank.
enum AgentMemoryKind: String, CaseIterable, Sendable {
    /// A durable statement about the person or their routine. "Started minoxidil in January."
    case fact
    /// Something they asked for. "Prefers short answers." "Doesn't want to discuss finasteride."
    case preference
    /// A one-off from a conversation, low value later.
    case note
}

// MARK: - Retrieval

/// Reading and writing memories. Pure query construction plus scoring — no networking, no agent.
///
/// Kept deliberately dumb: keyword overlap, not embeddings. A local embedding model would be
/// better at recall and is the obvious upgrade, but it is also a large dependency for a store that
/// will hold tens of rows per user for a long time. Start with something whose failures are
/// obvious; escalate when a measurement says to (framework.md's ladder).
enum AgentMemoryStore {

    /// Cap on what one recall returns. The agent pays for every token of this on every turn that
    /// asks, so unbounded recall is a slow, invisible cost leak.
    static let defaultLimit = 5

    /// Memories visible from a given conversation, most relevant first.
    ///
    /// A blank query returns the most recently useful ones rather than nothing — "what do you know
    /// about me?" is a real question and should not fall through to an empty answer.
    static func recall(
        _ all: [AgentMemory],
        scope: AgentMemoryScope?,
        sessionID: String,
        query: String,
        limit: Int = defaultLimit
    ) -> [AgentMemory] {
        let visible = all.filter { memory in
            guard !memory.isForgotten else { return false }
            switch memory.scope {
            case .global:
                // Global is visible everywhere, so a scope filter of `.session` must still exclude
                // it — asking for session memories and receiving global ones is a surprise.
                return scope == nil || scope == .global
            case .session:
                return (scope == nil || scope == .session) && memory.sessionID == sessionID
            }
        }

        let terms = tokenise(query)
        if terms.isEmpty {
            return Array(
                visible.sorted { lhs, rhs in
                    (lhs.lastRecalledAt ?? lhs.createdAt) > (rhs.lastRecalledAt ?? rhs.createdAt)
                }.prefix(limit)
            )
        }

        // Split into named, explicitly typed steps: as one chained expression over anonymous
        // tuples this defeated the type-checker outright ("unable to type-check in reasonable
        // time"). Same ranking — score descending, newest first at equal score.
        let scored: [(memory: AgentMemory, score: Int)] = visible.compactMap { memory in
            let value = score(memory, terms: terms)
            return value > 0 ? (memory: memory, score: value) : nil
        }
        let ranked = scored.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.memory.createdAt > rhs.memory.createdAt : lhs.score > rhs.score
        }
        return ranked.prefix(limit).map(\.memory)
    }

    /// Overlap, weighted by kind. Facts and preferences outrank passing notes at equal overlap,
    /// because a preference the user stated once should not be buried by chatter that happens to
    /// share a word.
    static func score(_ memory: AgentMemory, terms: Set<String>) -> Int {
        let overlap = tokenise(memory.text).intersection(terms).count
        guard overlap > 0 else { return 0 }
        let weight: Int = switch memory.kind {
        case .preference: 3
        case .fact: 2
        case .note: 1
        }
        return overlap * weight
    }

    static func tokenise(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    /// Small on purpose. A long stop list starts removing words that matter in this domain — "oil"
    /// and "dose" are three letters and load-bearing.
    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "was", "are", "you", "your", "have", "has",
        "but", "not", "any", "all", "can", "did", "does", "how", "what", "when", "why", "about",
    ]

    /// Record that a memory was used, so consolidation can favour what is actually read.
    static func markRecalled(_ memories: [AgentMemory], at date: Date = .now) {
        for memory in memories {
            memory.lastRecalledAt = date
            memory.recallCount += 1
        }
    }

    /// What to drop when the store grows past `keeping`.
    ///
    /// Never touches preferences: a user who said "don't suggest finasteride" must not have that
    /// forgotten because they stopped mentioning it. Among the rest, the least-recalled and oldest
    /// go first. Returns the candidates rather than deleting them — deletion is the caller's
    /// decision, and the app's rule is that removals go to a tombstone, not a void.
    static func consolidationCandidates(
        _ all: [AgentMemory], keeping: Int = 200
    ) -> [AgentMemory] {
        let live = all.filter { !$0.isForgotten && $0.kind != .preference }
        guard live.count > keeping else { return [] }
        let ranked = live.sorted { lhs, rhs in
            lhs.recallCount == rhs.recallCount
                ? lhs.createdAt < rhs.createdAt
                : lhs.recallCount < rhs.recallCount
        }
        return Array(ranked.prefix(live.count - keeping))
    }
}
