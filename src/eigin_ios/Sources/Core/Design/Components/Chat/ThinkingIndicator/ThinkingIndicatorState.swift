import SwiftUI

/// What the agent is doing while the indicator is up — selects the copy
/// shown next to the blob.
public enum ThinkingActivity: Equatable {
    /// Waiting for model output.
    case thinking
    /// Forming or executing tool calls.
    case working
    /// Preparing something outside the chat turn (e.g. onboarding wrap-up).
    case preparing
}

/// Presentation state for the thinking indicator inside a chat feed.
///
/// Owns the indicator's lifecycle bits: the delayed show-gate that keeps
/// fast responses from flashing it, the activity the copy ladder follows,
/// and the activity clock that restarts when the activity changes and
/// pauses while the turn waits on the user.
@MainActor
@Observable
final class ThinkingIndicatorState {
    /// Render gate: set once the appearance delay has survived.
    private(set) var isShown = false
    /// When the current appearance began — anchors the indicator's timeline.
    private(set) var shownAt: Date?
    /// What the agent is currently doing; selects the copy ladder.
    private(set) var activity: ThinkingActivity = .thinking
    /// When the current activity stretch began; nil while the turn is
    /// parked waiting on the user.
    private(set) var clockStart: Date?
    /// Activity seconds accumulated before the current stretch.
    private(set) var priorElapsed: TimeInterval = 0

    private var appearanceTask: Task<Void, Never>?

    /// Elapsed thinking time at `date`, ignoring paused stretches.
    func elapsed(at date: Date) -> TimeInterval {
        (clockStart.map { date.timeIntervalSince($0) } ?? 0) + priorElapsed
    }

    /// Shows a fresh indicator after a short delay — so fast responses never
    /// flash it — or hides it and forgets it immediately.
    func setShown(_ shown: Bool) {
        appearanceTask?.cancel()
        appearanceTask = nil
        isShown = false
        shownAt = nil
        clockStart = nil
        priorElapsed = 0
        guard shown else { return }

        appearanceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            shownAt = Date.now
            clockStart = shownAt
            isShown = true
        }
    }

    /// Switches what the agent is doing and restarts its copy ladder,
    /// without touching the appearance gate or the blob's timeline —
    /// activity swaps must never hide or re-anchor the indicator.
    func setActivity(_ newActivity: ThinkingActivity) {
        guard newActivity != activity else { return }
        activity = newActivity
        // While hidden the next appearance re-anchors the clock anyway.
        guard shownAt != nil else { return }
        priorElapsed = 0
        clockStart = .now
    }

    /// Parks the activity clock when the turn waits on the user; restarts
    /// it when the turn resumes, preserving accumulated time.
    func setStalled(_ stalled: Bool) {
        if stalled {
            if let clockStart {
                priorElapsed += Date.now.timeIntervalSince(clockStart)
                self.clockStart = nil
            }
        } else if shownAt != nil {
            clockStart = .now
        }
    }
}
