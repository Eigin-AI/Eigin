#if DEBUG || EIGIN_DEV
import Foundation

final class FakeReminderService: ReminderService, @unchecked Sendable {
    var authResult: EventKitAuthResult = .authorized
    var accessLevel: EventKitAccess = .full
    var reminders: [ReminderItem] = []
    var lists: [ReminderListInfo] = []
    var createdReminders: [NewReminder] = []
    var updatedReminders: [(id: String, changes: ReminderChanges)] = []
    var completedReminderIDs: [String] = []
    var deletedReminderIDs: [String] = []
    var nextReminderID = "fake-reminder-1"

    func authorize(canPromptUser: Bool) async -> EventKitAuthResult {
        authResult
    }

    func access() -> EventKitAccess {
        accessLevel
    }

    func fetchReminders(
        listID: String?,
        from startDate: Date?,
        to endDate: Date?,
        includeCompleted: Bool
    ) async throws -> [ReminderItem] {
        var result = reminders
        if let listID { result = result.filter { $0.listID == listID } }
        if !includeCompleted { result = result.filter { !$0.isCompleted } }

        if startDate != nil || endDate != nil {
            result = result.filter { reminder in
                var fits = false
                if let dueDate = reminder.dueDate {
                    let afterStart = startDate.map { dueDate >= $0 } ?? true
                    let beforeEnd = endDate.map { dueDate <= $0 } ?? true
                    if afterStart, beforeEnd { fits = true }
                }
                if !fits, let creationDate = reminder.creationDate, let startDate, let endDate {
                    if creationDate >= startDate, creationDate <= endDate { fits = true }
                }
                return fits
            }
        } else {
            // Default window: created or due within ±28 days of now.
            let calendar = Calendar.current
            let now = Date()
            let windowStart = calendar.date(byAdding: .day, value: -28, to: now)!
            let windowEnd = calendar.date(byAdding: .day, value: 28, to: now)!
            result = result.filter { reminder in
                let dueFits = reminder.dueDate.map { $0 >= windowStart && $0 <= windowEnd } ?? false
                let createdFits = reminder.creationDate
                    .map { $0 >= windowStart && $0 <= windowEnd } ?? false
                return dueFits || createdFits
            }
        }

        return result
    }

    func availableReminderLists() -> [ReminderListInfo] {
        lists
    }

    func createReminder(_ reminder: NewReminder) async throws -> String {
        createdReminders.append(reminder)
        return nextReminderID
    }

    func updateReminder(id: String, changes: ReminderChanges) async throws {
        guard reminders.contains(where: { $0.id == id }) else {
            throw ReminderServiceError.reminderNotFound
        }
        updatedReminders.append((id: id, changes: changes))
    }

    func completeReminder(id: String) async throws {
        guard reminders.contains(where: { $0.id == id }) else {
            throw ReminderServiceError.reminderNotFound
        }
        completedReminderIDs.append(id)
    }

    func deleteReminder(id: String) async throws {
        guard reminders.contains(where: { $0.id == id }) else {
            throw ReminderServiceError.reminderNotFound
        }
        deletedReminderIDs.append(id)
    }
}
#endif
