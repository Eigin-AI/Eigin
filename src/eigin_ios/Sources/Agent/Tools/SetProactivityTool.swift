import Foundation

/// Asks for notification authorization when the agent gains background access.
/// Injectable so tests can install a stub instead of the system authorizer.
protocol NotificationAuthorizing: Sendable {
    func requestIfNeeded() async -> Bool
}

struct SystemNotificationAuthorizer: NotificationAuthorizing {
    func requestIfNeeded() async -> Bool {
        await NotificationPermission.requestIfNeeded()
    }
}

struct SetProactivityTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "set_proactivity",
        displayName: Localized.Tools.Set.proactivity,
        description: Localized.Tools.Description.setProactivity,
        defaultPermissionLevel: .ask, category: .agent
    )

    let name = "set_proactivity"
    var isSmallContext: Bool = false
    var notificationAuthorizer: any NotificationAuthorizing

    init(notificationAuthorizer: any NotificationAuthorizing = SystemNotificationAuthorizer()) {
        self.notificationAuthorizer = notificationAuthorizer
    }

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
        ProactivityDecision.markDecided()

        BackgroundPromptScheduler.reschedule(for: level)

        if level.isBackgroundEnabled {
            _ = await notificationAuthorizer.requestIfNeeded()
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
