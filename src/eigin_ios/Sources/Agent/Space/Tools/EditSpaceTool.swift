import Foundation
import SwiftData

struct EditSpaceTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "edit_space",
        displayName: Localized.Tools.Space.edit,
        defaultPermissionLevel: .ask, category: .chats
    )

    let name = "edit_space"
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
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Edit an existing space's name, emoji, or instructions.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "id": .init(type: "string", description: "The UUID of the space to edit."),
                    "name": .init(type: "string", description: "New name for the space."),
                    "emoji": .init(type: "string", description: "New emoji for the space."),
                    "instructions": .init(
                        type: "string",
                        description: "New instructions for the space."
                    ),
                ],
                required: ["id"]
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
        guard let idString = args["id"] as? String, let spaceID = UUID(uuidString: idString) else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Missing or invalid 'id' parameter"]),
                isError: true
            )
        }

        guard let context = agent.modelContext else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["No model context available"]),
                isError: true
            )
        }

        let agentID = agent.id
        let descriptor = FetchDescriptor<Space>(
            predicate: #Predicate { $0.id == spaceID && $0.agentID == agentID }
        )

        guard let space = try? context.fetch(descriptor).first else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Space not found"]),
                isError: true
            )
        }

        if let name = args["name"] as? String, !name.isEmpty {
            space.name = name
        }
        if let emoji = args["emoji"] as? String, !emoji.isEmpty {
            space.emoji = String(emoji.prefix(1))
        }
        if let instructions = args["instructions"] as? String {
            space.instructions = instructions
        }
        space.updatedAt = .now

        return ToolResult(
            toolCallID: callID,
            content: ToolHelpers.output(result: ["status": "OK"]),
            isError: false
        )
    }
}
