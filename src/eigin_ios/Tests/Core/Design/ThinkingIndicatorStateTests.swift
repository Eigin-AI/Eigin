@testable import Eigin
import Testing

@MainActor
struct ThinkingIndicatorStateTests {
    /// The show-gate delays appearance by 500ms.
    private func appear(_ state: ThinkingIndicatorState) async throws {
        state.setShown(true)
        try await Task.sleep(for: .milliseconds(600))
        #expect(state.isShown)
    }

    @Test func setActivitySwapsLadderWithoutReanchoring() async throws {
        let state = ThinkingIndicatorState()
        try await appear(state)
        let shownAt = try #require(state.shownAt)

        state.setActivity(.working)

        #expect(state.isShown)
        #expect(state.shownAt == shownAt)
        #expect(state.activity == .working)
    }

    @Test func setActivityRestartsLadderClock() async throws {
        let state = ThinkingIndicatorState()
        try await appear(state)
        let shownAt = try #require(state.shownAt)

        state.setActivity(.working)

        #expect(state.activity == .working)
        #expect(state.priorElapsed == 0)
        // The activity clock restarts from now, not from the appearance.
        #expect(try #require(state.clockStart) != shownAt)
    }

    @Test func setActivityWhileHiddenDoesNotShow() {
        let state = ThinkingIndicatorState()
        state.setActivity(.working)

        #expect(!state.isShown)
        #expect(state.shownAt == nil)
        #expect(state.activity == .working)
    }

    @Test func stallParksActivityClockAndResumeRestarts() async throws {
        let state = ThinkingIndicatorState()
        try await appear(state)
        state.setActivity(.working)
        try await Task.sleep(for: .milliseconds(20))

        state.setStalled(true)

        #expect(state.clockStart == nil)
        #expect(state.priorElapsed > 0)

        state.setStalled(false)

        #expect(state.clockStart != nil)
        #expect(state.priorElapsed > 0)
    }
}

struct WorkingCopyTests {
    @Test func silentBeforeFirstThreshold() {
        #expect(WorkingCopy.stage(at: 0) == nil)
        #expect(WorkingCopy.stage(at: 4.4) == nil)
    }

    @Test func transitionsOnThresholds() {
        #expect(WorkingCopy.stage(at: WorkingCopy.thresholds[0]) == .working)
        #expect(WorkingCopy.stage(at: WorkingCopy.thresholds[1]) == .stillWorking)
        #expect(WorkingCopy.stage(at: WorkingCopy.thresholds[2]) == .takingAWhile)
        #expect(WorkingCopy.stage(at: WorkingCopy.thresholds[3]) == .sorryForTheWait)
    }

    @Test func staysOnLastRung() {
        #expect(WorkingCopy.stage(at: 120) == .sorryForTheWait)
    }

    @Test func rungsMatchThresholdCount() {
        #expect(WorkingCopy.allCases.count == WorkingCopy.thresholds.count)
    }
}
