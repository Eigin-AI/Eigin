import Foundation

/// How a tool call should be authorized.
enum ToolPermissionLevel: String, Codable, CaseIterable {
    /// Block the tool call entirely.
    case never
    /// Ask the user for permission before executing.
    case ask
    /// Allow without prompting.
    case always

    var displayName: String {
        switch self {
        case .never: Localized.Permission.never
        case .ask: Localized.Permission.ask
        case .always: Localized.Permission.always
        }
    }
}

/// Distinguishes built-in capabilities from MCP-discovered ones.
enum GrantKind: String, Codable {
    case builtIn
    case discovered
}

/// Decides the permission level for a given tool call.
protocol ToolPermissionPolicy: Sendable {
    func permissionLevel(for toolName: String) -> ToolPermissionLevel
}

/// Allows all tool calls without prompting. Used during bootstrap.
struct AlwaysAllowPolicy: ToolPermissionPolicy {
    func permissionLevel(for toolName: String) -> ToolPermissionLevel {
        .always
    }
}

/// Per-agent permission policy that resolves capabilities against stored
/// agent grants and per-chat grants.
///
/// Resolution for discovered (MCP) capabilities:
///   per-tool discovered grant → `mcpServer` built-in fallback → default (.ask)
///
/// Resolution for built-in capabilities:
///   agent grant → capability default
struct AgentPermissionPolicy: ToolPermissionPolicy {
    /// Built-in capability key → configured level from agent-level grants.
    let builtInGrants: [String: ToolPermissionLevel]
    /// Discovered capability key → configured level from agent-level grants.
    let discoveredGrants: [String: ToolPermissionLevel]
    /// Capability keys granted for this chat session.
    private(set) var chatGrants: Set<String>
    /// Whether the UI can present a permission prompt (false during live calls / backgrounded).
    let canPromptUser: Bool

    /// Records chat-level grants so subsequent checks in the same loop return `.always`.
    mutating func grantForChat(_ capabilities: [ToolCapability]) {
        for capability in capabilities {
            chatGrants.insert(capability.key)
        }
    }

    func permissionLevel(for toolName: String) -> ToolPermissionLevel {
        let capabilities = ToolRegistry.capabilities(for: toolName)

        // Discovered capabilities — per-tool grant, then mcpServer fallback
        for cap in capabilities where cap.kind == .discovered {
            if let level = discoveredGrants[cap.key] {
                if level == .ask, chatGrants.contains(cap.key) { return .always }
                return level
            }
            // Fall back to the built-in mcpServer capability grant
            let fallback = builtInGrants[MCPToolProxy.defaultCapability.key]
                ?? MCPToolProxy.defaultCapability.defaultPermissionLevel
            if fallback == .ask, chatGrants.contains(cap.key) { return .always }
            return fallback
        }

        // Built-in capabilities (existing merge logic)
        guard !capabilities.isEmpty else { return .ask }

        var effective: ToolPermissionLevel = .always
        for cap in capabilities {
            let level = builtInGrants[cap.key] ?? cap.defaultPermissionLevel

            // Chat grant upgrades ask → always for this session
            if level == .ask, chatGrants.contains(cap.key) {
                continue
            }
            if level == .never { return .never }
            if level == .ask { effective = .ask }
        }
        return effective
    }
}
