import Foundation

/// Aula calendar events for the user's children within a date range.
struct GetAulaCalendarTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "aula_calendar",
        displayName: Localized.Tools.Aula.calendar,
        defaultPermissionLevel: .ask, category: .external
    )

    let name = "aula_calendar"
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
            description: "List Aula calendar events for the user's children between two dates (school events, closing days, activities).",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "from": .init(
                        type: "string",
                        description: "Start date, ISO-8601 (YYYY-MM-DD)."
                    ),
                    "to": .init(
                        type: "string",
                        description: "End date, ISO-8601 (YYYY-MM-DD). Keep within ~2 weeks of 'from'."
                    ),
                ],
                required: ["from", "to"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments),
              let from = args["from"] as? String, !from.isEmpty,
              let to = args["to"] as? String, !to.isEmpty
        else {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(errors: ["Missing 'from' or 'to' parameter"]),
                isError: true
            )
        }
        do {
            let events = try await provider.calendar(from: from, to: to)
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(result: ["events": events.map(\.jsonObject)]),
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
