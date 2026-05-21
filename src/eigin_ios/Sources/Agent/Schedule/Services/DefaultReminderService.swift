import EventKit
import Foundation

final class DefaultReminderService: ReminderService, @unchecked Sendable {
    private let store = EKEventStore()

    // MARK: - Authorization

    func authorize(canPromptUser: Bool) async -> EventKitAuthResult {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .fullAccess:
            return .authorized
        case .notDetermined:
            if canPromptUser {
                let granted = await withTimeout {
                    await (try? self.store.requestFullAccessToReminders()) ?? false
                }
                return (granted == true) ? .authorized :
                    .denied("Reminders access was denied by the user.")
            } else {
                return .denied("Reminders access cannot be requested while in the background.")
            }
        case .denied, .restricted, .writeOnly:
            return .denied("Reminders access was denied by the user. Enable it in Settings.")
        @unknown default:
            return .denied("Reminders access is unavailable.")
        }
    }

    // MARK: - Read

    func fetchReminders(
        listID: String?,
        from startDate: Date?,
        to endDate: Date?,
        includeCompleted: Bool
    ) async throws -> [ReminderItem] {
        var calendars: [EKCalendar]?
        if let listID, let calendar = store.calendar(withIdentifier: listID) {
            calendars = [calendar]
        }

        let datesProvided = startDate != nil || endDate != nil
        let defaultWindowDays = 28

        // When dates are provided we fetch all reminders so we can filter by
        // creationDate OR dueDate in memory.
        let predicate: NSPredicate = if datesProvided || includeCompleted {
            store.predicateForReminders(in: calendars)
        } else {
            store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: calendars
            )
        }

        let calendar = Calendar.current
        let now = Date()
        let windowStart: Date? = if !datesProvided {
            calendar.date(byAdding: .day, value: -defaultWindowDays, to: now)
        } else {
            nil
        }
        let windowEnd: Date? = if !datesProvided {
            calendar.date(byAdding: .day, value: defaultWindowDays, to: now)
        } else {
            nil
        }

        nonisolated(unsafe) let unsafeStore = store
        nonisolated(unsafe) let unsafePredicate = predicate

        let result: [ReminderItem]? = await withTimeout {
            let ekReminders = await withCheckedContinuation { (continuation: CheckedContinuation<
                [EKReminder],
                Never
            >) in
                unsafeStore.fetchReminders(matching: unsafePredicate) { reminders in
                    nonisolated(unsafe) let r = reminders ?? []
                    continuation.resume(returning: r)
                }
            }
            return ekReminders
                .filter { includeCompleted || !$0.isCompleted }
                .filter { reminder in
                    if datesProvided {
                        var fits = false
                        if let dueDate = reminder.dueDateComponents?.date {
                            let afterStart = startDate.map { dueDate >= $0 } ?? true
                            let beforeEnd = endDate.map { dueDate <= $0 } ?? true
                            if afterStart, beforeEnd { fits = true }
                        }
                        if !fits {
                            if let creationDate = reminder.creationDate,
                               let startDate, let endDate
                            {
                                if creationDate >= startDate, creationDate <= endDate {
                                    fits = true
                                }
                            }
                        }
                        return fits
                    } else {
                        guard let windowStart, let windowEnd else { return true }
                        let dueFits = reminder.dueDateComponents?.date
                            .map { $0 >= windowStart && $0 <= windowEnd } ?? false
                        let createdFits = reminder.creationDate
                            .map { $0 >= windowStart && $0 <= windowEnd } ?? false
                        return dueFits || createdFits
                    }
                }
                .map { reminder in
                    ReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        isCompleted: reminder.isCompleted,
                        dueDate: reminder.dueDateComponents?.date,
                        creationDate: reminder.creationDate,
                        listName: reminder.calendar.title,
                        listID: reminder.calendar.calendarIdentifier,
                        notes: reminder.notes,
                        priority: reminder.priority
                    )
                }
        }

        guard let reminders = result else {
            throw ReminderServiceError.timeout
        }

        return reminders
    }

    func availableReminderLists() -> [ReminderListInfo] {
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder).map { cal in
            ReminderListInfo(
                id: cal.calendarIdentifier,
                name: cal.title,
                isDefault: cal.calendarIdentifier == defaultID
            )
        }
    }

    // MARK: - Write

    func createReminder(_ reminder: NewReminder) async throws -> String {
        let ekReminder = EKReminder(eventStore: store)
        ekReminder.title = reminder.title

        if let listID = reminder.listID,
           let calendar = store.calendar(withIdentifier: listID)
        {
            ekReminder.calendar = calendar
        } else {
            ekReminder.calendar = store.defaultCalendarForNewReminders()
        }

        if let dueDate = reminder.dueDate {
            ekReminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        ekReminder.notes = reminder.notes
        if let priority = reminder.priority {
            ekReminder.priority = priority
        }

        try store.save(ekReminder, commit: true)
        return ekReminder.calendarItemIdentifier
    }

    func updateReminder(id: String, changes: ReminderChanges) async throws {
        guard let ekReminder = fetchReminderByID(id) else {
            throw ReminderServiceError.reminderNotFound
        }

        if let title = changes.title { ekReminder.title = title }
        if let dueDate = changes.dueDate {
            ekReminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        if let notes = changes.notes { ekReminder.notes = notes }
        if let priority = changes.priority { ekReminder.priority = priority }

        try store.save(ekReminder, commit: true)
    }

    func completeReminder(id: String) async throws {
        guard let ekReminder = fetchReminderByID(id) else {
            throw ReminderServiceError.reminderNotFound
        }
        ekReminder.isCompleted = true
        try store.save(ekReminder, commit: true)
    }

    func deleteReminder(id: String) async throws {
        guard let ekReminder = fetchReminderByID(id) else {
            throw ReminderServiceError.reminderNotFound
        }
        try store.remove(ekReminder, commit: true)
    }

    // MARK: - Private

    private func fetchReminderByID(_ id: String) -> EKReminder? {
        store.calendarItem(withIdentifier: id) as? EKReminder
    }
}

// MARK: - Errors

enum ReminderServiceError: LocalizedError {
    case reminderNotFound
    case timeout

    var errorDescription: String? {
        switch self {
        case .reminderNotFound: "Reminder not found."
        case .timeout: "Reminder operation timed out."
        }
    }
}
