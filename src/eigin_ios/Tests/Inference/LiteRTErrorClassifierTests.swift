@testable import Eigin
import LiteRTLM
import Testing

/// Pins the brittle string/enum matching ``LiteRTErrorClassifier`` relies on so
/// breakage on a LiteRT version bump is loud rather than silent.
@Suite("LiteRT error classifier")
struct LiteRTErrorClassifierTests {
    @Test("Context overflow: 'too long' message")
    func contextOverflowTooLong() {
        let error = LiteRTLMError.conversation(
            .invalidResponse("Input prompt is too long for the context window.")
        )
        #expect(LiteRTErrorClassifier.classify(error) == .contextOverflow)
        #expect(LiteRTErrorClassifier.isContextOverflow(error))
    }

    @Test("Context overflow: 'maximum number of tokens' message")
    func contextOverflowMaxTokens() {
        let error = LiteRTLMError.conversation(
            .invalidResponse("Exceeding the maximum number of tokens allowed.")
        )
        #expect(LiteRTErrorClassifier.classify(error) == .contextOverflow)
    }

    @Test("Unknown tool: ToolError.notFound")
    func unknownToolNotFound() {
        let error = LiteRTLMError.tool(.notFound(name: "calendar_add"))
        #expect(LiteRTErrorClassifier.classify(error) == .unknownToolCall(name: "calendar_add"))
    }

    @Test("Unknown tool: toolExecutionError wrapping 'not found'")
    func unknownToolExecutionWrapsNotFound() {
        let error = LiteRTLMError.conversation(
            .toolExecutionError(name: "reminders_add", error: "tool not found in registry")
        )
        #expect(LiteRTErrorClassifier.classify(error) == .unknownToolCall(name: "reminders_add"))
    }

    @Test("Unknown tool: FC parse error extracts call name")
    func unknownToolParseErrorExtractsName() {
        let error = LiteRTLMError.conversation(
            .invalidResponse("Failed to parse tool calls: <|tool_call>call:google:search{q:1}")
        )
        #expect(
            LiteRTErrorClassifier.classify(error) == .unknownToolCall(name: "google:search")
        )
    }

    @Test("Unknown tool: FC parse error with no extractable name falls back")
    func unknownToolParseErrorFallback() {
        let error = LiteRTLMError.conversation(
            .invalidResponse("Failed to parse tool calls: garbled output")
        )
        #expect(LiteRTErrorClassifier.classify(error) == .unknownToolCall(name: "unknown"))
    }

    @Test("toolExecutionError without 'not found' is not classified")
    func toolExecutionErrorOtherIsUnclassified() {
        let error = LiteRTLMError.conversation(
            .toolExecutionError(name: "web_fetch", error: "network timeout")
        )
        #expect(LiteRTErrorClassifier.classify(error) == nil)
    }

    @Test("Unrelated error is not classified")
    func unrelatedErrorIsNil() {
        let error = LiteRTLMError.engine(.notInitialized)
        #expect(LiteRTErrorClassifier.classify(error) == nil)
        #expect(!LiteRTErrorClassifier.isContextOverflow(error))
        #expect(LiteRTErrorClassifier.unknownToolCallName(error) == nil)
    }

    @Test("extractToolNameFromParseError parses call:NAME{ form")
    func extractName() {
        #expect(
            LiteRTErrorClassifier.extractToolNameFromParseError("...call:web_search{q:x}")
                == "web_search"
        )
        #expect(LiteRTErrorClassifier.extractToolNameFromParseError("no call here") == nil)
        #expect(LiteRTErrorClassifier.extractToolNameFromParseError("call:{empty}") == nil)
    }
}
