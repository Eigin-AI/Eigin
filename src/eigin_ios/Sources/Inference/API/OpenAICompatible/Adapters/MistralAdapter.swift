import Foundation

/// Adapter for Mistral AI's OpenAI-compatible endpoint.
///
/// Sanitizes tool call IDs to contain only alphanumeric characters (`[a-zA-Z0-9]`),
/// which is Mistral's requirement. Both `tool_calls[*].id` (assistant messages) and
/// `tool_call_id` (tool result messages) are sanitized with the same function so IDs stay in sync.
struct MistralAdapter: ProviderAdapter {
    let supportsReasoningHistory: Bool

    init(supportsReasoningHistory: Bool = false) {
        self.supportsReasoningHistory = supportsReasoningHistory
    }

    func makeReasoningCapture(origin: ReasoningOrigin?) -> (any ReasoningCapturing)? {
        guard supportsReasoningHistory, let origin else { return nil }
        return MistralReasoningAccumulator(origin: origin)
    }

    var treatsStopAsToolCalls: Bool {
        false
    }

    var usesPromptCacheKey: Bool {
        true
    }

    func processRequestBody(
        _ body: Data,
        messages: [ChatMessage],
        reasoningOrigin: ReasoningOrigin? = nil
    ) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              var jsonMessages = root["messages"] as? [[String: Any]]
        else {
            return body
        }

        var changed = false

        for i in 0 ..< jsonMessages.count {
            if supportsReasoningHistory, i < messages.count,
               let history = messages[i].reasoningHistory,
               history.format == MistralReasoningHistory.format,
               history.matches(messages[i], origin: reasoningOrigin),
               let parts = try? JSONDecoder().decode(
                   [MistralContentPart].self,
                   from: history.payload
               )
            {
                jsonMessages[i]["content"] = try JSONSerialization
                    .jsonObject(with: JSONEncoder().encode(parts))
                changed = true
            }
            // Sanitize tool_call_id on tool result messages
            if let toolCallID = jsonMessages[i]["tool_call_id"] as? String {
                let sanitized = Self.sanitizeID(toolCallID)
                if sanitized != toolCallID {
                    jsonMessages[i]["tool_call_id"] = sanitized
                    changed = true
                }
            }

            // Sanitize tool_calls[*].id on assistant messages
            if var toolCalls = jsonMessages[i]["tool_calls"] as? [[String: Any]] {
                for j in 0 ..< toolCalls.count {
                    if let id = toolCalls[j]["id"] as? String {
                        let sanitized = Self.sanitizeID(id)
                        if sanitized != id {
                            toolCalls[j]["id"] = sanitized
                            changed = true
                        }
                    }
                }
                if changed { jsonMessages[i]["tool_calls"] = toolCalls }
            }
        }

        guard changed else { return body }

        root["messages"] = jsonMessages
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// Strips all characters outside `[a-zA-Z0-9]`.
    static func sanitizeID(_ id: String) -> String {
        String(id.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.suffix(9))
    }
}
