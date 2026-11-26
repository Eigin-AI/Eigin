import EiginSDK
import Foundation

/// Maps host errors and prompt hints at the SDK turn-policy boundary.
enum ChatTurnErrorConversion {
    typealias SDK = EiginSDK.Experimental.Agent

    static func failure(_ error: Error) -> SDK.TurnFailure {
        if let error = error as? TurnCompletionError, case .missingReply = error {
            return .missingReply
        }
        if let error = error as? StreamCompletionError, case .interrupted = error {
            return .interruption
        }
        if let error = error as? ResponsesAPIError, case .interruptedStream = error {
            return .interruption
        }
        if let error = error as? URLError,
           error.code == .timedOut || error.code == .networkConnectionLost
        {
            return .interruption
        }
        return .terminal
    }

    static func restore(_ error: any Error, errors: RequestHostErrors) -> any Error {
        guard let failure = error as? SDK.ChatFailure else { return errors.restore(error) }
        switch failure {
        case .MissingReply: return TurnCompletionError.missingReply
        case .Round(.Interrupted): return StreamCompletionError.interrupted
        case .Round(.InvalidToolCall): return StreamCompletionError.invalidToolCall
        case .Cancelled: return CancellationError()
        case .Request(let request): return errors.restore(request)
        default: return error
        }
    }

    static func instruction(_ reason: SDK.Continuation) -> String {
        switch reason {
        case .missingReply: Prompt.Hints.Continuation.missingReply
        case .interrupted: Prompt.Hints.Continuation.interrupted
        }
    }
}
