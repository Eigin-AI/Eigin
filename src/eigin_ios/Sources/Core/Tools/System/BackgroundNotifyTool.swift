import Foundation

/// Result of a background prompt run.
enum BackgroundToolSignal {
    case notify(title: String, message: String, summary: String, deliverAt: Date?)
}

/// Background-only tool: agent calls this when it has something worth sharing.
/// Fires a callback — NOT registered in ToolRegistry.
struct BackgroundNotifyTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "background_notify",
        displayName: Localized.Tools.System.backgroundNotify,
        description: Localized.Tools.Description.backgroundNotify,
        defaultPermissionLevel: .always, category: .agent, isUserConfigurable: false
    )

    let name = "background_notify"
    var displayName: String {
        Self.capability.displayName
    }

    let onSignal: @Sendable (BackgroundToolSignal) -> Void

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Send a notification to the user.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "notification_title": .init(
                        type: "string",
                        description: "Short title for the notification (max ~50 characters)."
                    ),
                    "message": .init(
                        type: "string",
                        description: "The message shown when the user opens the chat. Keep it concise — 1-3 sentences, no filler."
                    ),
                    "summary": .init(
                        type: "string",
                        description: "This is the ONLY context you will have in the follow-up conversation — there is no chat history. Write a thorough, self-contained briefing: full background and motivation, what tools/sources you used, what you found (in detail, not compressed), your reasoning and conclusions, and open questions. The richer this is, the better you can help the user when they respond."
                    ),
                    "deliver_at": .init(
                        type: "string",
                        description: "Optional ISO 8601 datetime for when to deliver the notification (e.g. \"2025-03-15T09:00:00\"). If omitted, delivers immediately. Use this to schedule timely reminders."
                    ),
                ],
                required: ["notification_title", "message", "summary"]
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
        guard let title = args["notification_title"] as? String, !title.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'notification_title' parameter"]),
                isError: true
            )
        }
        guard let message = args["message"] as? String, !message.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'message' parameter"]),
                isError: true
            )
        }
        guard let summary = args["summary"] as? String, !summary.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'summary' parameter"]),
                isError: true
            )
        }

        var deliverAt: Date?
        if let deliverString = args["deliver_at"] as? String, !deliverString.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            deliverAt = formatter.date(from: deliverString)
            if deliverAt == nil {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                deliverAt = formatter.date(from: deliverString)
            }
            if deliverAt == nil {
                // Try date + time without timezone (assume local)
                let local = DateFormatter()
                local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                local.timeZone = .current
                deliverAt = local.date(from: deliverString)
            }
            if deliverAt == nil {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers
                        .output(
                            errors: ["Could not parse 'deliver_at' as a date. Use ISO 8601 format."]
                        ),
                    isError: true
                )
            }
        }

        onSignal(.notify(title: title, message: message, summary: summary, deliverAt: deliverAt))

        var result: [String: Any] = ["status": "notification_queued"]
        if let deliverAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            result["scheduled_for"] = formatter.string(from: deliverAt)
        }

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: result),
            isError: false
        )
    }
}
