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
    let messages: [ChatCompletionMessage]
    let stream: Bool
    var maxTokens: Int?
    var tools: [ToolDefinition]?
    var promptCacheKey: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools
        case maxTokens = "max_tokens"
        case promptCacheKey = "prompt_cache_key"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(promptCacheKey, forKey: .promptCacheKey)
    }
}

// MARK: - Wire message (image-aware)

/// Content value for an OpenAI-compatible chat message: plain text for ordinary
/// messages, or a list of typed parts when the message carries image attachments.
enum ChatMessageContent: Encodable {
    case text(String)
    case parts([ContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }

    /// A single part of a multi-part message content array (text or image).
    struct ContentPart: Encodable {
        var type: String
        var text: String?
        var imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }

        struct ImageURL: Encodable {
            let url: String
            let detail: String
        }

        static func text(_ text: String) -> ContentPart {
            ContentPart(type: "text", text: text)
        }

        static func image(dataURL: String) -> ContentPart {
            ContentPart(type: "image_url", imageURL: ImageURL(url: dataURL, detail: "high"))
        }
    }
}

/// Wire-format counterpart to ``ChatMessage`` for the `/chat/completions` endpoint.
///
/// ``ChatMessage`` deliberately excludes attachments from its own `Codable`
/// conformance (see its doc comment) since the wire representation of an image
/// differs per provider. This type resolves a message's attachments into inline
/// base64 content parts at construction time, so the request can be encoded in a
/// single pass — no post-hoc JSON patching needed.
struct ChatCompletionMessage: Encodable {
    let role: String
    let content: ChatMessageContent?
    let toolCallID: String?
    let name: String?
    let toolCalls: [ToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
    }

    /// Builds the wire message for `message`. Image attachments are loaded from
    /// `store` and inlined as base64 data URLs; when there are none (or none of
    /// their bytes could be loaded), `content` falls back to plain text.
    init(_ message: ChatMessage, store: any ChatAttachmentStoring) {
        role = message.role
        toolCallID = message.toolCallID
        name = message.name
        toolCalls = message.toolCalls

        guard let attachments = message.attachments, !attachments.isEmpty else {
            content = message.content.map(ChatMessageContent.text)
            return
        }

        var parts: [ChatMessageContent.ContentPart] = []
        if let text = message.content, !text.isEmpty {
            parts.append(.text(text))
        }
        for attachment in attachments where attachment.kind == .image {
            guard let data = store.load(id: attachment.id) else { continue }
            let dataURL = "data:\(attachment.mimeType);base64,\(data.base64EncodedString())"
            parts.append(.image(dataURL: dataURL))
        }

        content = parts.isEmpty ? message.content.map(ChatMessageContent.text) : .parts(parts)
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
