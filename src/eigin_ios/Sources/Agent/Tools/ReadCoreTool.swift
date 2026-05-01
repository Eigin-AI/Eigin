import Foundation

struct ReadCoreTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "read_core",
        displayName: Localized.Tools.Read.core,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "read_core"
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
        .always
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Read one of your core texts.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "core": .init(
                        type: "string",
                        description: "Which core text to read.",
                        enum: ["identity", "user", "soul"]
                    ),
                ],
                required: ["core"]
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

        switch core {
        case "identity":
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["content": agent.identityCore]),
                isError: false
            )
        case "user":
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["content": agent.userCore]),
                isError: false
            )
        case "soul":
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["content": agent.soulCore]),
                isError: false
            )
        default:
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(errors: ["Unknown core: \(core). Use 'identity', 'user', or 'soul'."]),
                isError: true
            )
        }
    }
}
