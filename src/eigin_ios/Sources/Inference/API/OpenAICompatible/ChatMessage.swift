import Foundation

/// A single message in an OpenAI-compatible chat conversation, identified by its role (e.g. "user",
/// "assistant",
/// "system").
struct ChatMessage: Codable {
    /// Local-only stable identifier for UI tracking. Not sent to the API.
    let localID: String

    var role: String
    var content: String?
    var toolCallID: String?
    /// Function name for tool role messages (OpenAI spec).
    var name: String?
    var toolCalls: [ToolCall]?

    /// Provider-specific metadata (e.g. Gemini thought_signature).
    /// Not part of CodingKeys — injected into the request body by the ProviderAdapter.
    var providerMetadata: [String: String]?

    /// Local-only flag marking this message as a compaction summary.
    /// Not sent to the API — used by ``ChatItem.buildItems()`` and ``buildAPIMessages()``.
    var isCompactionSummary: Bool = false

    /// Lightweight references to locally-stored attachments (images, etc.).
    ///
    /// Not part of the Codable encoding; each provider client converts these into
    /// its own wire representation at request-build time. The bytes are loaded from
    /// ``ChatAttachmentStore`` on demand.
    var attachments: [MessageAttachment]?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    /// Convenience initializer for simple text messages (user, system, assistant).
    init(role: String, content: String, localID: String = UUID().uuidString) {
        self.localID = localID
        self.role = role
        self.content = content
        name = nil
    }

    /// Full initializer for tool-related messages.
    init(
        role: String,
        content: String? = nil,
        toolCallID: String? = nil,
        name: String? = nil,
        toolCalls: [ToolCall]? = nil,
        providerMetadata: [String: String]? = nil,
        attachments: [MessageAttachment]? = nil,
        localID: String = UUID().uuidString
    ) {
        self.localID = localID
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.name = name
        self.toolCalls = toolCalls
        self.providerMetadata = providerMetadata
        self.attachments = attachments
    }

    /// Returns a copy of this message with all attachment references replaced by the given
    /// placeholder text appended to the existing content.
    func withStrippedAttachments(placeholder: String = "[image omitted]") -> ChatMessage {
        guard attachments != nil else { return self }
        var copy = self
        copy.attachments = nil
        // Append placeholder so the model knows an image was present.
        let base = copy.content ?? ""
        copy.content = base.isEmpty ? placeholder : base + "\n\n" + placeholder
        return copy
    }

    /// Custom encoding that omits nil optional fields instead of writing null.
    /// Gemini and other providers reject unexpected null fields.
    /// Provider-specific details (e.g. thought_signature) are injected by the
    /// ProviderAdapter via JSON post-processing, not during encoding.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localID = UUID().uuidString
        role = try container.decode(String.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        providerMetadata = nil
    }
}
