@testable import Eigin
import Foundation
import Testing

@Suite("Initiative intent rotation")
struct InitiativeIntentRotationTests {
    // MARK: - Helpers

    private func snapshot(id: UUID = UUID(), content: String = "Goal") -> IntentSnapshot {
        IntentSnapshot(
            id: id,
            content: content,
            status: .active,
            tasks: [],
            events: [],
            schedules: [],
            createdAt: .now,
            updatedAt: .now
        )
    }

    // MARK: - Tests

    @Test func emptyPoolReturnsNoFocus() {
        let selection = InitiativeIntentRotation.select(rankedIntents: [], history: [])
        #expect(selection.focus == nil)
        #expect(selection.history.isEmpty)
    }

    @Test func neverFocusedIntentIsPreferredByRank() {
        let a = snapshot(content: "top")
        let b = snapshot(content: "second")
        // "a" ranked first, "b" second, neither has been focused before.
        let selection = InitiativeIntentRotation.select(rankedIntents: [a, b], history: [])
        #expect(selection.focus?.id == a.id)
        #expect(selection.history == [a.id])
    }

    @Test func cyclesThroughAllBeforeRepeating() throws {
        let a = snapshot()
        let b = snapshot()
        let c = snapshot()
        let ranked = [a, b, c]

        var history: [UUID] = []
        var focusedOrder: [UUID] = []
        for _ in 0 ..< 3 {
            let selection = InitiativeIntentRotation.select(rankedIntents: ranked, history: history)
            try focusedOrder.append(#require(selection.focus?.id))
            history = selection.history
        }

        // Each intent got exactly one turn before any repeats.
        #expect(Set(focusedOrder) == Set([a.id, b.id, c.id]))
        #expect(focusedOrder == [a.id, b.id, c.id])
    }

    @Test func leastRecentlyFocusedIsChosenOnceAllHaveHadATurn() {
        let a = snapshot()
        let b = snapshot()
        let ranked = [a, b]

        // Both already focused, "a" longest ago.
        let history = [a.id, b.id]
        let selection = InitiativeIntentRotation.select(rankedIntents: ranked, history: history)
        #expect(selection.focus?.id == a.id)
        // History rotates: "a" moves to the back.
        #expect(selection.history == [b.id, a.id])
    }

    @Test func singleIntentIsAlwaysSelected() {
        let only = snapshot()
        var history: [UUID] = []
        for _ in 0 ..< 4 {
            let selection = InitiativeIntentRotation.select(rankedIntents: [only], history: history)
            #expect(selection.focus?.id == only.id)
            history = selection.history
        }
        #expect(history == [only.id])
    }

    @Test func historyPrunesIntentsNoLongerActive() {
        let a = snapshot()
        let b = snapshot()
        // History references a stale intent no longer in the active pool.
        let stale = UUID()
        let selection = InitiativeIntentRotation.select(
            rankedIntents: [a, b], history: [stale, a.id]
        )
        // "b" has never been focused among the active pool, so it wins.
        #expect(selection.focus?.id == b.id)
        #expect(!selection.history.contains(stale))
    }
}
