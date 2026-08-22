import Foundation

/// Controls how the chat loop handles a tool's execution.
enum ToolExecutionMode {
    /// Normal execution: runs with a timeout, input remains locked.
    /// Use for all tools that do background work (API calls, data access, etc.).
    case background

    /// Interactive execution: no timeout, input re-enabled while the tool runs.
    /// Use for tools that suspend waiting for user input (e.g. presenting options).
    case interactive
}

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
    /// How the loop handles this tool's execution. Defaults to `.background`.
    var executionMode: ToolExecutionMode { get }
    /// Optional disclosure for the permission sheet, built from the call args.
    /// Default `nil` keeps the generic "wants to use {tool}" prompt.
    func disclosure(for toolCall: ToolCall) -> ToolDisclosure?
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

    var executionMode: ToolExecutionMode {
        .background
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        nil
    }
}
