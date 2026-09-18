import Foundation

struct ListIntentsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "list_intents",
        displayName: Localized.Tools.Agent.listIntents,
        description: Localized.Tools.Description.listIntents,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "list_intents"
    var isSmallContext: Bool = false
    let intentService: any IntentService
    let accessPolicy: SpaceAccessPolicy
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
        .always
    }

    init(
        intentService: any IntentService = PreviewIntentService(),
        accessPolicy: SpaceAccessPolicy = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
    ) {
        self.intentService = intentService
        self.accessPolicy = accessPolicy
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "List your intents — goals you've set for yourself. By default returns only active intents sorted by strength.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "limit": .init(
                        type: "integer",
                        description: "Maximum number of intents to return. Default 10."
                    ),
                    "include_resolved": .init(
                        type: "boolean",
                        description: "Include resolved and dismissed intents. Default false."
                    ),
                ]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id
        let args = ToolHelpers.parseArguments(toolCall.function.arguments)
        let limit = (args?["limit"] as? Int) ?? 10
        let includeResolved = (args?["include_resolved"] as? Bool) ?? false

        do {
            let intents: [IntentSnapshot] = if includeResolved {
                try await intentService.allIntents(
                    agentID: agent.id,
                    limit: limit,
                    accessPolicy: accessPolicy
                )
            } else {
                try await intentService.activeIntents(
                    agentID: agent.id,
                    limit: limit,
                    accessPolicy: accessPolicy
                )
            }
            let now = Date.now
            let items: [[String: Any]] = intents.map { intent in
                var entry: [String: Any] = [
                    "id": intent.id.uuidString,
                    "content": intent.content,
                    "days_active": Int(now.timeIntervalSince(intent.createdAt) / 86400),
                ]
                if !intent.tasks.isEmpty {
                    entry["tasks"] = intent.tasks.map { Self.taskEntry($0) }
                    entry["open_task_count"] = intent.tasks.count { !$0.completed }
                }
                if !intent.events.isEmpty {
                    entry["events"] = intent.events.map { Self.eventEntry($0, now: now) }
                }
                if !intent.schedules.isEmpty {
                    entry["schedules"] = intent.schedules.map { Self.scheduleEntry($0, now: now) }
                }
                if includeResolved {
                    entry["status"] = intent.status.rawValue
                }
                return entry
            }
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["intents": items, "count": items.count]),
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

    private static func taskEntry(_ task: IntentTask) -> [String: Any] {
        var entry: [String: Any] = [
            "id": task.id.uuidString,
            "content": task.content,
            "completed": task.completed,
        ]
        if let due = task.due { entry["due"] = LocalDateFormatter.string(from: due) }
        if let priority = task.priority { entry["priority"] = priority.rawValue }
        if let blockedBy = task.blockedBy { entry["blocked_by"] = blockedBy }
        return entry
    }

    private static func eventEntry(_ event: IntentEvent, now: Date) -> [String: Any] {
        [
            "id": event.id.uuidString,
            "content": event.content,
            "at": LocalDateFormatter.string(from: event.at),
            "in_days": Int((event.at.timeIntervalSince(now) / 86400).rounded()),
        ]
    }

    private static func scheduleEntry(_ schedule: IntentSchedule, now: Date) -> [String: Any] {
        var entry: [String: Any] = [
            "id": schedule.id.uuidString,
            "content": schedule.content,
            "frequency": schedule.frequency.rawValue,
        ]
        if let weekdays = schedule.weekdays { entry["weekdays"] = weekdays }
        if let monthDays = schedule.monthDays { entry["month_days"] = monthDays }
        if let next = schedule.nextOccurrence(onOrAfter: now) {
            entry["next"] = LocalDateFormatter.string(from: next)
        }
        return entry
    }
}
