import Foundation

struct ReadEmailTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "email_read",
        displayName: Localized.Tools.Email.read,
        description: Localized.Tools.Description.emailRead,
        defaultPermissionLevel: .ask, category: .email
    )

    let name = "email_read"
    var isSmallContext: Bool = false
    let provider: any EmailProvider

    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .email
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Read the full content of an email by id.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "id": .init(type: "string", description: "The message id to read."),
                ],
                required: ["id"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id
        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments),
              let messageID = args["id"] as? String, !messageID.isEmpty
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'id' parameter"]),
                isError: true
            )
        }

        do {
            let message = try await provider.readEmail(id: messageID)
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: message.jsonObject),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
