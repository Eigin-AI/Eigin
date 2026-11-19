import Foundation
import SwiftData

struct SearchChatTranscriptTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "search_chat_transcript",
        displayName: Localized.Tools.Search.Chat.transcript,
        description: Localized.Tools.Description.searchChatTranscript,
        defaultPermissionLevel: .always, category: .chats
    )

    let name = "search_chat_transcript"
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
            description: "Search user and assistant text in a chat.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "chat_id": .init(
                        type: "string",
                        description: "Chat UUID. Omit to read the current chat."
                    ),
                    "before_message_id": .init(
                        type: "string",
                        description: "Continue searching before this message ID. Use next_before_message_id when returned, including when there are no hits."
                    ),
                    "query": .init(
                        type: "string",
                        description: "Literal text to find, case-insensitive with a fixed locale. Accents are significant. Maximum 500 characters."
                    ),
                    "limit": .init(
                        type: "integer",
                        description: "Maximum number of messages to return. Defaults to 10, capped at 20."
                    ),
                ],
                required: ["query"]
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
            search: true
        )
    }
}
