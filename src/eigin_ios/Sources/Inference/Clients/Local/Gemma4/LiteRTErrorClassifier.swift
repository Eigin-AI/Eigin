import Foundation
@preconcurrency import LiteRTLM

/// Classifies opaque LiteRT-LM generation errors into the recovery cases the
/// runtime knows how to handle.
///
/// LiteRT surfaces several failure modes as wrapped enums or free-form strings
/// (the C++ core's messages). This pure classifier centralises that brittle
/// matching so it has one home and focused tests, rather than being scattered
/// through `GemmaRuntime`. It will need revisiting when the LiteRT version bumps
/// — the tests pin the strings we depend on so that breakage is loud.
enum LiteRTErrorClassifier {
    /// A recognised, recoverable failure mode.
    enum Classification: Equatable {
        /// The history is too long for the context window — drop oldest turns.
        case contextOverflow
        /// The model called an invalid or unregistered tool. Carries the
        /// attempted name (or "unknown" when it can't be extracted).
        case unknownToolCall(name: String)
    }

    /// Returns the recovery classification for `error`, or `nil` if it isn't one
    /// of the modes we handle specially (caller treats `nil` as a hard failure).
    static func classify(_ error: Error) -> Classification? {
        if isContextOverflow(error) {
            return .contextOverflow
        }
        if let name = unknownToolCallName(error) {
            return .unknownToolCall(name: name)
        }
        return nil
    }

    /// True when the error is a LiteRT context-window overflow.
    static func isContextOverflow(_ error: Error) -> Bool {
        // LiteRT surfaces this as a string error containing "too long" or
        // "Exceeding the maximum number of tokens".
        let msg = error.localizedDescription
        return msg.contains("too long") || msg.contains("maximum number of tokens")
    }

    /// If the error is a bad/unknown tool call, returns the attempted name (or
    /// "unknown" when it can't be extracted). Returns `nil` otherwise.
    static func unknownToolCallName(_ error: Error) -> String? {
        // Tool name genuinely not in ToolManager's registry.
        if case LiteRTLMError.tool(.notFound(let name)) = error {
            return name
        }
        // toolExecutionError wraps notFound from older LiteRT versions.
        if case LiteRTLMError.conversation(.toolExecutionError(let name, let errStr)) = error,
           errStr.contains("not found") || errStr.contains("notFound")
        {
            return name
        }
        // LiteRT's C++ FC parser failed — model emitted a syntactically invalid
        // or unrecognised tool call (e.g. "google:search"). Extract the attempted
        // name from the error message so we can tell the model what went wrong.
        if case LiteRTLMError.conversation(.invalidResponse(let msg)) = error,
           msg.contains("Failed to parse tool calls")
        {
            return extractToolNameFromParseError(msg) ?? "unknown"
        }
        return nil
    }

    /// Extracts the tool name from LiteRT's FC parse error string.
    /// e.g. "...call:google:search{...}" → "google:search"
    static func extractToolNameFromParseError(_ msg: String) -> String? {
        guard let callRange = msg.range(of: "call:") else { return nil }
        let after = msg[callRange.upperBound...]
        guard let braceIdx = after.firstIndex(of: "{") else { return nil }
        let name = String(after[after.startIndex ..< braceIdx])
        return name.isEmpty ? nil : name
    }
}
