import Foundation
import SwiftData

struct CreateSpaceTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "create_space",
        displayName: Localized.Tools.Space.create,
        defaultPermissionLevel: .ask, category: .chats
    )

    let name = "create_space"
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
            description: "Create a new space.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "name": .init(type: "string", description: "The space name."),
                    "emoji": .init(type: "string", description: "A single emoji for the space."),
                    "instructions": .init(
                        type: "string", description: "Context and instructions for this space."
                    ),
                    "is_private": .init(
                        type: "boolean", description: "Whether this space is private."
                    ),
                ],
                required: ["name", "emoji", "instructions", "is_private"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let name = ToolHelpers.stringArgument(toolCall, "name") else { return nil }
        let instructions = ToolHelpers.stringArgument(toolCall, "instructions")
        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.createSpaceNamed(name),
            detail: instructions.map { .block($0) }
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }
        guard let name = args["name"] as? String, !name.isEmpty else {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: ["Missing 'name' parameter"]),
                isError: true
            )
        }
        guard let emoji = args["emoji"] as? String, !emoji.isEmpty else {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: ["Missing 'emoji' parameter"]),
                isError: true
            )
        }
        guard let instructions = args["instructions"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'instructions' parameter"]),
                isError: true
            )
        }

        let isPrivate = (args["is_private"] as? Bool) ?? false

        let space = Space(agentID: agent.id)
        space.name = name
        space.emoji = String(emoji.prefix(1))
        space.instructions = instructions
        space.isPrivate = isPrivate
        space.bootstrapComplete = true
        agent.modelContext?.insert(space)

        return ToolResult(
            toolCallID: id, content: ToolHelpers.output(result: ["id": space.id.uuidString]),
            isError: false
        )
    }
}
