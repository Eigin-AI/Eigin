import Foundation

/// Fold near-duplicate memories into one canonical entry. The duplicates are
/// forgotten and linked to the survivor via `supersedes`.
struct MergeKnowledgeTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "merge_knowledge",
        displayName: Localized.Tools.Merge.knowledge,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "merge_knowledge"
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
            Fold duplicate knowledge entries into one survivor, which records \
            that it supersedes the others; the duplicates are hidden. Update the \
            survivor first if it needs details only the duplicates had.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "into": .init(
                        type: "string",
                        description: "Qualified ID of the entry to keep (e.g. \"thing.eigin\")."
                    ),
                    "from": .init(
                        type: "array",
                        description: "Qualified IDs of the duplicates to fold in and forget.",
                        items: .init(type: "string")
                    ),
                ],
                required: ["into", "from"]
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
        guard let intoRaw = args["into"] as? String, let into = parseQualifiedKnowledgeID(intoRaw)
        else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers
                    .output(errors: ["'into' must be a qualified ID like \"thing.eigin\"."]),
                isError: true
            )
        }
        let fromRaw = (args["from"] as? [String]) ?? []
        let fromParsed = fromRaw.compactMap { parseQualifiedKnowledgeID($0) }
            .filter { "\($0.type).\($0.id)" != "\(into.type).\(into.id)" }
        guard !fromParsed.isEmpty else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: [
                    "'from' must list one or more qualified IDs to merge (excluding 'into').",
                ]),
                isError: true
            )
        }

        guard let intoEntity = try? await knowledgeService.getEntity(
            type: into.type, id: into.id, spaceID: spaceID, agentID: agentID
        ) else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Survivor \(intoRaw) not found."]),
                isError: true
            )
        }

        let targets = fromParsed.map { "\($0.type).\($0.id)" }
        do {
            try await appendKnowledgeRelation(
                "supersedes", targets: targets, on: intoEntity,
                knowledgeService: knowledgeService,
                spaceID: spaceID, agentID: agentID, chatID: chatID
            )
            for dup in fromParsed {
                try await knowledgeService.setExpired(
                    type: dup.type, id: dup.id, expired: true, spaceID: spaceID, agentID: agentID
                )
            }
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(result: [
                    "into": "\(into.type).\(into.id)",
                    "merged": targets,
                    "status": "merged",
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
