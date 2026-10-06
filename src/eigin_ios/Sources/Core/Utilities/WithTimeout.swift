import Foundation

/// Races an operation against a timeout. Returns the operation's result,
/// or `nil` when the timeout elapsed first. The losing task is cancelled —
/// operations should check for cancellation at their suspension points.
func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
