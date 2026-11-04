import Foundation

/// Shared scope, permission identity, and result reporting for initiative tools.
protocol InitiativeTool: Tool {
    static var toolName: String { get }
    var service: InitiativeService { get }
    var spaceID: UUID? { get }
}

extension InitiativeTool {
    static var capability: ToolCapability {
        // Keep existing grants effective across the split tool names.
        ToolCapability(
            kind: .builtIn, key: "set_intent_initiatives",
            displayName: Localized.Tools.Agent.initiatives,
            description: Localized.Tools.Description.initiatives,
            defaultPermissionLevel: .always, category: .agent
        )
    }

    var name: String {
        Self.toolName
    }

    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .agent
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    @MainActor func success(_ call: ToolCall, agent: Agent) async throws -> ToolResult {
        let agreements = try await service.report(agentID: agent.id, spaceID: spaceID)
        return try ToolResult(toolCallID: call.id, content: ToolHelpers.output(result: [
            "status": "ok",
            "initiatives": agreements,
            "nearby_suggestions": service.nearbySuggestions(agentID: agent.id, spaceID: spaceID),
            "guidance": "Times follow the device timezone. Delivery depends on notification settings. Only combine nearby times with the user's agreement.",
        ]), isError: false)
    }

    @MainActor func failure(
        _ call: ToolCall, agent: Agent, error: Error,
        changesState: InitiativeOperationFailure.ChangesState = .notSaved
    ) async -> ToolResult {
        let agreements = await (try? service.report(agentID: agent.id, spaceID: spaceID)) ?? []
        return ToolResult(toolCallID: call.id, content: ToolHelpers.output(result: [
            "status": InitiativeFailureCode.code(for: error),
            "changes_state": ((error as? InitiativeOperationFailure)?.changesState ?? changesState)
                .rawValue,
            "initiatives": agreements,
        ], errors: [error.localizedDescription]), isError: true)
    }
}
