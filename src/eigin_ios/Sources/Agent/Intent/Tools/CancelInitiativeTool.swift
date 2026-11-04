import Foundation

/// Stops an initiative without changing its intent or requiring notification permission.
struct CancelInitiativeTool: InitiativeTool {
    static let toolName = "cancel_initiative"
    let service: InitiativeService
    let spaceID: UUID?

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Cancel an initiative when its agreement ends. Use its ID from list_initiatives.",
            parameters: JSONSchema(type: "object", properties: [
                "id": .init(type: "string", description: "Initiative UUID from list_initiatives."),
            ], required: ["id"])
        )
    }

    @MainActor func execute(_ call: ToolCall, agent: Agent) async -> ToolResult {
        var changesState = InitiativeOperationFailure.ChangesState.notSaved
        do {
            guard let args = ToolHelpers.parseArguments(call.function.arguments),
                  let text = args["id"] as? String, let id = UUID(uuidString: text)
            else { throw InitiativeError.invalidInitiativeID }
            try await service.cancel(id: id, agentID: agent.id, spaceID: spaceID)
            changesState = .saved
            return try await success(call, agent: agent)
        } catch {
            return await failure(call, agent: agent, error: error, changesState: changesState)
        }
    }
}
