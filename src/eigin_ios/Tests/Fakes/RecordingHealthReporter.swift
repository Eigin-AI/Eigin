@testable import Eigin
import Foundation

/// Records ``IntegrationHealthReporter`` calls so provider tests can assert
/// that auth-death sites flag their integration for reconnect. Records
/// synchronously on the calling isolation, so asserts never race the async
/// hop the real monitor makes.
final class RecordingHealthReporter: IntegrationHealthReporter, @unchecked Sendable {
    private let lock = NSLock()
    private var markedIDs: [UUID] = []

    nonisolated func markNeedsReconnect(_ integrationID: UUID) {
        lock.withLock { markedIDs.append(integrationID) }
    }

    /// The ids reported as needing a reconnect, in call order.
    var marked: [UUID] {
        lock.withLock { markedIDs }
    }
}
