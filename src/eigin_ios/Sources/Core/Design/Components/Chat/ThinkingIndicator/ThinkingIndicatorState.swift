import SwiftUI

/// Presentation state for the thinking indicator inside a chat feed.
///
/// Owns the indicator's lifecycle bits: the delayed show-gate that keeps
/// fast responses from flashing it, and the thinking clock that pauses
/// while the turn waits on the user.
@MainActor
@Observable
final class ThinkingIndicatorState {
    /// Render gate: set once the appearance delay has survived.
    private(set) var isShown = false
    /// When the current appearance began — anchors the indicator's timeline.
    private(set) var shownAt: Date?
    /// When the current thinking stretch began; nil while the turn is
    /// parked waiting on the user.
    private(set) var clockStart: Date?
    /// Thinking seconds accumulated before the current stretch.
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

    /// Parks the thinking clock when the turn waits on the user; restarts
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
