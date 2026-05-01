import UIKit

/// Requests OS background time so an in-flight stream can finish or checkpoint
/// before the app is suspended. Call `begin()` when entering background and
/// `end()` when the stream completes or the app returns to foreground.
@MainActor
final class BackgroundTaskGuard {
    private var taskID: UIBackgroundTaskIdentifier = .invalid
    private var monitor: Task<Void, Never>?
    private let onExpiring: @MainActor () -> Void

    init(onExpiring: @escaping @MainActor () -> Void) {
        self.onExpiring = onExpiring
    }

    func begin() {
        guard taskID == .invalid else { return }

        taskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor in
                self?.expire()
            }
        }

        guard taskID != .invalid else { return }

        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, taskID != .invalid else { return }
                if UIApplication.shared.backgroundTimeRemaining < 5 {
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

    private func expire() {
        onExpiring()
        end()
    }
}
