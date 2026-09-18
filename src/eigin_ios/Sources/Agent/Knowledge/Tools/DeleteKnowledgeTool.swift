import Foundation

struct DeleteKnowledgeTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "delete_knowledge",
        displayName: Localized.Tools.Delete.knowledge,
        description: Localized.Tools.Description.deleteKnowledge,
        defaultPermissionLevel: .ask, category: .knowledge
    )

    let name = "delete_knowledge"
    var isSmallContext: Bool = false
    let knowledgeService: any KnowledgeService
    let spaceID: UUID?
    let agentID: UUID?
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .knowledge
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Delete a knowledge entry by type and ID. Only user/agent-created entries can be deleted. Bundled entries are protected.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "type": .init(
                        type: "string",
                        description: "Knowledge type.",
                        enum: ["actor", "thing", "fact", "output", "note"]
                    ),
                    "id": .init(
                        type: "string",
                        description: "Entry ID to delete (e.g. \"alice\", \"my_note\")."
                    ),
                ],
                required: ["type", "id"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let callID = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }
        guard let entityType = args["type"] as? String else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Missing 'type' parameter"]),
                isError: true
            )
        }
        guard var entityID = args["id"] as? String else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Missing 'id' parameter"]),
                isError: true
            )
        }
        // Strip type prefix if the LLM included it.
        if entityID.hasPrefix("\(entityType).") {
            entityID = String(entityID.dropFirst(entityType.count + 1))
        }

        do {
            try await knowledgeService.deleteEntity(
                type: entityType,
                id: entityID,
                spaceID: spaceID,
                agentID: agentID
            )
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(result: [
                    "id": "\(entityType).\(entityID)",
                    "status": "deleted",
                ]),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
