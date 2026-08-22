import Foundation

/// Collects tools and dispatches calls by name lookup.
struct ToolRegistry: ToolExecutor {
    private let toolsByName: [String: any Tool]
    let isSmallContext: Bool

    init(tools: [any Tool], isSmallContext: Bool = false) {
        var map = [String: any Tool]()
        for tool in tools {
            map[tool.name] = tool
        }
        toolsByName = map
        self.isSmallContext = isSmallContext
    }

    /// Tool definitions for passing to the chat service.
    var definitions: [ToolDefinition] {
        toolsByName.values
            .map { $0.definition() }
            .sorted(by: { (a: ToolDefinition, b: ToolDefinition) in
                a.function.name < b.function.name
            })
    }

    /// Maximum characters for tool result content in small-context mode.
    private static let smallContextResultLimit = 2000

    func executionMode(for toolName: String) -> ToolExecutionMode {
        toolsByName[toolName]?.executionMode ?? .background
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        toolsByName[toolCall.function.name]?.disclosure(for: toolCall)
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        guard let tool = toolsByName[toolCall.function.name] else {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(errors: ["Unknown tool: \(toolCall.function.name)"]),
                isError: true
            )
        }
        var result = await tool.execute(toolCall, agent: agent)
        if isSmallContext, !result.isError,
           result.content.count > Self.smallContextResultLimit
        {
            result = ToolResult(
                toolCallID: result.toolCallID,
                content: String(result.content.prefix(Self.smallContextResultLimit)),
                isError: false
            )
        }
        return result
    }

    /// Dynamic display names registered at runtime (e.g. MCP tools).
    @MainActor static var dynamicDisplayNames: [String: String] = [:]

    /// Display name for a tool, looked up from all known tool types.
    /// Falls back to dynamic names for MCP tools not in the static metadata.
    static func displayName(for toolName: String) -> String {
        if let name = allDisplayNames[toolName] { return name }
        if let name = MainActor.assumeIsolated({ dynamicDisplayNames[toolName] }) { return name }
        return deriveMCPDisplayName(toolName) ?? toolName
    }

    /// Capabilities for a tool, looked up from all known tool types.
    /// MCP tools (prefixed with "mcp__") return a discovered capability keyed by their full name.
    static func capabilities(for toolName: String) -> [ToolCapability] {
        if let meta = allToolMetadata[toolName] { return meta.capabilities }
        if toolName.hasPrefix("mcp__") {
            let display = MainActor.assumeIsolated { dynamicDisplayNames[toolName] }
                ?? deriveMCPDisplayName(toolName)
                ?? toolName
            return [ToolCapability(
                kind: .discovered, key: toolName,
                displayName: display,
                defaultPermissionLevel: MCPToolProxy.defaultCapability.defaultPermissionLevel,
                category: .external
            )]
        }
        return []
    }

    /// Derives a display name from an MCP tool ID: "mcp__server_name__tool" → "Server Name: Tool"
    private static func deriveMCPDisplayName(_ toolName: String) -> String? {
        guard toolName.hasPrefix("mcp__") else { return nil }
        let remainder = String(toolName.dropFirst(5))
        guard let range = remainder.range(of: "__") else { return nil }
        let server = String(remainder[..<range.lowerBound]).titleCased
        let tool = String(remainder[range.upperBound...]).titleCased
        return "\(server): \(tool)"
    }

    // MARK: - Capability Registry

    /// All built-in capabilities, collected from domain tool kits.
    /// Adding a new tool? Add it to the appropriate domain ToolKit.
    static let allBuiltInCapabilities: [ToolCapability] =
        allKitCapabilities + [MCPToolProxy.defaultCapability]

    /// Look up a capability by key (for Codable restoration, permissions UI).
    static func capability(forKey key: String) -> ToolCapability? {
        allBuiltInCapabilities.first { $0.key == key }
    }

    /// Built-in capabilities grouped by category (for permissions UI).
    static func capabilities(for category: ToolCapability.Category) -> [ToolCapability] {
        allBuiltInCapabilities.filter { $0.category == category }
    }

    // MARK: - Static Metadata

    private static let allDisplayNames: [String: String] = allToolMetadata.mapValues(\.displayName)

    static let allToolMetadata: [String: ToolMetadata] = {
        var map = [String: ToolMetadata]()
        for cap in allKitCapabilities {
            if cap == DoneTool.capability || cap == BackgroundNotifyTool.capability {
                // System tools: not user-configurable, but need display names for chat UI
                map[cap.key] = ToolMetadata(displayName: cap.displayName, capabilities: [])
            } else {
                map[cap.key] = ToolMetadata(displayName: cap.displayName, capabilities: [cap])
            }
        }
        return map
    }()

    struct ToolMetadata {
        let displayName: String
        let capabilities: [ToolCapability]
    }
}
