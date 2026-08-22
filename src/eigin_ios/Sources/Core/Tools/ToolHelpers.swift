import Foundation

/// Shared utilities for tool implementations.
enum ToolHelpers {
    static func parseArguments(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    /// A trimmed, non-empty string argument from a tool call, or nil.
    /// Convenient for building permission disclosures.
    static func stringArgument(_ toolCall: ToolCall, _ key: String) -> String? {
        guard let args = parseArguments(toolCall.function.arguments),
              let value = (args[key] as? String)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Build a standardised tool result JSON string.
    ///
    /// Envelope: `{ "result": {…}, "errors": […], "warnings": […] }`
    /// All three fields are optional — only non-nil values are included.
    static func output(
        result: [String: Any]? = nil,
        errors: [String]? = nil,
        warnings: [String]? = nil
    ) -> String {
        var dict: [String: Any] = [:]
        if let result { dict["result"] = result }
        if let errors { dict["errors"] = errors }
        if let warnings { dict["warnings"] = warnings }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
}
