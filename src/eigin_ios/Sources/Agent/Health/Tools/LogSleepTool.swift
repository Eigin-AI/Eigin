import Foundation

struct LogSleepTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "log_sleep",
        displayName: Localized.Tools.Log.sleep,
        defaultPermissionLevel: .ask, category: .system
    )

    let name = "log_sleep"
    var isSmallContext: Bool = false
    let healthService: (any HealthService)?
    let canPromptUser: Bool
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .system
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Log a night's sleep to Apple Health as a single asleep interval, from when the user fell asleep to when they woke up.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "start": .init(
                        type: "string",
                        description: "When sleep started (e.g. \"2026-04-12 23:15\")."
                    ),
                    "end": .init(
                        type: "string",
                        description: "When the user woke up (e.g. \"2026-04-13 07:00\")."
                    ),
                ],
                required: ["start", "end"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let service = healthService else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Health service unavailable."]), isError: true
            )
        }

        let auth = await service.authorize(canPromptUser: canPromptUser)
        if case .denied(let reason) = auth {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: [reason]), isError: true
            )
        }

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: ["Invalid JSON arguments."]),
                isError: true
            )
        }

        guard let startString = args["start"] as? String,
              let start = LocalDateFormatter.parse(startString)
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or invalid 'start' date/time."]),
                isError: true
            )
        }

        guard let endString = args["end"] as? String,
              let end = LocalDateFormatter.parse(endString)
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or invalid 'end' date/time."]),
                isError: true
            )
        }

        guard end > start else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["'end' must be after 'start'."]),
                isError: true
            )
        }

        do {
            try await service.logSleep(start: start, end: end)

            let result: [String: Any] = [
                "logged": true,
                "start": LocalDateFormatter.string(from: start),
                "end": LocalDateFormatter.string(from: end),
                "duration_hours": end.timeIntervalSince(start) / 3600,
            ]

            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(result: result), isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
