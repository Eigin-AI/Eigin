import Foundation

/// Manages explicit recurring notifications without exposing calendar trigger machinery.
struct SetInitiativesTool: InitiativeTool {
    static let toolName = "set_initiatives"
    let service: InitiativeService
    let spaceID: UUID?
    let canPromptUser: Bool

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Create or update recurring initiatives that start agreed work when opened. Use intent and schedule IDs from add_intent/update_intent or list_intents. Only change agreed times with consent, and confirm scheduling after success.",
            parameters: JSONSchema(type: "object", properties: [
                "changes": .init(
                    type: "array",
                    description: "Approved agreement changes; batch shared-time changes together.",
                    items: .init(type: "object", properties: [
                        "intent_id": .init(
                            type: "string",
                            description: "Existing intent UUID returned by add_intent/update_intent or list_intents."
                        ),
                        "schedule_id": .init(
                            type: "string",
                            description: "Schedule UUID from the intent tool response's schedules[].id or list_intents; not a name or label."
                        ),
                        "instructions": .init(
                            type: "string",
                            description: "Work to start when opened; use current information."
                        ),
                        "notification": .init(
                            type: "string",
                            description: "Short, task-appropriate invitation, aiming for 40–50 characters (maximum 200). Also used as the initiative title and initial chat title, so lead with the topic. Keep it accurate and pleasant across repeated occurrences; never claim unfinished work is ready."
                        ),
                        "frequency": .init(
                            type: "string",
                            description: "Optional schedule change; otherwise retain current recurrence.",
                            enum: ["daily", "weekly"]
                        ),
                        "daily_pattern": .init(
                            type: "string",
                            description: "Daily day selection.",
                            enum: InitiativeDailyPattern.allCases.map(\.rawValue)
                        ),
                        "weekdays": .init(
                            type: "array",
                            description: "Weekly days: 1=Sunday through 7=Saturday.",
                            items: .init(type: "integer")
                        ),
                        "hour": .init(
                            type: "integer",
                            description: "Device-local hour 0–23; provide with minute to change time."
                        ),
                        "minute": .init(type: "integer", description: "Minute 0–59."),
                    ], required: ["intent_id", "schedule_id", "instructions", "notification"])
                ),
            ], required: ["changes"])
        )
    }

    @MainActor func execute(_ call: ToolCall, agent: Agent) async -> ToolResult {
        var changesState = InitiativeOperationFailure.ChangesState.notSaved
        do {
            guard let args = ToolHelpers.parseArguments(call.function.arguments),
                  let values = args["changes"] as? [[String: Any]], !values.isEmpty,
                  values.count <= 20 else { throw InitiativeError.invalidChanges }
            let changes = try values.map { try parse($0, agentID: agent.id) }
            _ = try await service.apply(
                changes,
                agentID: agent.id,
                spaceID: spaceID,
                canPromptUser: canPromptUser
            )
            changesState = .saved
            return try await success(call, agent: agent)
        } catch {
            return await failure(call, agent: agent, error: error, changesState: changesState)
        }
    }

    @MainActor private func parse(
        _ value: [String: Any],
        agentID: UUID
    ) throws -> InitiativeChange {
        guard let intentText = value["intent_id"] as? String,
              let intentID = UUID(uuidString: intentText)
        else { throw InitiativeError.invalidIntentID }
        guard let scheduleText = value["schedule_id"] as? String,
              let scheduleID = UUID(uuidString: scheduleText)
        else { throw InitiativeError.invalidScheduleID }
        guard let instructions = value["instructions"] as? String,
              let body = value["notification"] as? String
        else { throw InitiativeError.invalidContent }
        var schedule = try service.schedule(
            intentID: intentID,
            scheduleID: scheduleID,
            agentID: agentID,
            spaceID: spaceID
        )
        if value["frequency"] != nil {
            guard let frequency = value["frequency"] as? String,
                  let parsed = ScheduleFrequency(rawValue: frequency)
            else { throw InitiativeScheduleError.unsupportedMonthlySchedule }
            schedule.frequency = parsed
            if parsed == .daily { schedule.weekdays = nil }
        }
        if value["daily_pattern"] != nil {
            guard value["weekdays"] == nil,
                  value["frequency"] == nil || value["frequency"] as? String == "daily",
                  let text = value["daily_pattern"] as? String,
                  let pattern = InitiativeDailyPattern(rawValue: text)
            else { throw InitiativeScheduleError.invalidWeekdays }
            schedule.frequency = pattern == .everyDay ? .daily : .weekly
            schedule.weekdays = pattern == .everyDay ? nil : pattern.weekdays
        }
        if value["weekdays"] != nil {
            guard value["daily_pattern"] == nil,
                  value["frequency"] == nil || value["frequency"] as? String == "weekly",
                  let days = value["weekdays"] as? [Int]
            else { throw InitiativeScheduleError.invalidWeekdays }
            schedule.frequency = .weekly
            schedule.weekdays = days
        }
        if value["hour"] != nil || value["minute"] != nil {
            guard let hour = value["hour"] as? Int,
                  let minute = value["minute"] as? Int
            else { throw InitiativeScheduleError.explicitTimeRequired }
            schedule.hour = hour
            schedule.minute = minute
        }
        return InitiativeChange(
            intentID: intentID,
            scheduleID: scheduleID,
            instructions: instructions,
            body: body,
            schedule: schedule
        )
    }
}
