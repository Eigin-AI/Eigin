import Foundation

/// One memory replaces another: expire the old entry and link the new one to it
/// via the `supersedes` relation, keeping a trail of what replaced what.
struct SupersedeKnowledgeTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "supersede_knowledge",
        displayName: Localized.Tools.Supersede.knowledge,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "supersede_knowledge"
    var isSmallContext: Bool = false
    let knowledgeService: any KnowledgeService
    let spaceID: UUID?
    let agentID: UUID?
    let chatID: UUID?
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

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
            Replace an outdated knowledge entry with a newer one. The old entry \
            is hidden and the new one records that it supersedes it.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "old": .init(
                        type: "string",
                        description: "Qualified ID of the entry being replaced (e.g. \"fact.old_role\")."
                    ),
                    "new": .init(
                        type: "string",
                        description: "Qualified ID of the replacement entry (e.g. \"fact.new_role\")."
                    ),
                ],
                required: ["old", "new"]
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
        guard let oldRaw = args["old"] as? String, let newRaw = args["new"] as? String else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers
                    .output(errors: ["Both 'old' and 'new' are required (e.g. \"fact.x\")."]),
                isError: true
            )
        }
        guard let old = parseQualifiedKnowledgeID(oldRaw),
              let new = parseQualifiedKnowledgeID(newRaw)
        else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: [
                    "'old' and 'new' must be qualified IDs like \"fact.likes_tea\".",
                ]),
                isError: true
            )
        }

        guard let newEntity = try? await knowledgeService.getEntity(
            type: new.type, id: new.id, spaceID: spaceID, agentID: agentID
        ) else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Replacement \(newRaw) not found."]),
                isError: true
            )
        }

        do {
            try await appendKnowledgeRelation(
                "supersedes", targets: ["\(old.type).\(old.id)"], on: newEntity,
                knowledgeService: knowledgeService,
                spaceID: spaceID, agentID: agentID, chatID: chatID
            )
            try await knowledgeService.setExpired(
                type: old.type, id: old.id, expired: true, spaceID: spaceID, agentID: agentID
            )
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(result: [
                    "old": "\(old.type).\(old.id)",
                    "new": "\(new.type).\(new.id)",
                    "status": "superseded",
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
