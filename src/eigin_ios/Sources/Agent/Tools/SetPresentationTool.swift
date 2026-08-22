import Foundation

struct SetPresentationTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "set_presentation",
        displayName: Localized.Tools.Set.presentation,
        defaultPermissionLevel: .ask, category: .agent
    )

    let name = "set_presentation"
    var isSmallContext: Bool = false
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
        .ask
    }

    nonisolated(unsafe) var voiceService: (any VoiceService)?
    var voiceNames: [String]
    nonisolated(unsafe) var knowledgeService: (any KnowledgeService)?
    var agentID: UUID?

    func definition() -> ToolDefinition {
        var properties: [String: JSONSchema.Property] = [
            "name": .init(
                type: "string",
                description: "Your display name. Omit to keep current name."
            ),
            "emoji": .init(
                type: "string",
                description: "A single emoji that represents you. Omit to keep current emoji."
            ),
        ]

        if voiceNames.isEmpty {
            properties["voice"] = .init(
                type: "string",
                description: "Your speaking voice name. Omit to keep current voice."
            )
        } else {
            properties["voice"] = .init(
                type: "string",
                description: "Your speaking voice name. Omit to keep current voice.",
                enum: voiceNames
            )
        }

        return ToolDefinition(
            name: name,
            description: """
            Set your display name, emoji, and/or voice.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: properties
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        if let name = ToolHelpers.stringArgument(toolCall, "name") {
            return ToolDisclosure(
                actionPhrase: Localized.Permission.Disclosure.changeNameTo,
                detail: .inline(name)
            )
        }
        return ToolDisclosure(actionPhrase: Localized.Permission.Disclosure.updateAppearance)
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }

        if let name = args["name"] as? String, !name.isEmpty {
            agent.name = name
            // Sync to the agent's actor entity in the knowledge graph.
            if let ks = knowledgeService {
                Task {
                    await syncAgentActorName(name, knowledgeService: ks, agentID: agentID)
                }
            }
        }
        if let emoji = args["emoji"] as? String, !emoji.isEmpty {
            agent.emoji = String(emoji.prefix(2))
        }
        if let voiceName = args["voice"] as? String, !voiceName.isEmpty {
            if let service = voiceService,
               let identifier = service.bestIdentifier(forName: voiceName)
            {
                agent.voiceIdentifier = identifier
            } else {
                agent.updatedAt = .now
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: ["Unrecognized voice: \(voiceName)"]),
                    isError: true
                )
            }
        }
        agent.updatedAt = .now
        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["status": "OK"]),
            isError: false
        )
    }

    /// Update the agent's actor entity name in the knowledge graph.
    private func syncAgentActorName(
        _ name: String,
        knowledgeService: any KnowledgeService,
        agentID: UUID?
    ) async {
        guard let entity = try? await knowledgeService.getEntity(
            type: "actor", id: "agent", spaceID: nil, agentID: agentID
        ) else { return }

        var updatedFields = entity.fields.map { field -> FirmField in
            if field.name == "name" {
                return FirmField(name: "name", value: .string(value: name))
            }
            return field
        }
        // Add name field if it didn't exist.
        if !updatedFields.contains(where: { $0.name == "name" }) {
            updatedFields.append(FirmField(name: "name", value: .string(value: name)))
        }

        let updated = FirmEntity(
            id: BundledKnowledge.agentActorID,
            entityType: entity.entityType,
            fields: updatedFields
        )
        try? await knowledgeService.addEntity(updated, spaceID: nil, agentID: agentID, chatID: nil)
    }
}
