import Foundation

/// A self-contained tool that an agent can invoke.
protocol Tool: Sendable {
    var name: String { get }
    var displayName: String { get }
    /// Whether this tool is operating in a small-context environment.
    /// Tools can use this to produce shorter definitions and results.
    var isSmallContext: Bool { get set }
    /// Capabilities this tool requires permission for. Empty means no permission check.
    var capabilities: [ToolCapability] { get }
    /// Category for grouping in the permissions UI.
    var category: ToolCapability.Category { get }
    /// Default permission level when no explicit agent grant exists.
    var defaultPermissionLevel: ToolPermissionLevel { get }
    func definition() -> ToolDefinition
    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult
}

extension Tool {
    var isSmallContext: Bool {
        get { false }
        set {}
    }

    var capabilities: [ToolCapability] {
        []
    }

    var category: ToolCapability.Category {
        .agent
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }
}
