import Foundation

/// Parses future notification dates, using the local timezone when omitted.
enum NotificationDeliveryTime {
    static func parse(_ value: Any?, now: Date, calendar: Calendar, required: Bool) throws -> Date {
        guard let value else {
            if required {
                throw ValidationError(
                    message: "Missing 'deliver_at': provide a future ISO 8601 datetime."
                )
            }
            return NotificationDeliverySchedule.nextDelivery(after: now, calendar: calendar)
        }
        guard let text = value as? String, !text.isEmpty else {
            throw ValidationError(message: "Use a future ISO 8601 datetime for 'deliver_at'.")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: text)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: text)
        }
        if date == nil {
            let local = DateFormatter()
            local.locale = Locale(identifier: "en_US_POSIX")
            local.calendar = Calendar(identifier: .gregorian)
            local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            local.timeZone = calendar.timeZone
            local.isLenient = false
            date = local.date(from: text)
        }
        guard let date else {
            throw ValidationError(message: "Could not parse 'deliver_at'. Use ISO 8601 format.")
        }
        guard date > now else {
            throw ValidationError(message: "'deliver_at' must be in the future.")
        }
        return date
    }

    struct ValidationError: LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }
}
