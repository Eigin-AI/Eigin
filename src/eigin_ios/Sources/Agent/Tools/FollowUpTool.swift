import Foundation

/// Saves a prepared one-off follow-up with optional system notification delivery.
struct FollowUpTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "follow_up",
        displayName: Localized.Tools.followUp,
        description: Localized.Tools.Description.followUp,
        defaultPermissionLevel: .ask, category: .agent
    )

    let name = "follow_up"
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    let scheduler: any FollowUpScheduling
    var spaceID: UUID?
    var canPromptUser: Bool = true
    var now: @Sendable () -> Date = { Date() }
    var calendar: Calendar = .current

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Save a prepared one-off follow-up for a future time, with optional notification delivery. Delivers your prepared message without running the agent again. Tapping opens a new conversation with your briefing. Use intent initiatives for recurring invitations that start work when opened, the Reminders skill for tracked tasks, and Calendar for events. Clarify the time if needed before calling.",
            parameters: JSONSchema(type: "object", properties: [
                "notification_title": .init(
                    type: "string",
                    description: "Short notification title."
                ),
                "message": .init(
                    type: "string",
                    description: "Prepared notification message, also shown in the new conversation."
                ),
                "summary": .init(
                    type: "string",
                    description: "Self-contained briefing for the new conversation: relevant context, why the user requested this follow-up, and details needed to continue. The original chat history will not be available."
                ),
                "deliver_at": .init(
                    type: "string",
                    description: "Required future ISO 8601 datetime, preferably including timezone. Without a timezone, uses local time."
                ),
            ], required: ["notification_title", "message", "summary", "deliver_at"])
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        do {
            guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
                throw NotificationDeliveryTime.ValidationError(message: "Invalid JSON arguments")
            }
            func text(_ key: String) throws -> String {
                guard let value = args[key] as? String,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw NotificationDeliveryTime
                        .ValidationError(message: "Missing '\(key)' parameter")
                }
                return value
            }
            let title = try text("notification_title")
            let message = try text("message")
            let summary = try text("summary")
            let delivery = try NotificationDeliveryTime.parse(
                args["deliver_at"],
                now: now(),
                calendar: calendar,
                required: true
            )
            let result = try await scheduler.schedule(
                title: title,
                body: message,
                message: message,
                summary: summary,
                deliverAt: delivery,
                agentID: agent.id,
                agentName: agent.name,
                agentEmoji: agent.emoji,
                spaceID: spaceID,
                canPromptUser: canPromptUser
            )
            return ToolResult(toolCallID: toolCall.id, content: ToolHelpers.output(result: [
                "status": "saved",
                "delivery_status": result.deliveryStatus.rawValue,
                "request_id": result.requestID.uuidString,
                "scheduled_for": ISO8601DateFormatter().string(from: delivery),
            ]), isError: false)
        } catch {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
