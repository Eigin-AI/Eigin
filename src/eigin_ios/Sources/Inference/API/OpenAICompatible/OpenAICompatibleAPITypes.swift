import Foundation

/// Response from the `/models` endpoint, containing a list of available model entries.
struct ModelsResponse: Decodable {
    let data: [ModelEntry]

    struct ModelEntry: Decodable {
        let id: String
    }
}

/// Request body for the `/chat/completions` endpoint.
struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    var maxTokens: Int?
    var tools: [ToolDefinition]?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools
        case maxTokens = "max_tokens"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(tools, forKey: .tools)
    }
}

/// Non-streaming chat completion response, used for API key validation.
struct ChatCompletionResponse: Decodable {
    let id: String
}

/// An inline error returned inside the SSE data stream (HTTP 200 with error body).
/// Standard OpenAI error envelope: `{"error": {"message": "...", "type": "..."}}`.
struct StreamErrorResponse: Decodable {
    let error: ErrorBody

    struct ErrorBody: Decodable {
        let message: String
        let type: String
    }
}

/// A single server-sent event chunk from a streamed chat completion response.
struct ChatCompletionChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let toolCalls: [ToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }
}
