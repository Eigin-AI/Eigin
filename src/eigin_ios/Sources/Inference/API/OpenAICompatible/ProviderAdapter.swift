import Foundation

/// Encapsulates provider-specific behavior so core types remain pure OpenAI-compatible.
protocol ProviderAdapter: Sendable {
    /// Post-process the JSON-encoded request body before sending.
    /// `messages` provides access to providerMetadata (not in the encoded JSON).
    func processRequestBody(
        _ body: Data,
        messages: [ChatMessage],
        reasoningOrigin: ReasoningOrigin?
    ) throws -> Data

    /// Creates provider-specific capture state for a compatible destination.
    func makeReasoningCapture(origin: ReasoningOrigin?) -> (any ReasoningCapturing)?

    /// Whether this provider sends "stop" as finish reason even when tool calls are present.
    var treatsStopAsToolCalls: Bool { get }

    /// Whether this provider reads the OpenAI-style `prompt_cache_key` request field.
    /// This is about which field carries the key, not whether the provider caches at all:
    /// Anthropic caches via `cache_control` and so returns `false` here.
    var usesPromptCacheKey: Bool { get }
}

/// Accumulates provider wire events into private continuation state.
protocol ReasoningCapturing: Sendable {
    mutating func append(chunk: Data)
    mutating func invalidate()
    func completed() -> ReasoningHistory?
}

extension ProviderAdapter {
    func makeReasoningCapture(origin: ReasoningOrigin?) -> (any ReasoningCapturing)? {
        nil
    }

    func processRequestBody(_ body: Data, messages: [ChatMessage]) throws -> Data {
        try processRequestBody(body, messages: messages, reasoningOrigin: nil)
    }
}

/// No-op adapter for standard OpenAI-compatible providers.
struct DefaultAdapter: ProviderAdapter {
    func processRequestBody(
        _ body: Data,
        messages: [ChatMessage],
        reasoningOrigin: ReasoningOrigin? = nil
    ) throws -> Data {
        body
    }

    var treatsStopAsToolCalls: Bool {
        false
    }

    var usesPromptCacheKey: Bool {
        true
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

    /// Gemini's OpenAI-compatible endpoint does not read `prompt_cache_key`.
    var usesPromptCacheKey: Bool {
        false
    }

    func processRequestBody(
        _ body: Data,
        messages: [ChatMessage],
        reasoningOrigin: ReasoningOrigin? = nil
    ) throws -> Data {
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

/// Adapter for Anthropic models on OpenRouter.
///
/// Injects top-level `cache_control` into the OpenAI-compatible request body so
/// OpenRouter passes the caching hint through to the Anthropic API.
struct AnthropicAdapter: ProviderAdapter {
    var treatsStopAsToolCalls: Bool {
        false
    }

    /// Anthropic caches via the top-level `cache_control` hint, not `prompt_cache_key`.
    var usesPromptCacheKey: Bool {
        false
    }

    func processRequestBody(
        _ body: Data,
        messages: [ChatMessage],
        reasoningOrigin: ReasoningOrigin? = nil
    ) throws -> Data {
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
    static func adapter(
        for baseURL: String,
        model: String,
        isEiginRelay: Bool = false
    ) -> ProviderAdapter {
        // Primary: URL-based detection (direct API access)
        if baseURL.contains("generativelanguage.googleapis.com") {
            return GeminiAdapter()
        }
        if URL(string: baseURL)?.host?.lowercased() == "api.mistral.ai" {
            return MistralAdapter(supportsReasoningHistory: true)
        }

        // Fallback: model-based detection via catalog (for routers)
        if let entry = KnownModelCatalog.lookup(model) {
            switch entry.family {
            case .google: return GeminiAdapter()
            case .mistral: return MistralAdapter(supportsReasoningHistory: isEiginRelay ||
                    ProviderPreset.isRelay(baseURL))
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

    /// Reads current envelopes and native history saved by earlier development builds.
    static func decodeReasoningHistory(_ data: Data) -> ReasoningHistory? {
        if let history = try? JSONDecoder()
            .decode(ReasoningHistory.self, from: data) { return history }
        return try? JSONDecoder().decode(MistralReasoningHistory.self, from: data).stored()
    }
}
