import EventKit
import Foundation

// MARK: - Protocol

protocol CalendarService: Sendable {
    func authorize(canPromptUser: Bool) async -> EventKitAuthResult
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
