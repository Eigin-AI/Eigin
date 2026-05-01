import EventKit
import Foundation

// MARK: - Protocol

protocol ReminderService: Sendable {
    func authorize(canPromptUser: Bool) async -> EventKitAuthResult
    func fetchReminders(
        listID: String?,
        from startDate: Date?,
        to endDate: Date?,
        includeCompleted: Bool
    ) async throws
        -> [ReminderItem]
    func availableReminderLists() -> [ReminderListInfo]
    func createReminder(_ reminder: NewReminder) async throws -> String
    func updateReminder(id: String, changes: ReminderChanges) async throws
    func completeReminder(id: String) async throws
    func deleteReminder(id: String) async throws
}

// MARK: - Value Types

struct ReminderItem {
    let id: String
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
    let listName: String
    let listID: String
    let notes: String?
    let priority: Int
}

struct ReminderListInfo {
    let id: String
    let name: String
    let isDefault: Bool
}

struct NewReminder {
    let title: String
    let listID: String?
    let dueDate: Date?
    let notes: String?
    let priority: Int?
}

struct ReminderChanges {
    let title: String?
    let dueDate: Date?
    let notes: String?
    let priority: Int?
}
