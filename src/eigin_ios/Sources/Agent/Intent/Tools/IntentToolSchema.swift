import Foundation

/// Shared parameter schemas for the `tasks` / `events` / `schedules` arrays
/// accepted by both `add_intent` and `update_intent`.
enum IntentToolSchema {
    static let tasks = JSONSchema.Property(
        type: "array",
        description: "Checklist items for this goal. On update, the array you "
            + "send fully replaces the existing tasks — include unchanged items "
            + "(with their id) to keep them.",
        items: .init(
            type: "object",
            properties: [
                "content": .init(type: "string", description: "What needs doing."),
                "due": .init(
                    type: "string",
                    description: "Optional due date, e.g. \"2026-05-20\" or \"2026-05-20 14:00\"."
                ),
                "priority": .init(
                    type: "string",
                    description: "Optional importance.",
                    enum: TaskPriority.allCases.map(\.rawValue)
                ),
                "completed": .init(
                    type: "boolean",
                    description: "Whether it's done. Defaults to false."
                ),
                "blocked_by": .init(
                    type: "string",
                    description: "Optional note on what's holding it up."
                ),
                "id": .init(
                    type: "string",
                    description: "Existing task id — include to preserve identity when updating."
                ),
            ],
            required: ["content"]
        )
    )

    static let events = JSONSchema.Property(
        type: "array",
        description: "One-off dated triggers (a birthday, a deadline). The intent "
            + "is boosted as the date approaches. Replaces existing events on update.",
        items: .init(
            type: "object",
            properties: [
                "content": .init(type: "string", description: "What the event is."),
                "at": .init(
                    type: "string",
                    description: "When it happens, e.g. \"2026-05-25 09:00\"."
                ),
                "id": .init(
                    type: "string",
                    description: "Existing event id — include to preserve identity when updating."
                ),
            ],
            required: ["content", "at"]
        )
    )

    static let schedules = JSONSchema.Property(
        type: "array",
        description: "Recurring triggers (a daily routine, a weekly chore). The "
            + "intent is boosted around each occurrence. Replaces existing schedules on update.",
        items: .init(
            type: "object",
            properties: [
                "content": .init(type: "string", description: "What recurs."),
                "frequency": .init(
                    type: "string",
                    description: "How often it recurs.",
                    enum: ScheduleFrequency.allCases.map(\.rawValue)
                ),
                "weekdays": .init(
                    type: "array",
                    description: "For weekly: days it fires on, 1=Sunday … 7=Saturday."
                ),
                "month_days": .init(
                    type: "array",
                    description: "For monthly: days of the month (1–31)."
                ),
                "hour": .init(type: "integer", description: "Optional hour of day (0–23)."),
                "minute": .init(type: "integer", description: "Optional minute (0–59)."),
                "id": .init(
                    type: "string",
                    description: "Existing schedule id — include to preserve identity when updating."
                ),
            ],
            required: ["content", "frequency"]
        )
    )
}
