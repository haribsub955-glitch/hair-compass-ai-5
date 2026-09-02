import Foundation
import Testing

@testable import Hair_Compass_AI_5

/// Memory retrieval. Pure scoring over in-memory rows — no store, no agent, no network.
///
/// The tests that matter most are the isolation ones: a session memory from one conversation must
/// never surface in another. Getting that wrong leaks a private aside from months ago into an
/// unrelated answer, and it fails silently — the answer just quietly contains something it
/// shouldn't.
struct AgentMemoryTests {

    private func memory(
        _ text: String,
        scope: AgentMemoryScope = .global,
        session: String = "s1",
        kind: AgentMemoryKind = .fact,
        daysAgo: Int = 0
    ) -> AgentMemory {
        AgentMemory(
            scope: scope,
            sessionID: session,
            text: text,
            kind: kind,
            createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        )
    }

    // MARK: - Scope isolation

    @Test func aSessionMemoryNeverEscapesItsConversation() {
        let all = [memory("started minoxidil in January", scope: .session, session: "s1")]
        let other = AgentMemoryStore.recall(all, scope: nil, sessionID: "s2", query: "minoxidil")
        #expect(other.isEmpty)
    }

    @Test func aSessionMemoryIsVisibleInsideItsOwnConversation() {
        let all = [memory("started minoxidil in January", scope: .session, session: "s1")]
        let same = AgentMemoryStore.recall(all, scope: nil, sessionID: "s1", query: "minoxidil")
        #expect(same.count == 1)
    }

    @Test func aGlobalMemoryIsVisibleFromAnyConversation() {
        let all = [memory("started minoxidil in January", scope: .global, session: "s1")]
        let elsewhere = AgentMemoryStore.recall(all, scope: nil, sessionID: "s99", query: "minoxidil")
        #expect(elsewhere.count == 1)
    }

    @Test func askingForSessionScopeDoesNotReturnGlobalMemories() {
        // Asking for one scope and receiving another is a surprise, and a surprise in a retrieval
        // layer becomes a surprise in an answer.
        let all = [memory("global fact about minoxidil", scope: .global, session: "s1")]
        let scoped = AgentMemoryStore.recall(
            all, scope: .session, sessionID: "s1", query: "minoxidil"
        )
        #expect(scoped.isEmpty)
    }

    @Test func aForgottenMemoryIsNeverRecalled() {
        let forgotten = memory("wants to stop finasteride")
        forgotten.forgottenAt = .now
        let results = AgentMemoryStore.recall(
            [forgotten], scope: nil, sessionID: "s1", query: "finasteride"
        )
        #expect(results.isEmpty)
    }

    // MARK: - Ranking

    @Test func aPreferenceOutranksANoteAtEqualOverlap() {
        let all = [
            memory("mentioned rosemary oil once", kind: .note),
            memory("prefers rosemary oil over minoxidil", kind: .preference),
        ]
        let results = AgentMemoryStore.recall(all, scope: nil, sessionID: "s1", query: "rosemary")
        #expect(results.first?.kind == .preference)
    }

    @Test func irrelevantMemoriesAreNotReturnedAtAll() {
        // Returning everything and letting the model sort it out is how a recall quietly becomes
        // the largest thing in the prompt.
        let all = [memory("started minoxidil in January")]
        #expect(AgentMemoryStore.recall(all, scope: nil, sessionID: "s1", query: "sleep").isEmpty)
    }

    @Test func recallIsBounded() {
        let all = (0..<50).map { memory("minoxidil note number \($0)") }
        let results = AgentMemoryStore.recall(all, scope: nil, sessionID: "s1", query: "minoxidil")
        #expect(results.count == AgentMemoryStore.defaultLimit)
    }

    @Test func anEmptyQueryReturnsTheMostRecentlyUsefulRatherThanNothing() {
        // "What do you know about me?" is a real question.
        let all = [memory("older", daysAgo: 30), memory("newer", daysAgo: 1)]
        let results = AgentMemoryStore.recall(all, scope: nil, sessionID: "s1", query: "")
        #expect(results.first?.text == "newer")
    }

    @Test func shortDomainWordsSurviveTokenisation() {
        // "oil" and "dose" are three letters and load-bearing in this domain.
        #expect(AgentMemoryStore.tokenise("rosemary oil dose").contains("oil"))
        #expect(AgentMemoryStore.tokenise("rosemary oil dose").contains("dose"))
    }

    // MARK: - Consolidation

    @Test func consolidationNeverDropsAPreference() {
        // Someone who said "don't suggest finasteride" must not have that forgotten because they
        // stopped mentioning it.
        let preferences = (0..<20).map { memory("preference \($0)", kind: .preference) }
        let notes = (0..<20).map { memory("note \($0)", kind: .note) }
        let candidates = AgentMemoryStore.consolidationCandidates(preferences + notes, keeping: 10)
        #expect(candidates.allSatisfy { $0.kind != .preference })
    }

    @Test func consolidationPrefersDroppingWhatIsNeverRead() {
        let read = memory("read often")
        read.recallCount = 20
        let unread = memory("never read")
        let candidates = AgentMemoryStore.consolidationCandidates([read, unread], keeping: 1)
        #expect(candidates.map(\.text) == ["never read"])
    }

    @Test func aSmallStoreIsLeftAlone() {
        let all = (0..<5).map { memory("note \($0)", kind: .note) }
        #expect(AgentMemoryStore.consolidationCandidates(all, keeping: 200).isEmpty)
    }

    @Test func recallMarksWhatWasUsed() {
        let one = memory("started minoxidil")
        AgentMemoryStore.markRecalled([one])
        #expect(one.recallCount == 1)
        #expect(one.lastRecalledAt != nil)
    }
}
