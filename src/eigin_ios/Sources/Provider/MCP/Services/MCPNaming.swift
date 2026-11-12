import CryptoKit
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

    /// Namespaces tools within provider function-name limits, hashing shortened or escaped names.
    static func toolName(serverName: String, toolName: String) -> String {
        let original = "mcp\(namespaceDelimiter)\(sanitize(serverName))\(namespaceDelimiter)\(toolName)"
        let safe = sanitizedFunctionName(original)
        guard safe.count > 64 || safe != original else { return safe }
        let hash = SHA256.hash(data: Data(original.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        let suffix = "_\(hash)"
        return "\(safe.prefix(64 - suffix.count))\(suffix)"
    }

    private static func sanitizedFunctionName(_ name: String) -> String {
        name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
    }
}
