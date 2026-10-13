import EventKit
import Foundation

final class DefaultCalendarService: CalendarService, @unchecked Sendable {
    private let store = EKEventStore()
    private static let timeout: Duration = .seconds(5)

    // MARK: - Authorization

    func authorize(canPromptUser: Bool) async -> EventKitAuthResult {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess:
            return .authorized
        case .notDetermined:
            if canPromptUser {
                let granted = await withTimeout {
                    await (try? self.store.requestFullAccessToEvents()) ?? false
                }
                return (granted == true) ? .authorized :
                    .denied("Calendar access was denied by the user.")
            } else {
                return .denied("Calendar access cannot be requested while in the background.")
            }
        case .denied, .restricted, .writeOnly:
            return .denied("Calendar access was denied by the user. Enable it in Settings.")
        @unknown default:
            return .denied("Calendar access is unavailable.")
        }
    }

    func access() -> EventKitAccess {
        EventKitAccess(EKEventStore.authorizationStatus(for: .event))
    }

    // MARK: - Read

    func fetchEvents(
        from startDate: Date,
        to endDate: Date,
        calendarIDs: [String]?
    ) async throws -> [CalendarEvent] {
        var calendars: [EKCalendar]?
        if let calendarIDs {
            calendars = calendarIDs.compactMap { store.calendar(withIdentifier: $0) }
        }

        let predicate = store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )
        let ekEvents = store.events(matching: predicate)

        return ekEvents.map { event in
            CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                calendarID: event.calendar.calendarIdentifier,
                location: event.location,
                notes: event.notes
            )
        }
    }

    func availableCalendars() -> [CalendarInfo] {
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event).map { cal in
            CalendarInfo(
                id: cal.calendarIdentifier,
                name: cal.title,
                isDefault: cal.calendarIdentifier == defaultID
            )
        }
    }

    // MARK: - Write

    func createEvent(_ event: NewCalendarEvent) async throws -> String {
        let ekEvent = EKEvent(eventStore: store)
        ekEvent.title = event.title
        ekEvent.startDate = event.startDate
        ekEvent.endDate = event.endDate
        ekEvent.isAllDay = event.isAllDay
        ekEvent.location = event.location
        ekEvent.notes = event.notes

        if let calendarID = event.calendarID,
           let calendar = store.calendar(withIdentifier: calendarID)
        {
            ekEvent.calendar = calendar
        } else {
            ekEvent.calendar = store.defaultCalendarForNewEvents
        }

        try store.save(ekEvent, span: .thisEvent)
        return ekEvent.eventIdentifier
    }

    func updateEvent(id: String, changes: CalendarEventChanges) async throws {
        guard let ekEvent = store.event(withIdentifier: id) else {
            throw CalendarServiceError.eventNotFound
        }

        if let title = changes.title { ekEvent.title = title }
        if let startDate = changes.startDate { ekEvent.startDate = startDate }
        if let endDate = changes.endDate { ekEvent.endDate = endDate }
        if let location = changes.location { ekEvent.location = location }
        if let notes = changes.notes { ekEvent.notes = notes }

        try store.save(ekEvent, span: .thisEvent)
    }

    func deleteEvent(id: String) async throws {
        guard let ekEvent = store.event(withIdentifier: id) else {
            throw CalendarServiceError.eventNotFound
        }
        try store.remove(ekEvent, span: .thisEvent)
    }
}

// MARK: - Errors

enum CalendarServiceError: LocalizedError {
    case eventNotFound
    case timeout

    var errorDescription: String? {
        switch self {
        case .eventNotFound: "Calendar event not found."
        case .timeout: "Calendar operation timed out."
        }
    }
}

// MARK: - Timeout Helper

func withTimeout<T: Sendable>(
    duration: Duration = .seconds(5),
    _ operation: @escaping @Sendable () async throws -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { try? await operation() }
        group.addTask { try? await Task.sleep(for: duration); return nil }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
