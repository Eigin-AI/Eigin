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

    init(spaceID: UUID? = nil) {
        self.spaceID = spaceID
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Get recent messages from a chat by ID.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "chat_id": .init(
                        type: "string",
                        description: "The UUID of the chat to retrieve."
                    ),
                    "limit": .init(
                        type: "integer",
                        description: "Maximum number of messages to return. Defaults to 10."
                    ),
                ],
                required: ["chat_id"]
            )
        )
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
        guard let chatIDString = args["chat_id"] as? String,
              let chatID = UUID(uuidString: chatIDString)
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or invalid 'chat_id' parameter"]),
                isError: true
            )
        }

        let limit = (args["limit"] as? Int) ?? 10

        guard let context = agent.modelContext else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["No model context available"]),
                isError: true
            )
        }

        // Fetch the chat and verify ownership
        var chatDescriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.id == chatID }
        )
        chatDescriptor.fetchLimit = 1

        guard let chat = (try? context.fetch(chatDescriptor))?.first else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Chat not found"]),
                isError: true
            )
        }

        guard chat.agentID == agent.id else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Chat not found"]),
                isError: true
            )
        }

        // Space scoping: if tool has a spaceID, verify the chat belongs to that space
        if let chatSpaceID = spaceID, chat.spaceID != chatSpaceID {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Chat not found"]),
                isError: true
            )
        }

        // Fetch messages sorted by timestamp descending, limited
        let fetchChatID = chat.id
        var messageDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate { message in
                message.chat?.id == fetchChatID
                    && (message.role == "user" || message.role == "assistant")
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        messageDescriptor.fetchLimit = limit

        guard let messages = try? context.fetch(messageDescriptor) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Failed to fetch messages"]),
                isError: true
            )
        }

        // Reverse to chronological order (oldest first in the window)
        let chronological = messages.reversed()

        // Format transcript lines
        let lines: [String] = chronological.map { message in
            let cleaned = ChatTags.stripAll(from: message.content)
            let speaker = message.role == "user" ? "User" : "Assistant"
            return "\(speaker): \(cleaned)"
        }

        var transcript = lines.joined(separator: "\n\n")

        // Truncation: max 10,000 characters, cut from the top (oldest messages)
        let maxLength = 10000
        var warnings: [String]? = nil
        if transcript.count > maxLength {
            let excess = transcript.count - maxLength
            let startIndex = transcript.index(transcript.startIndex, offsetBy: excess)
            transcript = String(transcript[startIndex...])
            // Trim to the next complete line
            if let newlineIndex = transcript.firstIndex(of: "\n") {
                transcript = String(transcript[transcript.index(after: newlineIndex)...])
            }
            transcript = "[earlier messages omitted]\n\n" + transcript
            warnings =
                [
                    "Transcript exceeds 10,000 character limit. Some earlier messages were omitted. Use a smaller limit to get a focused excerpt.",
                ]
        }

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["transcript": transcript], warnings: warnings),
            isError: false
        )
    }
}
