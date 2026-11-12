import Foundation

/// Forwards task cancellation to the host operation and adapts its errors.
func withCancellation<Value: Sendable>(
    cancel: @escaping @Sendable () -> Void,
    mapError: @Sendable (any Error) -> any Error = { $0 },
    work: () async throws -> Value
) async throws -> Value {
    try await withTaskCancellationHandler {
        try Task.checkCancellation()
        do {
            let value = try await work()
            try Task.checkCancellation()
            return value
        } catch {
            throw mapError(error)
        }
    } onCancel: { cancel() }
}
