import Foundation

/// The primary Aula tool: a single digest of what's new and what's coming up
/// for the user's children, so the agent doesn't have to stitch messages,
/// notifications, calendar, and posts together itself.
struct GetAulaUpdatesTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "aula_updates",
        displayName: Localized.Tools.Aula.updates,
        defaultPermissionLevel: .ask, category: .external
    )

    /// Fallback for the `days` parameter when the agent omits it.
    static let defaultDays = 7

    let name = "aula_updates"
    var isSmallContext: Bool = false
    let provider: any AulaProvider

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
            description: """
            Get a digest of recent and upcoming school/daycare activity from \
            Aula: unread and recent messages, notifications, upcoming calendar \
            events, and recent posts for the user's children.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "days": .init(
                        type: "integer",
                        description: "How many days ahead to include calendar events for."
                    ),
                ],
                required: []
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let args = ToolHelpers.parseArguments(toolCall.function.arguments)
        let days = (args?["days"] as? Int) ?? Self.defaultDays
        do {
            let digest = try await provider.updates(days: days)
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(result: digest.jsonObject),
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
