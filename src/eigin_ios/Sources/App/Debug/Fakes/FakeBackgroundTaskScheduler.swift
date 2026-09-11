#if DEBUG || EIGIN_DEV
import BackgroundTasks

/// A fake `BackgroundTaskScheduling` that records calls and exposes pending requests for
/// assertions.
final class FakeBackgroundTaskScheduler: BackgroundTaskScheduling, @unchecked Sendable {
    private let lock = NSLock()

    private var _cancelledIdentifiers: [String] = []
    private var _submittedRequests: [BGTaskRequest] = []
    private var _pendingRequests: [BGTaskRequest] = []

    // MARK: - BackgroundTaskScheduling

    func cancel(taskRequestWithIdentifier identifier: String) {
        lock.withLock {
            _cancelledIdentifiers.append(identifier)
            _pendingRequests.removeAll { $0.identifier == identifier }
        }
    }

    func submit(_ taskRequest: BGTaskRequest) throws {
        lock.withLock {
            _submittedRequests.append(taskRequest)
            _pendingRequests.append(taskRequest)
        }
    }

    func pendingTaskRequests() async -> [BGTaskRequest] {
        lock.withLock { _pendingRequests }
    }

    // MARK: - Test helpers

    var cancelledIdentifiers: [String] {
        lock.withLock { _cancelledIdentifiers }
    }

    var submittedRequests: [BGTaskRequest] {
        lock.withLock { _submittedRequests }
    }

    /// Inject a pre-existing pending request (simulates an already-scheduled task).
    func addPendingRequest(_ request: BGTaskRequest) {
        lock.withLock {
            _pendingRequests.append(request)
        }
    }
}
#endif
