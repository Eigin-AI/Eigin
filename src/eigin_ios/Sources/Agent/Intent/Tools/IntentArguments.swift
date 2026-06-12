import Foundation

/// Parses the nested `tasks` / `events` / `schedules` arrays that the
/// `add_intent` and `update_intent` tools accept, turning loosely-typed JSON
/// into the strongly-typed value models and rejecting malformed items.
///
/// Each parser returns `nil` when the field is absent (so callers can tell
/// "leave untouched" from "set to empty"), and throws ``IntentArgumentError``
/// with an agent-readable message when an item is malformed.
enum IntentArguments {
    static func tasks(from raw: Any?) throws -> [IntentTask]? {
        guard let raw else { return nil }
        let items = try array(raw, field: "tasks")
        return try items.map { item in
            guard let content = nonEmptyString(item["content"]) else {
                throw IntentArgumentError("Each task needs a non-empty 'content'.")
            }
            return IntentTask(
                id: uuid(item["id"]),
                content: content,
                due: date(item["due"]),
                priority: priority(item["priority"]),
                completed: (item["completed"] as? Bool) ?? false,
                blockedBy: nonEmptyString(item["blocked_by"])
            )
        }
    }

    static func events(from raw: Any?) throws -> [IntentEvent]? {
        guard let raw else { return nil }
        let items = try array(raw, field: "events")
        return try items.map { item in
            guard let content = nonEmptyString(item["content"]) else {
                throw IntentArgumentError("Each event needs a non-empty 'content'.")
            }
            guard let at = date(item["at"]) else {
                throw IntentArgumentError(
                    "Event \"\(content)\" needs a valid 'at' date (e.g. \"2026-05-25 09:00\")."
                )
            }
            return IntentEvent(id: uuid(item["id"]), content: content, at: at)
        }
    }

    static func schedules(from raw: Any?) throws -> [IntentSchedule]? {
        guard let raw else { return nil }
        let items = try array(raw, field: "schedules")
        return try items.map { item in
            guard let content = nonEmptyString(item["content"]) else {
                throw IntentArgumentError("Each schedule needs a non-empty 'content'.")
            }
            guard let frequencyRaw = item["frequency"] as? String,
                  let frequency = ScheduleFrequency(rawValue: frequencyRaw.lowercased())
            else {
                throw IntentArgumentError(
                    "Schedule \"\(content)\" needs a 'frequency' of daily, weekly, or monthly."
                )
            }
            return IntentSchedule(
                id: uuid(item["id"]),
                content: content,
                frequency: frequency,
                weekdays: ints(item["weekdays"]),
                monthDays: ints(item["month_days"]),
                hour: item["hour"] as? Int,
                minute: item["minute"] as? Int
            )
        }
    }

    // MARK: - Helpers

    private static func array(_ raw: Any, field: String) throws -> [[String: Any]] {
        guard let items = raw as? [[String: Any]] else {
            throw IntentArgumentError("'\(field)' must be an array of objects.")
        }
        return items
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func uuid(_ value: Any?) -> UUID {
        (value as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap { LocalDateFormatter.parse($0) }
    }

    private static func priority(_ value: Any?) -> TaskPriority? {
        (value as? String).flatMap { TaskPriority(rawValue: $0.lowercased()) }
    }

    private static func ints(_ value: Any?) -> [Int]? {
        guard let array = value as? [Any] else { return nil }
        let ints = array.compactMap { $0 as? Int }
        return ints.isEmpty ? nil : ints
    }
}

struct IntentArgumentError: LocalizedError {
    let message: String
    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
