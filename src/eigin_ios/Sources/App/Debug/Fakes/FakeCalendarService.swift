#if DEBUG || EIGIN_DEV
import Foundation

final class FakeCalendarService: CalendarService, @unchecked Sendable {
    var authResult: EventKitAuthResult = .authorized
    var accessLevel: EventKitAccess = .full
    var events: [CalendarEvent] = []
    var calendars: [CalendarInfo] = []
    var createdEvents: [NewCalendarEvent] = []
    var updatedEvents: [(id: String, changes: CalendarEventChanges)] = []
    var deletedEventIDs: [String] = []
    var nextEventID = "fake-event-1"

    func authorize(canPromptUser: Bool) async -> EventKitAuthResult {
        authResult
    }

    func access() -> EventKitAccess {
        accessLevel
    }

    func fetchEvents(
        from startDate: Date,
        to endDate: Date,
        calendarIDs: [String]?
    ) async throws -> [CalendarEvent] {
        if let calendarIDs {
            return events.filter { calendarIDs.contains($0.calendarID) }
        }
        return events
    }

    func availableCalendars() -> [CalendarInfo] {
        calendars
    }

    func createEvent(_ event: NewCalendarEvent) async throws -> String {
        createdEvents.append(event)
        return nextEventID
    }

    func updateEvent(id: String, changes: CalendarEventChanges) async throws {
        guard events.contains(where: { $0.id == id }) else {
            throw CalendarServiceError.eventNotFound
        }
        updatedEvents.append((id: id, changes: changes))
    }

    func deleteEvent(id: String) async throws {
        guard events.contains(where: { $0.id == id }) else {
            throw CalendarServiceError.eventNotFound
        }
        deletedEventIDs.append(id)
    }
}
#endif
