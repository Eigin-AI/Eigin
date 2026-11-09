import Foundation

/// Terminal failures that must remain distinct from a successful empty response.
enum StreamCompletionError: Error {
    case interrupted
    case outputLimit
    case policyStop
    case invalidToolCall
}
