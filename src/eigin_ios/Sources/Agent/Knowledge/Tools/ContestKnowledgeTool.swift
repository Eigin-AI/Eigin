import Foundation

/// Flag memories as contested: a conflict the agent couldn't resolve on its own
/// and has asked the user about. Marking them stops consolidation re-detecting
/// and re-asking the same question every run. Clears when the conflict resolves.
struct ContestKnowledgeTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "contest_knowledge",
        displayName: Localized.Tools.Contest.knowledge,
        defaultPermissionLevel: .always, category: .knowledge
    )

    let name = "contest_knowledge"
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
            Flag two or more conflicting knowledge entries you can't resolve \
            yourself. Pair with background_notify to ask the user to decide. \
            Flagged entries aren't raised again until resolved.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "ids": .init(
                        type: "array",
                        description: "Qualified IDs of the conflicting entries (e.g. [\"fact.a\", \"fact.b\"]).",
                        items: .init(type: "string")
                    ),
                ],
                required: ["ids"]
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
        let raw = (args["ids"] as? [String]) ?? []
        let parsed = raw.compactMap { parseQualifiedKnowledgeID($0) }
        guard parsed.count >= 2 else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: [
                    "'ids' must list at least two qualified IDs like \"fact.a\".",
                ]),
                isError: true
            )
        }

        var flagged: [String] = []
        for entry in parsed {
            do {
                try await knowledgeService.setContested(
                    type: entry.type, id: entry.id, contested: true,
                    spaceID: spaceID, agentID: agentID
                )
                flagged.append("\(entry.type).\(entry.id)")
            } catch {
                // Skip entries that can't be flagged; report what we could.
                continue
            }
        }

        guard !flagged.isEmpty else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers
                    .output(errors: ["None of the given entries could be flagged."]),
                isError: true
            )
        }

        return ToolResult(
            toolCallID: callID,
            content: ToolHelpers.output(result: ["contested": flagged, "status": "flagged"]),
            isError: false
        )
    }
}
