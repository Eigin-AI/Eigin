import EventKit
import Foundation

// MARK: - Protocol

protocol CalendarService: Sendable {
    func authorize(canPromptUser: Bool) async -> EventKitAuthResult
    /// What iOS lets Eigin do with calendars, without asking.
    func access() -> EventKitAccess
    func fetchEvents(from startDate: Date, to endDate: Date, calendarIDs: [String]?) async throws
        -> [CalendarEvent]
    func availableCalendars() -> [CalendarInfo]
    func createEvent(_ event: NewCalendarEvent) async throws -> String
    func updateEvent(id: String, changes: CalendarEventChanges) async throws
    func deleteEvent(id: String) async throws
}

// MARK: - Value Types

enum EventKitAuthResult {
    case authorized
    case denied(String)
}

/// How much of a calendar or reminders store iOS lets Eigin use.
enum EventKitAccess: Equatable {
    case notAsked
    case full
    /// Calendars only: Eigin can add events but not see them.
    case addOnly
    case none

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notAsked
        case .fullAccess: self = .full
        case .writeOnly: self = .addOnly
        default: self = .none
        }
    }
}

struct CalendarEvent {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String
    let calendarID: String
    let location: String?
    let notes: String?
}

struct CalendarInfo {
    let id: String
    let name: String
    let isDefault: Bool
}

struct NewCalendarEvent {
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarID: String?
    let location: String?
    let notes: String?
    let isAllDay: Bool
}

struct CalendarEventChanges {
    let title: String?
    let startDate: Date?
    let endDate: Date?
    let location: String?
    let notes: String?
}
