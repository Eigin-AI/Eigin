import Foundation

/// Default local-time delivery slots for non-urgent notifications.
enum NotificationDeliverySchedule {
    /// Returns the first daytime slot strictly after the supplied time.
    static func nextDelivery(after now: Date, calendar: Calendar) -> Date {
        let slots = [7, 9, 11, 13, 15, 17, 19]
        return slots.compactMap { hour in
            calendar.nextDate(
                after: now,
                matching: DateComponents(hour: hour, minute: 0, second: 0),
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first
            )
        }.min()!
    }
}
