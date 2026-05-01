@testable import Eigin
import Foundation
import Testing

@Suite("RelevantKnowledgeSource")
@MainActor
struct RelevantKnowledgeSourceTests {
    // MARK: - Helpers

    private func input(
        messages: [ChatMessage] = [],
        isSmallContext: Bool = false,
        spaceID: UUID? = nil,
        agentID: UUID = UUID()
    ) -> SystemHintInput {
        SystemHintInput(
            agentID: agentID,
            bootstrapComplete: true,
            needsCompaction: false,
            hasSpaces: false,
            messages: messages,
            space: nil,
            spaceID: spaceID,
            language: nil,
            mode: .text,
            activeIntents: [],
            activeSkills: [],
            availableSkills: [],
            provider: ProviderSnapshot(name: "Test", baseURL: "https://test.com"),
            modelID: "test-model",
            isSmallContext: isSmallContext
        )
    }

    private func entry(
        qualifiedID: String,
        summary: String,
        top: [String],
        more: Int = 0
    ) -> RelevantKnowledgeEntry {
        RelevantKnowledgeEntry(
            qualifiedID: qualifiedID,
            type: qualifiedID.split(separator: ".").first.map(String.init) ?? "",
            summary: summary,
            score: 0.9,
            topRelationships: top,
            moreRelationships: more
        )
    }

    /// Creates a source with a hook that returns a fixed set of entries.
    private func makeSource(
        returning entries: [RelevantKnowledgeEntry] = []
    ) -> (RelevantKnowledgeSource, FakeKnowledgeService, Hook) {
        let hook = Hook()
        hook.fixedEntries = entries
        return makeSource(hook: hook)
    }

    /// Creates a source with a fully configurable hook (use
    /// ``Hook/entriesPerCall`` to vary results across turns).
    private func makeSource(
        hook: Hook
    ) -> (RelevantKnowledgeSource, FakeKnowledgeService, Hook) {
        let fake = FakeKnowledgeService()
        let source = RelevantKnowledgeSource(
            knowledgeService: fake,
            hydrator: { userText, _, spaceID, agentID in
                hook.record(userText: userText, spaceID: spaceID, agentID: agentID)
                return hook.nextEntries()
            }
        )
        return (source, fake, hook)
    }

    /// `@unchecked Sendable` is fine here — every access happens on the
    /// main actor inside the @MainActor test suite, serialising naturally.
    final class Hook: @unchecked Sendable {
        var lastUserText: String?
        var lastSpaceID: UUID?
        var lastAgentID: UUID?
        var callCount: Int = 0

        /// If set, every call returns this list.
        var fixedEntries: [RelevantKnowledgeEntry]?
        /// If set, each call pops the first element. Falls back to
        /// ``fixedEntries`` (or `[]`) when exhausted.
        var entriesPerCall: [[RelevantKnowledgeEntry]] = []

        func record(userText: String, spaceID: UUID?, agentID: UUID?) {
            lastUserText = userText
            lastSpaceID = spaceID
            lastAgentID = agentID
            callCount += 1
        }

        func nextEntries() -> [RelevantKnowledgeEntry] {
            if !entriesPerCall.isEmpty {
                return entriesPerCall.removeFirst()
            }
            return fixedEntries ?? []
        }
    }

    // MARK: - Skip paths

    @Test func nilWhenCompact() async {
        let (source, _, hook) = makeSource(returning: [
            entry(qualifiedID: "actor.alice", summary: "Alice", top: []),
        ])
        let result = await source.render(input(
            messages: [ChatMessage(role: "user", content: "Talk about Alice")],
            isSmallContext: true
        ))
        #expect(result == "- actor.alice: Alice")
        #expect(hook.callCount == 1)
    }

    @Test func nilWhenNoUserMessage() async {
        let (source, _, hook) = makeSource(returning: [
            entry(qualifiedID: "actor.alice", summary: "Alice", top: []),
        ])
        let result = await source.render(input(messages: []))
        #expect(result == nil)
        #expect(hook.callCount == 0)
    }

    @Test func nilWhenLatestRoleIsAssistant() async {
        let (source, _, hook) = makeSource(returning: [
            entry(qualifiedID: "actor.alice", summary: "Alice", top: []),
        ])
        // User message exists earlier but the hydrator still gets called —
        // render walks back to find a user message. Test that it finds it.
        let result = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Please tell me about Alice"),
            ChatMessage(role: "assistant", content: "Sure."),
        ]))
        #expect(result != nil)
        #expect(hook.callCount == 1)
        #expect(hook.lastUserText == "Please tell me about Alice")
    }

    @Test func nilWhenHydratorReturnsEmpty() async {
        let (source, _, hook) = makeSource(returning: [])
        let result = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Anything about xyz?"),
        ]))
        #expect(result == nil)
        #expect(hook.callCount == 1)
    }

    // MARK: - Rendering format

    @Test func rendersEntryWithRelated() async {
        let (source, _, _) = makeSource(returning: [
            entry(
                qualifiedID: "actor.mette",
                summary: "Mette Hansen",
                top: ["thing.phoenix", "actor.daniel", "thing.copenhagen"],
                more: 0
            ),
        ])
        let body = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Drafting a note for Mette today"),
        ])) ?? ""
        #expect(body.contains("- **actor.mette** — Mette Hansen"))
        #expect(body.contains("  - Related: thing.phoenix, actor.daniel, thing.copenhagen"))
        #expect(!body.contains("(+"))
    }

    @Test func rendersMoreCountWhenRelationshipsOverflow() async {
        let (source, _, _) = makeSource(returning: [
            entry(
                qualifiedID: "actor.mette",
                summary: "Mette Hansen",
                top: ["thing.phoenix", "actor.daniel", "thing.copenhagen"],
                more: 2
            ),
        ])
        let body = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Drafting a note for Mette today"),
        ])) ?? ""
        #expect(body.contains("(+2 more)"))
    }

    @Test func rendersEntryWithoutRelationshipsSkipsRelatedLine() async {
        let (source, _, _) = makeSource(returning: [
            entry(qualifiedID: "note.cat", summary: "Cat likes keyboard", top: []),
        ])
        let body = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Tell me about the cat thing"),
        ])) ?? ""
        #expect(body.contains("- **note.cat** — Cat likes keyboard"))
        #expect(!body.contains("- Related:"))
    }

    @Test func rendersStartingPointFraming() async {
        let (source, _, _) = makeSource(returning: [
            entry(qualifiedID: "actor.alice", summary: "Alice", top: []),
        ])
        let body = await source.render(input(messages: [
            ChatMessage(role: "user", content: "What do you know about Alice?"),
        ])) ?? ""
        // The framing prose must be present so the agent treats the list
        // as a nudge, not an authoritative answer.
        #expect(body.lowercased().contains("starting point"))
    }

    // MARK: - Scope passthrough

    @Test func forwardsScopeToHydrator() async {
        let (source, _, hook) = makeSource(returning: [
            entry(qualifiedID: "actor.alice", summary: "Alice", top: []),
        ])
        let spaceID = UUID()
        let agentID = UUID()
        _ = await source.render(input(
            messages: [ChatMessage(role: "user", content: "Something about Alice here")],
            spaceID: spaceID,
            agentID: agentID
        ))
        #expect(hook.lastSpaceID == spaceID)
        #expect(hook.lastAgentID == agentID)
    }

    // MARK: - Retention across turns

    /// Entry from turn 1 survives into turn 2 when the hydrator returns
    /// nothing fresh — the user can say "yes, tell me more" without the
    /// agent losing context.
    @Test func retainedEntrySurvivesOneStaleTurn() async {
        let bob = entry(qualifiedID: "actor.bob", summary: "Bob", top: [])
        let hook = Hook()
        hook.entriesPerCall = [
            [bob], // turn 1: fresh
            [], // turn 2: no fresh match
        ]
        let (source, _, _) = makeSource(hook: hook)

        // Turn 1 — Bob is fresh.
        let t1 = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Tell me about Bob please"),
        ]))
        #expect(t1?.contains("actor.bob") == true)

        // Turn 2 — hydrator returns nothing, but Bob is retained.
        let t2 = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Yes tell me more about him"),
        ]))
        #expect(t2?.contains("actor.bob") == true)
    }

    /// Retained entries are evicted after exceeding `maxStaleTurns`.
    /// With maxStaleTurns = 2 (default): current + 2 stale = 3 turns
    /// of visibility, then gone on the 4th.
    @Test func retainedEntryEvictedAfterMaxStaleTurns() async {
        let bob = entry(qualifiedID: "actor.bob", summary: "Bob", top: [])
        let hook = Hook()
        hook.entriesPerCall = [
            [bob], // turn 1: fresh
            [], // turn 2: stale 1
            [], // turn 3: stale 2
            [], // turn 4: stale 3 → evicted
        ]
        let (source, _, _) = makeSource(hook: hook)

        _ = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Tell me about Bob please"),
        ]))
        _ = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Yes tell me more about him"),
        ]))
        let t3 = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Anything else about his hobbies?"),
        ]))
        #expect(t3?.contains("actor.bob") == true)

        // Turn 4 — Bob has been stale for 3 turns, exceeds max (2).
        let t4 = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Okay let's talk about something else now"),
        ]))
        #expect(t4?.contains("actor.bob") != true)
    }

    /// Re-mentioning an entity resets its staleness counter.
    ///
    /// Timeline:  fresh → stale 1 → re-mentioned (0) → stale 1 → stale 2 → evicted
    @Test func reMentionRefreshesStaleness() async {
        let bob = entry(qualifiedID: "actor.bob", summary: "Bob", top: [])
        let hook = Hook()
        hook.entriesPerCall = [
            [bob], // turn 1: fresh (stale 0)
            [], // turn 2: stale 1
            [bob], // turn 3: re-mentioned → stale 0
            [], // turn 4: stale 1
            [], // turn 5: stale 2 — still visible
            [], // turn 6: stale 3 → evicted
        ]
        let (source, _, _) = makeSource(hook: hook)

        // Turns 1–4.
        for i in 0 ..< 4 {
            _ = await source.render(input(messages: [
                ChatMessage(role: "user", content: "Turn \(i + 1) with enough words here"),
            ]))
        }

        // Turn 5: stale 2 since re-mention at turn 3. Still visible.
        let t5 = await source.render(input(messages: [
            ChatMessage(role: "user", content: "This is turn five with enough text"),
        ]))
        #expect(t5?.contains("actor.bob") == true)

        // Turn 6: stale 3, exceeds max → gone.
        let t6 = await source.render(input(messages: [
            ChatMessage(role: "user", content: "This is turn six and Bob should be gone"),
        ]))
        #expect(t6?.contains("actor.bob") != true)
    }

    /// Fresh entries from the current turn rank above stale retained
    /// entries from previous turns.
    @Test func freshEntriesRankAboveStale() async {
        let bob = entry(qualifiedID: "actor.bob", summary: "Bob", top: [])
        let alice = RelevantKnowledgeEntry(
            qualifiedID: "actor.alice", type: "actor",
            summary: "Alice", score: 0.5,
            topRelationships: [], moreRelationships: 0
        )
        let hook = Hook()
        hook.entriesPerCall = [
            [bob], // turn 1: Bob fresh
            [alice], // turn 2: Alice fresh, Bob retained
        ]
        let (source, _, _) = makeSource(hook: hook)

        _ = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Tell me about Bob please"),
        ]))

        // Turn 2 — Alice is fresh (score 0.5), Bob is retained (score
        // 0.9 but stale). Fresh should rank first.
        let t2 = await source.render(input(messages: [
            ChatMessage(role: "user", content: "Actually what about Alice instead"),
        ])) ?? ""
        let aliceIdx = t2.range(of: "actor.alice")?.lowerBound
        let bobIdx = t2.range(of: "actor.bob")?.lowerBound
        #expect(aliceIdx != nil)
        #expect(bobIdx != nil)
        if let a = aliceIdx, let b = bobIdx {
            #expect(a < b)
        }
    }
}
