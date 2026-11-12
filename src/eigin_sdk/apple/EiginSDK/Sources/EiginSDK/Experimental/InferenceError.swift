import EiginSDKBindings
import Foundation

/// Preserves cancellation and URLSession error categories for host routing and presentation.
func inferenceError(_ error: any Error) -> any Error {
    if case InferenceError.Cancelled = error { return CancellationError() }
    if case let InferenceError.Transport(reason, domain, code) = error,
       domain == NSURLErrorDomain, let code
    {
        return URLError(URLError.Code(rawValue: Int(code)), userInfo: [NSLocalizedDescriptionKey: reason])
    }
    return error
}
