import EiginSDKBindings
import Foundation

/// Connects Swift task cancellation to an SDK operation and preserves host error categories.
func withInferenceCancellation<Value: Sendable>(
    cancel: @escaping @Sendable () -> Void,
    work: () async throws -> Value
) async throws -> Value {
    try await withTaskCancellationHandler {
        try Task.checkCancellation()
        do {
            let value = try await work()
            try Task.checkCancellation()
            return value
        } catch {
            throw hostError(error)
        }
    } onCancel: { cancel() }
}

/// Preserve URLSession error categories used by host routing and error presentation.
private func hostError(_ error: any Error) -> any Error {
    if case InferenceError.Cancelled = error { return CancellationError() }
    if case let InferenceError.Transport(reason, domain, code) = error,
       domain == NSURLErrorDomain, let code
    {
        return URLError(URLError.Code(rawValue: Int(code)), userInfo: [NSLocalizedDescriptionKey: reason])
    }
    return error
}
