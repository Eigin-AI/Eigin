import Foundation

struct EditCoreTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "edit_core",
        displayName: Localized.Tools.Edit.core,
        defaultPermissionLevel: .ask, category: .agent
    )

    let name = "edit_core"
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

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Edit one of your core texts by replacing a specific string.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "core": .init(
                        type: "string",
                        description: "Which core text to edit.",
                        enum: ["identity", "user", "soul"]
                    ),
                    "old_string": .init(
                        type: "string",
                        description: "The exact string to find and replace. Read the core text first to see its current content."
                    ),
                    "new_string": .init(
                        type: "string",
                        description: "The replacement string."
                    ),
                ],
                required: ["core", "old_string", "new_string"]
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
        guard let core = args["core"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'core' parameter"]),
                isError: true
            )
        }
        guard let oldString = args["old_string"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'old_string' parameter"]),
                isError: true
            )
        }
        guard let newString = args["new_string"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'new_string' parameter"]),
                isError: true
            )
        }

        let current: String
        switch core {
        case "identity": current = agent.identityCore
        case "user": current = agent.userCore
        case "soul": current = agent.soulCore
        default:
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Unknown core: \(core)"]),
                isError: true
            )
        }

        let updated: String
        var warnings: [String]?

        if oldString.isEmpty {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [
                    "old_string cannot be empty. Read the core text first, then replace the content you want to change.",
                ]),
                isError: true
            )
        } else {
            let occurrences = current.components(separatedBy: oldString).count - 1
            if occurrences == 0 {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers
                        .output(errors: ["old_string not found in \(core) core text"]),
                    isError: true
                )
            }
            if occurrences > 1 {
                warnings = ["Found \(occurrences) matches; replaced only the first."]
            }
            if let range = current.range(of: oldString) {
                updated = current.replacingCharacters(in: range, with: newString)
            } else {
                updated = current
            }
        }

        switch core {
        case "identity": agent.identityCore = updated
        case "user": agent.userCore = updated
        case "soul": agent.soulCore = updated
        default: break
        }
        agent.updatedAt = .now

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["status": "OK"], warnings: warnings),
            isError: false
        )
    }
}
