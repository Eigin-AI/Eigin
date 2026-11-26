import EiginSDK
import Foundation

/// Retains original app errors while Rust carries their routing classification and identity.
final class RequestHostErrors: @unchecked Sendable {
    private typealias SDK = EiginSDK.Experimental.Inference
    private let lock = NSLock()
    private var errors: [String: any Error] = [:]

    func encode(_ error: any Error) -> EiginSDK.Experimental.Inference.RequestFailure {
        if error is CancellationError { return .Inference(.Cancelled) }
        let id = UUID().uuidString
        lock.withLock { errors[id] = error }
        return .Host(
            id: id, message: error.localizedDescription,
            failure: RoutingSDKConversion.failure(RoutingFailure(from: error))
        )
    }

    func restore(_ error: any Error) -> any Error {
        guard let failure = error as? SDK.RequestFailure else { return error }
        switch failure {
        case .Host(let id, _, _):
            return lock.withLock { errors[id] } ?? error
        case .Inference(let underlying), .Classified(let underlying, _):
            return InferenceSDKConversion.error(underlying)
        case .FirstEventTimeout: return FirstEventTimeout()
        case .NoUsefulOutput: return StreamEndedWithoutUsefulOutput()
        case .BufferOverflow: return PreWinnerBufferOverflow()
        case .InvalidToolCall: return StreamCompletionError.invalidToolCall
        case .MissingReply: return TurnCompletionError.missingReply
        }
    }
}
