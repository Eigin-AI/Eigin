import Foundation

/// Gemma's native FC (function-calling) wire format helpers.
///
/// LiteRT-LM now handles tool declaration injection (via ``ConversationConfig``)
/// and output parsing (`<|tool_call>` → structured JSON) natively. These helpers
/// are kept for encoding tool call history into assistant/tool messages so the
/// engine's chat template reconstructs prior rounds correctly when rebuilding a
/// conversation.
extension LocalClient {
    // MARK: - History encoding (app/JSON → Gemma FC markers)

    /// Encodes a prior assistant tool call as a Gemma FC marker for inclusion
    /// in the assistant turn when seeding conversation history.
    static func renderGemmaToolCall(name: String, jsonArgs: String) -> String {
        let gemmaArgs = convertJSONArgsToGemma(jsonArgs)
        return "<|tool_call>call:\(name)\(gemmaArgs)<tool_call|>"
    }

    /// Encodes a prior tool response as a Gemma FC marker for inclusion in
    /// a tool-role turn when seeding conversation history.
    static func renderGemmaToolResponse(name: String, content: String) -> String {
        let body: String
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            body = convertJSONArgsToGemma(trimmed)
        } else {
            body = "{value:<|\"|>\(escapeGemmaString(content))<|\"|>}"
        }
        return "<|tool_response>response:\(name)\(body)<tool_response|>"
    }

    // MARK: - Conversion helpers

    static func convertJSONArgsToGemma(_ jsonArgs: String) -> String {
        guard let data = jsonArgs.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return jsonArgs
        }
        return renderGemmaValue(obj)
    }

    private static func renderGemmaValue(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            let entries = dict.map { key, val in "\(key):\(renderGemmaValue(val))" }
            return "{" + entries.joined(separator: ",") + "}"
        }
        if let arr = value as? [Any] {
            return "[" + arr.map { renderGemmaValue($0) }.joined(separator: ",") + "]"
        }
        if let str = value as? String {
            return "<|\"|>\(escapeGemmaString(str))<|\"|>"
        }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let n = value as? NSNumber { return n.stringValue }
        return "null"
    }

    private static func escapeGemmaString(_ s: String) -> String {
        s.replacingOccurrences(of: "<|\"|>", with: "\"")
    }
}
