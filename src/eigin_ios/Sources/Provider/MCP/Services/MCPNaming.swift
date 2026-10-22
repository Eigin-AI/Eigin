import Foundation

/// Shared name derivation for MCP servers and their tools.
///
/// Used both by ``MCPToolProxy`` (live tool names) and ``MCPServerSkill``
/// (catalog projection from cached tool names, no connection needed) so the
/// two stay namespaced identically.
enum MCPNaming {
    /// Delimiter between segments in IDs and capability keys — double so a
    /// single underscore in a server or tool name can't read as a boundary.
    static let namespaceDelimiter = "__"

    /// Sanitizes a server name for use in a tool/skill identifier:
    /// lowercased, spaces become underscores, non-alphanumeric/underscore
    /// characters dropped.
    static func sanitize(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// The skill ID a server projects to: `mcp__<sanitized_server_name>`.
    static func skillID(serverName: String) -> String {
        "mcp__\(sanitize(serverName))"
    }

    /// The namespaced tool name: `mcp__<sanitized_server_name>__<tool_name>`.
    /// Double underscores mark the namespace boundaries so a single-underscore
    /// server or tool name (e.g. "my_server") can't be misread as part of the
    /// delimiter when the name is split back apart.
    static func toolName(serverName: String, toolName: String) -> String {
        "mcp\(namespaceDelimiter)\(sanitize(serverName))\(namespaceDelimiter)\(toolName)"
    }
}
