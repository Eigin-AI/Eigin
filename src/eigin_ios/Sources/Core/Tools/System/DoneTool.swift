import Foundation

struct DoneTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "done",
        displayName: Localized.Tools.System.done,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "done"
    var displayName: String {
        Self.capability.displayName
    }

    /// Optional callback fired on execution — used by background prompts to signal completion.
    let onDone: (@Sendable () -> Void)?

    init(onDone: (@Sendable () -> Void)? = nil) {
        self.onDone = onDone
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Signal that your current task is complete.",
            parameters: JSONSchema(type: "object")
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        onDone?()
        return ToolResult(
            toolCallID: toolCall.id,
            content: ToolHelpers.output(result: ["status": "OK"]),
            isError: false
        )
    }
}
