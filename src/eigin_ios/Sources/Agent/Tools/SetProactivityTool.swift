import Foundation
import UserNotifications

struct SetProactivityTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "set_proactivity",
        displayName: Localized.Tools.Set.proactivity,
        defaultPermissionLevel: .ask, category: .agent
    )

    let name = "set_proactivity"
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
            description: "Change your background proactivity level.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "level": .init(
                        type: "string",
                        description: "reactive = only respond when user starts a conversation. balanced = middle ground. proactive = more willing to reach out.",
                        enum: ["reactive", "balanced", "proactive"]
                    ),
                ],
                required: ["level"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let level = ToolHelpers.stringArgument(toolCall, "level") else { return nil }
        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.setProactivityTo,
            detail: .inline(level)
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
        guard let levelString = args["level"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'level' parameter"]),
                isError: true
            )
        }

        let level: ProactivityLevel
        switch levelString {
        case "reactive": level = .reactive
        case "balanced": level = .balanced
        case "proactive": level = .proactive
        default:
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(
                        errors: [
                            "Invalid level '\(levelString)'. Must be 'reactive', 'balanced', or 'proactive'.",
                        ]
                    ),
                isError: true
            )
        }

        agent.proactivity = level
        agent.updatedAt = .now

        BackgroundPromptScheduler.reschedule(for: level)

        if level.isBackgroundEnabled {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "level": level.displayName,
                "background_enabled": level.isBackgroundEnabled,
            ]),
            isError: false
        )
    }
}
