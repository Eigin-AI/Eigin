import UIKit

/// Requests OS background time so an in-flight stream can finish or checkpoint
/// before the app is suspended. Call `begin()` when entering background and
/// `end()` when the stream completes or the app returns to foreground.
@MainActor
final class BackgroundTaskGuard {
    /// Remaining time below which the budget counts as expiring.
    private static let expiringThreshold: TimeInterval = 5

    private var taskID: UIBackgroundTaskIdentifier = .invalid
    private var monitor: Task<Void, Never>?
    private var didExpire = false
    private let onExpiring: @MainActor () -> Void
    /// The OS countdown, injectable so tests can drive expiry without UIKit
    /// background-time mechanics.
    private let remainingTime: () -> TimeInterval

    init(
        onExpiring: @escaping @MainActor () -> Void,
        remainingTime: @escaping () -> TimeInterval = {
            UIApplication.shared.backgroundTimeRemaining
        }
    ) {
        self.onExpiring = onExpiring
        self.remainingTime = remainingTime
    }

    func begin() {
        guard taskID == .invalid else { return }

        taskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor in
                self?.expire()
            }
        }

        guard taskID != .invalid else { return }

        didExpire = false
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, taskID != .invalid else { return }
                if remainingTime() < Self.expiringThreshold {
                    expire()
                    return
                }
            }
        }
    }

    func end() {
        monitor?.cancel()
        monitor = nil
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }

    /// Fires `onExpiring` exactly once per budget at most — the watchdog and
    /// the OS expiration handler can both race to get here.
    private func expire() {
        guard !didExpire else { return }
        didExpire = true
        onExpiring()
        end()
    }
}
