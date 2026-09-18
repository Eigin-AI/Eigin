import Foundation
import SwiftData

struct MoveChatToSpaceTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "move_chat_to_space",
        displayName: Localized.Tools.Space.moveChat,
        description: Localized.Tools.Description.moveChatToSpace,
        defaultPermissionLevel: .ask, category: .chats
    )

    let name = "move_chat_to_space"
    var isSmallContext: Bool = false
    let chatID: UUID?
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .chats
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    init(chatID: UUID? = nil) {
        self.chatID = chatID
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Move the current chat into a space, or remove it from its current space.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "space_id": .init(
                        type: "string",
                        description: "The UUID of the target space. Omit or pass null to remove the chat from its current space."
                    ),
                ]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let context = agent.modelContext else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["No model context available"]),
                isError: true
            )
        }

        guard let chatID else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["No active chat"]),
                isError: true
            )
        }

        let args = ToolHelpers.parseArguments(toolCall.function.arguments)
        let spaceIDString = args?["space_id"] as? String

        // Fetch the chat
        let targetChatID = chatID
        var chatDescriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.id == targetChatID }
        )
        chatDescriptor.fetchLimit = 1

        guard let chat = (try? context.fetch(chatDescriptor))?.first else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Chat not found"]),
                isError: true
            )
        }

        // Remove from space
        guard let spaceIDString, let spaceUUID = UUID(uuidString: spaceIDString) else {
            ChatMigration.moveChat(chat, toSpaceID: nil, context: context)
            return ToolResult(toolCallID: id, content: ToolHelpers.output(result: [
                "status": "OK",
                "message": "Chat removed from space. Data from this chat was migrated.",
            ]), isError: false)
        }

        // Validate the space exists and belongs to this agent
        let agentID = agent.id
        let targetSpaceID = spaceUUID
        var spaceDescriptor = FetchDescriptor<Space>(
            predicate: #Predicate { $0.id == targetSpaceID && $0.agentID == agentID }
        )
        spaceDescriptor.fetchLimit = 1

        guard let space = (try? context.fetch(spaceDescriptor))?.first else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(errors: ["Space not found or does not belong to this agent"]),
                isError: true
            )
        }

        ChatMigration.moveChat(chat, toSpaceID: space.id, context: context)

        var note = "Data from this chat was migrated."
        if space.isPrivate {
            note += " This is a private space. Its existing data will not be available until your next turn — if you need to access it, end your turn and it will become available when the user sends their next message."
        }

        return ToolResult(toolCallID: id, content: ToolHelpers.output(result: [
            "status": "OK",
            "space_name": space.name,
            "note": note,
        ]), isError: false)
    }
}
