import Foundation

/// Deliberate forgetting: soft-hides a memory by setting `expired = true`.
///
/// Gentler than delete — the entry stays in the graph and is still findable
/// with `include_expired`, it's just hidden from normal search and ranking.
struct ForgetKnowledgeTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "forget_knowledge",
        displayName: Localized.Tools.Forget.knowledge,
        defaultPermissionLevel: .always, category: .knowledge
    )

    let name = "forget_knowledge"
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
        .always
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
            Retire a knowledge entry that no longer holds. Hidden from search \
            but kept (findable with include_expired). Prefer over delete_knowledge.
            """,
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
                        description: "Entry ID (e.g. \"likes_espresso\")."
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
                content: ToolHelpers.output(errors: ["Invalid JSON arguments"]), isError: true
            )
        }
        guard let entityType = args["type"] as? String else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Missing 'type' parameter"]), isError: true
            )
        }
        guard var entityID = args["id"] as? String else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Missing 'id' parameter"]), isError: true
            )
        }
        if entityID.hasPrefix("\(entityType).") {
            entityID = String(entityID.dropFirst(entityType.count + 1))
        }

        do {
            try await knowledgeService.setExpired(
                type: entityType, id: entityID, expired: true,
                spaceID: spaceID, agentID: agentID
            )
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(result: [
                    "id": "\(entityType).\(entityID)", "status": "forgotten",
                ]),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: [error.localizedDescription]), isError: true
            )
        }
    }
}
