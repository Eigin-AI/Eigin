import Foundation

/// The user's children as Aula knows them, so the agent has the family context
/// (names, which school/daycare) to reason with.
struct GetAulaChildrenTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "aula_children",
        displayName: Localized.Tools.Aula.children,
        defaultPermissionLevel: .ask, category: .external
    )

    let name = "aula_children"
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
            description: "List the user's children on Aula and the school or daycare each attends.",
            parameters: JSONSchema(type: "object", properties: [:], required: [])
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        do {
            let children = try await provider.children()
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(result: ["children": children.map(\.jsonObject)]),
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
