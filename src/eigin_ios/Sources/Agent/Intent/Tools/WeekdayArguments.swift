import Foundation

/// Converts tool weekday names to Calendar's Sunday-first values.
enum WeekdayArguments {
    static let names = [
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
    ]

    static let schema = JSONSchema.Property(
        type: "array",
        description: "Weekly days as full English names, e.g. [\"monday\", \"wednesday\", \"friday\"]. Case-insensitive; numbers are not accepted.",
        items: .init(type: "string", enum: names)
    )

    static func parse(_ value: Any?) throws -> [Int]? {
        guard let value else { return nil }
        guard let days = value as? [String], !days.isEmpty else {
            throw invalidDays
        }
        return try days.map { day in
            guard let index = names.firstIndex(of: day.lowercased()) else {
                throw invalidDays
            }
            return index + 1
        }
    }

    static func render(_ days: [Int]) -> [String] {
        days.compactMap { (1 ... 7).contains($0) ? names[$0 - 1] : nil }
    }

    /// Converts the internal initiative list's comma-separated values for tool output.
    static func initiativeEntry(_ entry: [String: String]) -> [String: Any] {
        var result: [String: Any] = entry
        result["weekdays"] = render((entry["weekdays"] ?? "").split(separator: ",")
            .compactMap { Int($0) })
        return result
    }

    static func scheduleEntry(_ schedule: IntentSchedule) -> [String: Any] {
        var entry: [String: Any] = [
            "id": schedule.id.uuidString,
            "content": schedule.content,
            "frequency": schedule.frequency.rawValue,
        ]
        if let days = schedule.weekdays { entry["weekdays"] = render(days) }
        if let days = schedule.monthDays { entry["month_days"] = days }
        if let hour = schedule.hour { entry["hour"] = hour }
        if let minute = schedule.minute { entry["minute"] = minute }
        return entry
    }

    private static var invalidDays: IntentArgumentError {
        IntentArgumentError(
            "'weekdays' must be a non-empty array of full English weekday names (sunday, monday, tuesday, wednesday, thursday, friday, saturday). Numbers are not accepted."
        )
    }
}
