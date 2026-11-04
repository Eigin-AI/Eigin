import Foundation

/// Daily choices exposed by initiative tools, independent of calendar trigger storage.
enum InitiativeDailyPattern: String, Codable, CaseIterable, Sendable {
    case everyDay = "every_day"
    case weekdays
    case weekends

    /// Calendar weekday numbers, where Sunday is 1.
    var weekdays: [Int] {
        switch self {
        case .everyDay: Array(1 ... 7)
        case .weekdays: Array(2 ... 6)
        case .weekends: [1, 7]
        }
    }
}

/// An enabled initiative and its owning intent's current schedule.
struct InitiativeSchedule: Sendable {
    let initiativeID: UUID
    let intentID: UUID
    let agentID: UUID
    let spaceID: UUID?
    let schedule: IntentSchedule
}

/// One repeating notification pattern with the exact initiatives due together.
struct InitiativeNotificationPattern: Equatable, Sendable {
    let agentID: UUID
    let spaceID: UUID?
    let hour: Int
    let minute: Int
    /// Nil means every day; otherwise Calendar's weekday number (Sunday is 1).
    let weekday: Int?
    let initiativeIDs: [UUID]

    /// Uses the device's time zone; explicit seconds avoid inheriting registration seconds.
    var dateComponents: DateComponents {
        DateComponents(
            hour: hour,
            minute: minute,
            second: 0,
            weekday: weekday
        )
    }
}

/// A scheduling rejection that can be reported without exposing trigger internals.
enum InitiativeScheduleError: Error, Equatable {
    case unsupportedMonthlySchedule
    case explicitTimeRequired
    case invalidTime
    case invalidWeekdays
    case duplicateInitiative
    case invalidRequestBudget
    /// Compiled notification requests needed versus remaining request slots.
    case capacityExceeded(required: Int, available: Int)
}
