import Foundation

/// Lists the agent's initiatives in the current space and their delivery status.
struct ListInitiativesTool: InitiativeTool {
    static let toolName = "list_initiatives"
    let service: InitiativeService
    let spaceID: UUID?

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "List initiatives in this space, including their IDs, agreed times, and delivery status.",
            parameters: JSONSchema(type: "object", properties: [:])
        )
    }

    @MainActor func execute(_ call: ToolCall, agent: Agent) async -> ToolResult {
        do { return try await success(call, agent: agent) }
        catch { return await failure(call, agent: agent, error: error) }
    }
}
