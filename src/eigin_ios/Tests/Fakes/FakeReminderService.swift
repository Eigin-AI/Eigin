@testable import Eigin
import Foundation

final class FakeReminderService: ReminderService, @unchecked Sendable {
    var authResult: EventKitAuthResult = .authorized
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

    func fetchReminders(
        listID: String?,
        from startDate: Date?,
        to endDate: Date?,
        includeCompleted: Bool
    ) async throws -> [ReminderItem] {
        var result = reminders
        if let listID { result = result.filter { $0.listID == listID } }
        if !includeCompleted { result = result.filter { !$0.isCompleted } }
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
