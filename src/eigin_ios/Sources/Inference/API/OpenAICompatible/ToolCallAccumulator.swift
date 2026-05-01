import Foundation

/// Collects streaming tool call deltas and assembles them into complete `ToolCall` objects.
///
/// Handles two formats:
/// - **OpenAI**: deltas keyed by `index`, arguments arrive in fragments across chunks
/// - **Gemini**: complete tool calls per chunk, no `index`, each has a unique `id`
struct ToolCallAccumulator {
    private struct Partial {
        var id: String = ""
        var type: String = "function"
        var name: String = ""
        var arguments: String = ""
    }

    private var partials: [Int: Partial] = [:]
    private var nextAutoIndex = 1000 // auto-assigned keys for index-less deltas

    /// Provider-specific metadata captured from streaming deltas (e.g. Gemini thought_signature).
    /// Attached to the assistant message so the ProviderAdapter can inject it into future requests.
    private(set) var capturedProviderMetadata: [String: String]?

    /// Whether any tool call deltas have been accumulated.
    var hasToolCalls: Bool {
        !partials.isEmpty
    }

    /// Feed a single delta into the accumulator.
    mutating func feed(_ delta: ToolCallDelta) {
        // Capture provider metadata (e.g. Gemini thought_signature) if present
        if let sig = delta.extraContent?.google?.thoughtSignature {
            var meta = capturedProviderMetadata ?? [:]
            meta["thought_signature"] = sig
            capturedProviderMetadata = meta
        }

        // Skip deltas with no useful content (e.g. Gemini "thinking" entries)
        let hasContent = delta.id != nil || delta.function != nil
        guard hasContent else { return }

        let key: Int
        if let index = delta.index {
            // OpenAI format: explicit index
            key = index
        } else if let id = delta.id {
            // Gemini format: no index, but has an id — find existing or assign new key
            if let existing = partials.first(where: { $0.value.id == id }) {
                key = existing.key
            } else {
                key = nextAutoIndex
                nextAutoIndex += 1
            }
        } else {
            // No index, no id — append to key 0
            key = 0
        }

        var partial = partials[key] ?? Partial()
        if let id = delta.id { partial.id = id }
        if let type = delta.type { partial.type = type }
        if let name = delta.function?.name { partial.name = name }
        if let args = delta.function?.arguments { partial.arguments += args }
        partials[key] = partial
    }

    /// Assembles accumulated partials into complete `ToolCall` objects,
    /// filters out empty/invalid entries, sorts by key, and clears state.
    mutating func finalize() -> [ToolCall] {
        let calls = partials
            .sorted(by: { $0.key < $1.key })
            .compactMap { _, partial -> ToolCall? in
                // Skip partials with no id or name (e.g. junk from thinking tokens)
                guard !partial.id.isEmpty, !partial.name.isEmpty else { return nil }
                return ToolCall(
                    id: partial.id,
                    type: partial.type,
                    function: .init(name: partial.name, arguments: partial.arguments)
                )
            }
        partials = [:]
        nextAutoIndex = 1000
        capturedProviderMetadata = nil
        return calls
    }
}
