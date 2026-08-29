import Foundation
import SwiftData

struct GetKnowledgeTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_knowledge",
        displayName: Localized.Tools.Knowledge.get,
        defaultPermissionLevel: .always, category: .knowledge
    )

    let name = "get_knowledge"
    let knowledgeService: any KnowledgeService
    let spaceID: UUID?
    let agentID: UUID?
    var isSmallContext: Bool = false
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
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Get a knowledge entry by type and ID.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "type": .init(
                            type: "string",
                            description: "Knowledge type.",
                            enum: ["actor", "thing", "fact", "output", "note"]
                        ),
                        "id": .init(type: "string", description: "Entity ID."),
                    ],
                    required: ["type", "id"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: """
            Get full details for a single piece of knowledge by type and ID. \
            Always returns all fields and the complete relationship ID lists. \
            Optionally include expanded details of the top related entities \
            and/or surrounding chat context from when this entry was created.
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
                        description: "Knowledge ID (e.g. \"daniel_rothmann\", \"eigin\")."
                    ),
                    "include_related": .init(
                        type: "boolean",
                        description: "If true, include full details of the top related entities (sorted by recency). Defaults to false."
                    ),
                    "related_limit": .init(
                        type: "integer",
                        description: "Maximum related entities to expand when include_related is true. Defaults to 5."
                    ),
                    "include_context": .init(
                        type: "boolean",
                        description: "If true and this entry was created in a chat, include surrounding messages from that chat. Defaults to false."
                    ),
                    "context_characters": .init(
                        type: "integer",
                        description: "Total characters of surrounding chat context to include. Split evenly before/after the entry. Defaults to 2000."
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
        // Strip type prefix if included (e.g. "actor.daniel" → "daniel").
        if entityID.hasPrefix("\(entityType).") {
            entityID = String(entityID.dropFirst(entityType.count + 1))
        }

        let includeRelated = (args["include_related"] as? Bool) ?? false
        let relatedLimit = (args["related_limit"] as? Int) ?? 5
        let includeContext = (args["include_context"] as? Bool) ?? false
        let contextCharacters = (args["context_characters"] as? Int) ?? 2000

        do {
            guard let entity = try await knowledgeService.getEntity(
                type: entityType,
                id: entityID,
                spaceID: spaceID,
                agentID: agentID
            ) else {
                return ToolResult(
                    toolCallID: callID,
                    content: ToolHelpers
                        .output(errors: ["Knowledge entry '\(entityType).\(entityID)' not found"]),
                    isError: true
                )
            }

            // Direct recall — the strongest use signal.
            await knowledgeService.recordAccess(
                type: entityType,
                id: entityID,
                kind: .direct,
                spaceID: spaceID,
                agentID: agentID
            )

            var result = await formatKnowledgeEntityWithRelations(
                entity,
                knowledgeService: knowledgeService,
                spaceID: spaceID,
                agentID: agentID,
                includeRelatedDetail: includeRelated,
                relatedLimit: relatedLimit
            )

            // Look up the FirmSource for chatID and context expansion.
            if let source = try await knowledgeService.getFirmSource(
                type: entityType,
                id: entityID,
                spaceID: spaceID,
                agentID: agentID
            ) {
                if let chatID = source.chatID {
                    result["chat_id"] = chatID.uuidString
                }

                if includeContext, let chatID = source.chatID, let context = agent.modelContext {
                    let surroundingContext = fetchSurroundingContext(
                        chatID: chatID,
                        anchor: source.createdAt,
                        agentID: agent.id,
                        budget: contextCharacters,
                        context: context
                    )
                    if let surroundingContext {
                        result["surrounding_context"] = surroundingContext
                    }
                }
            }

            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(result: result),
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

    // MARK: - Chat context expansion

    /// Fetch messages surrounding the entry's creation timestamp, within a character budget.
    @MainActor private func fetchSurroundingContext(
        chatID: UUID, anchor: Date, agentID: UUID,
        budget: Int, context: ModelContext
    ) -> String? {
        // Verify the chat exists and belongs to this agent.
        var chatDescriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.id == chatID }
        )
        chatDescriptor.fetchLimit = 1

        guard let chat = (try? context.fetch(chatDescriptor))?.first,
              chat.agentID == agentID
        else {
            return nil
        }

        // Fetch user/assistant messages sorted by timestamp ascending.
        let fetchChatID = chatID
        let messageDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate { message in
                message.chat?.id == fetchChatID
                    && (message.role == "user" || message.role == "assistant")
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        guard let messages = try? context.fetch(messageDescriptor), !messages.isEmpty else {
            return nil
        }

        // Find the message closest to the anchor timestamp.
        let anchorIndex = messages.enumerated().min(by: {
            abs($0.element.timestamp.timeIntervalSince(anchor))
                < abs($1.element.timestamp.timeIntervalSince(anchor))
        })!.offset

        let halfBudget = budget / 2

        // Walk backward from anchor.
        var beforeLines: [String] = []
        var beforeChars = 0
        for i in stride(from: anchorIndex - 1, through: 0, by: -1) {
            let line = formatContextMessage(messages[i])
            if beforeChars + line.count > halfBudget { break }
            beforeLines.insert(line, at: 0)
            beforeChars += line.count
        }

        // Walk forward from anchor (inclusive).
        var afterLines: [String] = []
        var afterChars = 0
        for i in anchorIndex ..< messages.count {
            let line = formatContextMessage(messages[i])
            if afterChars + line.count > halfBudget { break }
            afterLines.append(line)
            afterChars += line.count
        }

        let allLines = beforeLines + afterLines
        guard !allLines.isEmpty else { return nil }
        return allLines.joined(separator: "\n\n")
    }

    private func formatContextMessage(_ message: Message) -> String {
        let cleaned = ChatTags.stripAll(from: message.content)
        let speaker = message.role == "user" ? "User" : "Assistant"
        return "\(speaker): \(cleaned)"
    }
}
