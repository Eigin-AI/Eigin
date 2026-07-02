import Foundation

// MARK: - Request Types

/// Top-level request body for the Anthropic Messages API.
struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let cacheControl: CacheControl?
    let system: String?
    let messages: [AnthropicMessage]
    let tools: [AnthropicToolDefinition]?
    let stream: Bool

    struct CacheControl: Encodable {
        let type: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case cacheControl = "cache_control"
        case system, messages, tools, stream
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
        try container.encodeIfPresent(system, forKey: .system)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encode(stream, forKey: .stream)
    }
}

/// A single message in Anthropic's format (role + content).
struct AnthropicMessage: Encodable {
    let role: String
    let content: AnthropicContent

    /// Content is either a plain string or an array of content blocks.
    enum AnthropicContent: Encodable {
        case text(String)
        case blocks([AnthropicContentBlock])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .blocks(let blocks):
                try container.encode(blocks)
            }
        }
    }
}

/// A content block within an Anthropic message.
enum AnthropicContentBlock: Encodable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case toolResult(toolUseID: String, content: String)
    case image(mediaType: String, data: String)

    private enum BlockType: String, Encodable {
        case text
        case toolUse = "tool_use"
        case toolResult = "tool_result"
        case image
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, source
        case toolUseID = "tool_use_id"
        case content
    }

    private enum ImageSourceCodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(BlockType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode(BlockType.toolUse, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content):
            try container.encode(BlockType.toolResult, forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
        case .image(let mediaType, let data):
            try container.encode(BlockType.image, forKey: .type)
            // Encodes as: { "type": "image", "source": { "type": "base64", "media_type": "...",
            // "data": "..." } }
            var sourceContainer = container.nestedContainer(
                keyedBy: ImageSourceCodingKeys.self,
                forKey: .source
            )
            try sourceContainer.encode("base64", forKey: .type)
            try sourceContainer.encode(mediaType, forKey: .mediaType)
            try sourceContainer.encode(data, forKey: .data)
        }
    }
}

/// Tool definition in Anthropic's format (no `type: "function"` wrapper).
struct AnthropicToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

/// Minimal JSON value type for encoding arbitrary tool input.
enum JSONValue: Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Response / SSE Event Types

/// Anthropic SSE events arrive as typed `event:` lines with `data:` payloads.
enum AnthropicStreamEventType: String, Decodable {
    case messageStart = "message_start"
    case contentBlockStart = "content_block_start"
    case contentBlockDelta = "content_block_delta"
    case contentBlockStop = "content_block_stop"
    case messageDelta = "message_delta"
    case messageStop = "message_stop"
    case ping
    case error
}

/// Payload for `content_block_start` events.
struct AnthropicContentBlockStart: Decodable {
    let index: Int
    let contentBlock: ContentBlock

    enum CodingKeys: String, CodingKey {
        case index
        case contentBlock = "content_block"
    }

    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
        let text: String?
    }
}

/// Payload for `content_block_delta` events.
struct AnthropicContentBlockDelta: Decodable {
    let index: Int
    let delta: Delta

    struct Delta: Decodable {
        let type: String
        let text: String?
        let partialJson: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJson = "partial_json"
        }
    }
}

/// Payload for `message_delta` events (carries stop_reason).
struct AnthropicMessageDelta: Decodable {
    let delta: Delta

    struct Delta: Decodable {
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
        }
    }
}

/// Payload for `error` events.
struct AnthropicStreamError: Decodable {
    let error: Detail

    struct Detail: Decodable {
        let type: String
        let message: String
    }
}

/// Response from Anthropic's `models` endpoint.
struct AnthropicModelsResponse: Decodable {
    let data: [ModelEntry]

    struct ModelEntry: Decodable {
        let id: String
    }
}
