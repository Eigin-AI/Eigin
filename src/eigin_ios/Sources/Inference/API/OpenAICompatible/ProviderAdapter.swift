import Foundation

/// Encapsulates provider-specific behavior so core types remain pure OpenAI-compatible.
protocol ProviderAdapter: Sendable {
    /// Post-process the JSON-encoded request body before sending.
    /// `messages` provides access to providerMetadata (not in the encoded JSON).
    func processRequestBody(_ body: Data, messages: [ChatMessage]) throws -> Data

    /// Whether this provider sends "stop" as finish reason even when tool calls are present.
    var treatsStopAsToolCalls: Bool { get }
}

/// No-op adapter for standard OpenAI-compatible providers.
struct DefaultAdapter: ProviderAdapter {
    func processRequestBody(_ body: Data, messages: [ChatMessage]) throws -> Data {
        body
    }

    var treatsStopAsToolCalls: Bool {
        false
    }
}

/// Adapter for Google Gemini via its OpenAI-compatible endpoint.
///
/// Handles two Gemini-specific behaviors:
/// 1. Injects `thought_signature` into request JSON as `extra_content` on the first tool call
/// 2. Treats "stop" finish reason as tool calls when the accumulator has pending calls
struct GeminiAdapter: ProviderAdapter {
    var treatsStopAsToolCalls: Bool {
        true
    }

    func processRequestBody(_ body: Data, messages: [ChatMessage]) throws -> Data {
        // Check if any message has a thought_signature to inject
        let hasSignature = messages.contains { msg in
            msg.providerMetadata?["thought_signature"] != nil && msg.toolCalls != nil
        }
        guard hasSignature else { return body }

        guard var root = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              var jsonMessages = root["messages"] as? [[String: Any]]
        else {
            return body
        }

        // Walk messages and JSON messages in parallel by index
        for i in 0 ..< min(messages.count, jsonMessages.count) {
            guard let sig = messages[i].providerMetadata?["thought_signature"],
                  messages[i].toolCalls != nil,
                  var toolCalls = jsonMessages[i]["tool_calls"] as? [[String: Any]],
                  !toolCalls.isEmpty
            else {
                continue
            }

            // Inject extra_content onto the first tool call
            toolCalls[0]["extra_content"] = [
                "google": ["thought_signature": sig],
            ]
            jsonMessages[i]["tool_calls"] = toolCalls
        }

        root["messages"] = jsonMessages
        return try JSONSerialization.data(withJSONObject: root)
    }
}

/// Adapter for Mistral AI's OpenAI-compatible endpoint.
///
/// Sanitizes tool call IDs to contain only alphanumeric characters (`[a-zA-Z0-9]`),
/// which is Mistral's requirement. Both `tool_calls[*].id` (assistant messages) and
/// `tool_call_id` (tool result messages) are sanitized with the same function so IDs stay in sync.
struct MistralAdapter: ProviderAdapter {
    var treatsStopAsToolCalls: Bool {
        false
    }

    func processRequestBody(_ body: Data, messages: [ChatMessage]) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              var jsonMessages = root["messages"] as? [[String: Any]]
        else {
            return body
        }

        var changed = false

        for i in 0 ..< jsonMessages.count {
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

/// Adapter for Anthropic models on OpenRouter.
///
/// Injects top-level `cache_control` into the OpenAI-compatible request body so
/// OpenRouter passes the caching hint through to the Anthropic API.
struct AnthropicAdapter: ProviderAdapter {
    var treatsStopAsToolCalls: Bool {
        false
    }

    func processRequestBody(_ body: Data, messages: [ChatMessage]) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return body
        }
        root["cache_control"] = ["type": "ephemeral"]
        return try JSONSerialization.data(withJSONObject: root)
    }
}

/// Selects the appropriate adapter based on the provider's base URL and model name.
///
/// URL matching is the primary signal (cheap, exact). Model-name matching via the
/// catalog kicks in as a fallback for routers like OpenRouter that proxy to the
/// original model API without normalizing request/response formats.
enum ProviderAdapterFactory {
    static func adapter(for baseURL: String, model: String) -> ProviderAdapter {
        // Primary: URL-based detection (direct API access)
        if baseURL.contains("generativelanguage.googleapis.com") {
            return GeminiAdapter()
        }
        if baseURL.contains("api.mistral.ai") {
            return MistralAdapter()
        }

        // Fallback: model-based detection via catalog (for routers)
        if let entry = KnownModelCatalog.lookup(model) {
            switch entry.family {
            case .google: return GeminiAdapter()
            case .mistral: return MistralAdapter()
            default: break
            }
        }

        // OpenRouter: inject cache_control for Anthropic models
        // TODO: EUrouter and other model aggregators may also support cache_control
        // passthrough for Anthropic models — extend when documented/tested.
        if baseURL.contains("openrouter.ai"),
           let entry = KnownModelCatalog.lookup(model),
           entry.family == .anthropic
        {
            return AnthropicAdapter()
        }

        return DefaultAdapter()
    }
}
