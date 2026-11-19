import Foundation
import SwiftData

struct GetChatTranscriptTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_chat_transcript",
        displayName: Localized.Tools.Get.Chat.transcript,
        description: Localized.Tools.Description.getChatTranscript,
        defaultPermissionLevel: .always, category: .chats
    )

    let name = "get_chat_transcript"
    var isSmallContext: Bool = false
    let spaceID: UUID?
    let currentChatID: UUID?
    let accessPolicy: SpaceAccessPolicy?
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
        .always
    }

    init(spaceID: UUID? = nil, currentChatID: UUID? = nil, accessPolicy: SpaceAccessPolicy? = nil) {
        self.spaceID = spaceID
        self.currentChatID = currentChatID
        self.accessPolicy = accessPolicy
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Read user and assistant text from a chat.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "chat_id": .init(
                        type: "string",
                        description: "Chat UUID. Omit to read the current chat."
                    ),
                    "before_message_id": .init(
                        type: "string",
                        description: "Read messages before this message ID."
                    ),
                    "around_message_id": .init(
                        type: "string",
                        description: "Read surrounding messages, including this message ID. Mutually exclusive with before_message_id."
                    ),
                    "read_message_id": .init(
                        type: "string",
                        description: "Read one complete message in bounded chunks. Cannot be combined with before/around."
                    ),
                    "content_offset": .init(
                        type: "integer",
                        description: "Character offset for read_message_id. Defaults to 0. Continue with next_content_offset."
                    ),
                    "limit": .init(
                        type: "integer",
                        description: "Maximum number of messages to return. Defaults to 10, capped at 20."
                    ),
                ],
                required: []
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        ChatTranscriptAccess.execute(
            toolCall,
            agent: agent,
            spaceID: spaceID,
            currentChatID: currentChatID,
            accessPolicy: accessPolicy,
            search: false
        )
    }
}
