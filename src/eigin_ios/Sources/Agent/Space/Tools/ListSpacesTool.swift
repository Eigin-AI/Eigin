import Foundation
import SwiftData

struct ListSpacesTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "list_spaces",
        displayName: Localized.Tools.Space.list,
        description: Localized.Tools.Description.listSpaces,
        defaultPermissionLevel: .always, category: .chats
    )

    let name = "list_spaces"
    var isSmallContext: Bool = false
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

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "List all spaces with IDs, names, and instructions.",
            parameters: JSONSchema(
                type: "object",
                properties: [:]
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

        let agentID = agent.id
        let descriptor = FetchDescriptor<Space>(
            predicate: #Predicate { $0.agentID == agentID && $0.bootstrapComplete },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let spaces = try? context.fetch(descriptor) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Failed to fetch spaces"]),
                isError: true
            )
        }

        let formatter = ISO8601DateFormatter()
        let entries: [[String: Any]] = spaces.map { space in
            var entry: [String: Any] = [
                "id": space.id.uuidString,
                "name": space.name,
                "emoji": space.emoji,
                "created_at": formatter.string(from: space.createdAt),
            ]
            let instructions = space.instructions
            if !instructions.isEmpty {
                entry["instructions"] = instructions.count > 200
                    ? String(instructions.prefix(200)) + "…"
                    : instructions
            }
            return entry
        }

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["spaces": entries]),
            isError: false
        )
    }
}
