import Foundation

/// Lists Aula message threads so the agent can scan them cheaply before
/// pulling a full thread with `aula_message_read`.
struct ListAulaMessagesTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "aula_messages_list",
        displayName: Localized.Tools.Aula.listMessages,
        defaultPermissionLevel: .ask, category: .external
    )

    let name = "aula_messages_list"
    var isSmallContext: Bool = false
    let provider: any AulaProvider

    /// Fallback for the `limit` parameter when the agent omits it.
    static let defaultLimit = 20

    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .external
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "List recent Aula message threads (subject, sender, unread status).",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "limit": .init(
                        type: "integer",
                        description: "Maximum number of threads to return."
                    ),
                ],
                required: []
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let args = ToolHelpers.parseArguments(toolCall.function.arguments)
        let limit = (args?["limit"] as? Int) ?? Self.defaultLimit
        do {
            let messages = try await provider.listMessages(limit: limit)
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(result: ["threads": messages.map(\.jsonObject)]),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
