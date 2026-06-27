import Foundation

/// Parses and formats dates for agent-facing tools.
///
/// All times are local — the agent never reasons about UTC or timezone offsets.
///
/// **Primary format** (preferred for both input and output):
/// - Date + time: `"2026-03-23 09:00"`
/// - Date only: `"2026-03-23"` (midnight local)
///
/// **Fallback formats** (accepted on input for robustness):
/// - ISO 8601 datetime: `"2026-03-23T09:00:00"`, `"2026-03-23T09:00:00Z"`,
/// `"2026-03-23T09:00:00+01:00"`
/// - Timezone offsets are stripped — `14:00+02:00` is interpreted as 14:00 local.
enum LocalDateFormatter {
    // MARK: - Formatting (tool → agent)

    /// Format a date as `"2026-03-23 09:00"` in the device's local timezone.
    static func string(from date: Date) -> String {
        dateTimeOutput.string(from: date)
    }

    /// Format a date as `"Monday, 2026-03-23 09:00"` in the device's local
    /// timezone, naming the weekday in English.
    static func stringWithWeekday(from date: Date) -> String {
        "\(weekdayOutput.string(from: date)), \(dateTimeOutput.string(from: date))"
    }

    /// Format a date as `"2026-03-23"` in the device's local timezone.
    static func dateOnlyString(from date: Date) -> String {
        dateOnlyOutput.string(from: date)
    }

    /// Format a date as ISO 8601 `"2026-03-23T09:00:00Z"` (UTC) for Firm storage.
    static func iso8601String(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    // MARK: - Parsing (agent → tool)

    /// Parse a date string from the agent. Tries the simple format first,
    /// then falls back to ISO 8601 variants. All times interpreted as local.
    ///
    /// - Parameter endOfDayIfDateOnly: When `true` and the input is date-only
    ///   (e.g. `"2026-03-23"`), returns 23:59:59 on that day instead of midnight.
    ///   Use this for end-of-range parameters so "today to today" captures the full day.
    static func parse(_ string: String, endOfDayIfDateOnly: Bool = false) -> Date? {
        let cleaned = stripTimezoneOffset(string)

        // Primary: "2026-03-23 09:00"
        if let date = dateTimeInput.date(from: cleaned) { return date }

        // Fallback: ISO 8601 "2026-03-23T09:00:00"
        if let date = isoFallback.date(from: cleaned) { return date }

        // Date only: "2026-03-23"
        if let date = dateOnlyInput.date(from: cleaned) {
            if endOfDayIfDateOnly {
                return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date)
            }
            return date
        }

        return nil
    }

    // MARK: - Private

    private static let dateTimeOutput: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f
    }()

    private static let weekdayOutput: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static let dateOnlyOutput: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private static let dateTimeInput: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f
    }()

    private static let dateOnlyInput: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFallback: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    /// Strips trailing `Z`, `+HH:MM`, or `-HH:MM` so the datetime
    /// is interpreted as local time.
    private static func stripTimezoneOffset(_ string: String) -> String {
        var s = string
        if s.hasSuffix("Z") { s = String(s.dropLast()) }
        if s.count > 6 {
            let suffix = s.suffix(6)
            if let first = suffix.first, first == "+" || first == "-",
               suffix.dropFirst().contains(":")
            {
                s = String(s.dropLast(6))
            }
        }
        return s
    }
}
