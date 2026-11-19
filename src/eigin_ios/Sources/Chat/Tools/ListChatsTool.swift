import Foundation
import SwiftData

struct ListChatsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "list_chats",
        displayName: Localized.Tools.List.chats,
        description: Localized.Tools.Description.listChats,
        defaultPermissionLevel: .always, category: .chats
    )

    let name = "list_chats"
    var isSmallContext: Bool = false
    let spaceID: UUID?
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

    init(spaceID: UUID? = nil, accessPolicy: SpaceAccessPolicy? = nil) {
        self.spaceID = spaceID
        self.accessPolicy = accessPolicy
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "List recent chats with IDs and titles.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "limit": .init(
                        type: "integer",
                        description: "Maximum number of chats to return. Defaults to 10."
                    ),
                ]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        let args = ToolHelpers.parseArguments(toolCall.function.arguments)
        let limit = min(50, max(1, (args?["limit"] as? Int) ?? 10))

        guard let context = agent.modelContext else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["No model context available"]),
                isError: true
            )
        }

        let agentID = agent.id
        let chatSpaceID = spaceID
        var descriptor = if let chatSpaceID {
            FetchDescriptor<Chat>(
                predicate: #Predicate { $0.agentID == agentID && $0.spaceID == chatSpaceID },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        } else {
            FetchDescriptor<Chat>(
                predicate: #Predicate { $0.agentID == agentID },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        }
        descriptor.fetchLimit = 50
        var chats: [Chat] = []
        do {
            while chats.count < limit {
                let page = try context.fetch(descriptor)
                chats += page.filter { accessPolicy?.canAccess(itemSpaceID: $0.spaceID) != false }
                    .prefix(limit - chats.count)
                if page.count < 50 { break }
                descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + page.count
            }
        } catch {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Failed to fetch chats"]),
                isError: true
            )
        }

        let formatter = ISO8601DateFormatter()
        let entries: [[String: Any]] = chats.map { chat in
            [
                "id": chat.id.uuidString,
                "title": chat.title,
                "updated_at": formatter.string(from: chat.updatedAt),
            ]
        }

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["chats": entries]),
            isError: false
        )
    }
}
