import EiginSDK
import Foundation

/// Maps host errors and prompt hints at the SDK turn-policy boundary.
enum TurnSDKConversion {
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

    static func instruction(_ reason: SDK.Continuation) -> String {
        switch reason {
        case .missingReply: Prompt.Hints.Continuation.missingReply
        case .interrupted: Prompt.Hints.Continuation.interrupted
        }
    }
}
