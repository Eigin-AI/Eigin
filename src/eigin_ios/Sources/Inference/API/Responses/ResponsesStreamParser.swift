import Foundation

/// Maps Responses API SSE payloads onto ``ChatStreamEvent`` — the same
/// downstream contract as ``OpenAICompatibleClient``.
///
/// Events are complete here (no delta accumulation like chat completions):
/// text arrives as `response.output_text.delta`, and tool calls arrive whole
/// in `response.output_item.done` items.
enum ResponsesStreamParser {
    /// Decodes one `data:` payload and feeds it to the consumer. Returns
    /// `true` when the turn is complete and the stream should finish.
    static func apply(
        _ event: ResponsesStreamEvent,
        to continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation,
        hasToolCalls: inout Bool
    ) throws -> Bool {
        switch event.type {
        case "response.output_text.delta":
            if let delta = event.delta, !delta.isEmpty {
                continuation.yield(.contentDelta(delta))
            }
        case "response.output_item.done":
            if let item = event.item, item.type == "function_call" {
                hasToolCalls = true
                continuation.yield(.toolCall(ToolCall(
                    id: item.callID ?? UUID().uuidString,
                    type: "function",
                    function: .init(
                        name: item.name ?? "",
                        arguments: item.arguments ?? ""
                    )
                )))
            }
        case "response.completed":
            continuation.yield(.finished(hasToolCalls ? .toolCalls : .stop))
            return true
        case "response.failed":
            throw error(from: event)
        case "error":
            throw error(from: event)
        default:
            // Reasoning deltas, item addition events, usage events — pass.
            break
        }
        return false
    }

    /// One mapper for both error shapes: `response.failed` carries an
    /// envelope, bare `error` events carry inline `code`/`message`.
    static func error(
        from event: ResponsesStreamEvent,
        statusHint: Int = 0
    ) -> ResponsesAPIError {
        if let envelopeError = event.response?.error {
            return ResponsesAPIError.make(statusCode: statusHint, body: encoded(envelopeError))
        }
        if let code = event.code {
            let body = "{\"code\":\(jsonString(code)),\"param\":\(jsonString(event.message ?? ""))}"
            return ResponsesAPIError.make(statusCode: statusHint, body: body)
        }
        return .httpError(statusHint, body: event.message)
    }

    /// Re-encodes an envelope error so ``ResponsesAPIError``'s body scanner
    /// sees subscription codes in one place.
    private static func encoded(_ apiError: ResponsesStreamEvent.ResponseEnvelope
        .APIError) -> String?
    {
        switch (apiError.code, apiError.param) {
        case (let code?, let param?):
            """
            {"code":\(jsonString(code)),"param":\(jsonString(param))}
            """
        case (let code?, nil):
            code
        case (nil, let param?):
            param
        default:
            apiError.message
        }
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value) else {
            return "\"\(value)\""
        }
        return String(data: data, encoding: .utf8) ?? "\"\(value)\""
    }
}
