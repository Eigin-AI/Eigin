@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Schedule Tools", .serialized)
struct ScheduleToolTests {
    // MARK: - Helpers

    @MainActor
    private func makeAgent() throws -> (Agent, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
            configurations: config
        )
        let agent = Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
        container.mainContext.insert(agent)
        return (agent, container)
    }

    private func makeCall(name: String, arguments: String) -> ToolCall {
        ToolCall(
            id: "call_\(name)",
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    private func sampleEvents() -> [CalendarEvent] {
        [
            CalendarEvent(
                id: "evt-1", title: "Team Standup",
                startDate: Date(), endDate: Date().addingTimeInterval(3600),
                isAllDay: false, calendarName: "Work", calendarID: "cal-work",
                location: "Room 3", notes: nil
            ),
            CalendarEvent(
                id: "evt-2", title: "Lunch",
                startDate: Date(), endDate: Date().addingTimeInterval(3600),
                isAllDay: false, calendarName: "Personal", calendarID: "cal-personal",
                location: nil, notes: "With Bob"
            ),
        ]
    }

    private func sampleCalendars() -> [CalendarInfo] {
        [
            CalendarInfo(id: "cal-work", name: "Work", isDefault: true),
            CalendarInfo(id: "cal-personal", name: "Personal", isDefault: false),
        ]
    }

    private func sampleReminders() -> [ReminderItem] {
        [
            ReminderItem(
                id: "rem-1", title: "Buy milk", isCompleted: false,
                dueDate: Date(), listName: "Groceries", listID: "list-groceries",
                notes: nil, priority: 0
            ),
            ReminderItem(
                id: "rem-2", title: "Call dentist", isCompleted: true,
                dueDate: nil, listName: "Personal", listID: "list-personal",
                notes: "Rescheduled", priority: 1
            ),
        ]
    }

    private func sampleLists() -> [ReminderListInfo] {
        [
            ReminderListInfo(id: "list-groceries", name: "Groceries", isDefault: false),
            ReminderListInfo(id: "list-personal", name: "Personal", isDefault: true),
        ]
    }

    // MARK: - GetCalendarEventsTool

    @Test @MainActor func getCalendarEventsReturnsEvents() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeCalendarService()
        service.events = sampleEvents()
        service.calendars = sampleCalendars()

        let tool = GetCalendarEventsTool(calendarService: service, canPromptUser: true)
        let call = makeCall(name: "get_calendar_events", arguments: """
        {"start_date":"2026-03-22","end_date":"2026-03-23"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Team Standup"))
        #expect(result.content.contains("Lunch"))
        #expect(result.content.contains("Work"))
        #expect(result.content.contains("available_calendars"))
    }

    @Test @MainActor func getCalendarEventsFiltersByCalendarID() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeCalendarService()
        service.events = sampleEvents()
        service.calendars = sampleCalendars()

        let tool = GetCalendarEventsTool(calendarService: service, canPromptUser: true)
        let call = makeCall(name: "get_calendar_events", arguments: """
        {"start_date":"2026-03-22","end_date":"2026-03-23","calendar_ids":["cal-work"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Team Standup"))
        #expect(!result.content.contains("Lunch"))
    }

    @Test @MainActor func getCalendarEventsAuthDenied() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeCalendarService()
        service.authResult = .denied("Calendar access denied.")

        let tool = GetCalendarEventsTool(calendarService: service, canPromptUser: true)
        let call = makeCall(name: "get_calendar_events", arguments: """
        {"start_date":"2026-03-22","end_date":"2026-03-23"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("denied"))
    }

    // MARK: - CreateCalendarEventTool

    @Test @MainActor func createCalendarEventSuccess() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeCalendarService()
        service.nextEventID = "new-evt-123"

        let tool = CreateCalendarEventTool(calendarService: service, canPromptUser: true)
        let call = makeCall(name: "create_calendar_event", arguments: """
        {"title":"Meeting with Bob","start_date":"2026-03-25 14:00","end_date":"2026-03-25 15:00","calendar_id":"cal-work"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("new-evt-123"))
        #expect(service.createdEvents.count == 1)
        #expect(service.createdEvents.first?.title == "Meeting with Bob")
        #expect(service.createdEvents.first?.calendarID == "cal-work")
    }

    @Test @MainActor func createCalendarEventMissingTitle() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeCalendarService()

        let tool = CreateCalendarEventTool(calendarService: service, canPromptUser: true)
        let call = makeCall(name: "create_calendar_event", arguments: """
        {"start_date":"2026-03-25 14:00","end_date":"2026-03-25 15:00"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("title"))
    }

    // MARK: - ManageCalendarEventTool

    @Test @MainActor func manageCalendarEventUpdate() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeCalendarService()
        service.events = sampleEvents()

        let tool = ManageCalendarEventTool(calendarService: service, canPromptUser: true)
        let call = makeCall(name: "manage_calendar_event", arguments: """
        {"action":"update","event_id":"evt-1","title":"Updated Standup"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("updated"))
        #expect(service.updatedEvents.count == 1)
        #expect(service.updatedEvents.first?.changes.title == "Updated Standup")
    }

    @Test @MainActor func manageCalendarEventDelete() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeCalendarService()
        service.events = sampleEvents()

        let tool = ManageCalendarEventTool(calendarService: service, canPromptUser: true)
        let call = makeCall(name: "manage_calendar_event", arguments: """
        {"action":"delete","event_id":"evt-1"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("deleted"))
        #expect(service.deletedEventIDs == ["evt-1"])
    }

    @Test @MainActor func manageCalendarEventNotFound() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeCalendarService()

        let tool = ManageCalendarEventTool(calendarService: service, canPromptUser: true)
        let call = makeCall(name: "manage_calendar_event", arguments: """
        {"action":"delete","event_id":"nonexistent"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("not found"))
    }

    // MARK: - GetRemindersTool

    @Test @MainActor func getRemindersReturnsReminders() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeReminderService()
        service.reminders = sampleReminders()
        service.lists = sampleLists()

        let tool = GetRemindersTool(reminderService: service, canPromptUser: true)
        let call = makeCall(name: "get_reminders", arguments: "{}")
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Buy milk"))
        #expect(!result.content.contains("Call dentist")) // completed, excluded by default
        #expect(result.content.contains("available_lists"))
    }

    @Test @MainActor func getRemindersIncludesCompleted() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeReminderService()
        service.reminders = sampleReminders()
        service.lists = sampleLists()

        let tool = GetRemindersTool(reminderService: service, canPromptUser: true)
        let call = makeCall(name: "get_reminders", arguments: """
        {"include_completed":true}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Buy milk"))
        #expect(result.content.contains("Call dentist"))
    }

    // MARK: - ManageReminderTool

    @Test @MainActor func manageReminderCreate() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeReminderService()
        service.nextReminderID = "new-rem-456"

        let tool = ManageReminderTool(reminderService: service, canPromptUser: true)
        let call = makeCall(name: "manage_reminder", arguments: """
        {"action":"create","title":"Teddy bear day","due_date":"2026-03-27 08:00","list_id":"list-personal"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("new-rem-456"))
        #expect(service.createdReminders.count == 1)
        #expect(service.createdReminders.first?.title == "Teddy bear day")
    }

    @Test @MainActor func manageReminderComplete() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeReminderService()
        service.reminders = sampleReminders()

        let tool = ManageReminderTool(reminderService: service, canPromptUser: true)
        let call = makeCall(name: "manage_reminder", arguments: """
        {"action":"complete","reminder_id":"rem-1"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("completed"))
        #expect(service.completedReminderIDs == ["rem-1"])
    }

    @Test @MainActor func manageReminderDeleteNotFound() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeReminderService()

        let tool = ManageReminderTool(reminderService: service, canPromptUser: true)
        let call = makeCall(name: "manage_reminder", arguments: """
        {"action":"delete","reminder_id":"nonexistent"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("not found"))
    }

    @Test @MainActor func manageReminderCreateMissingTitle() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeReminderService()

        let tool = ManageReminderTool(reminderService: service, canPromptUser: true)
        let call = makeCall(name: "manage_reminder", arguments: """
        {"action":"create","due_date":"2026-03-27 08:00"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("title"))
    }

    // MARK: - Service unavailable

    @Test @MainActor func calendarToolWithNilServiceReturnsError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container

        let tool = GetCalendarEventsTool(calendarService: nil, canPromptUser: true)
        let call = makeCall(name: "get_calendar_events", arguments: """
        {"start_date":"2026-03-22","end_date":"2026-03-23"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("unavailable"))
    }

    @Test @MainActor func reminderToolWithNilServiceReturnsError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container

        let tool = GetRemindersTool(reminderService: nil, canPromptUser: true)
        let call = makeCall(name: "get_reminders", arguments: "{}")
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("unavailable"))
    }
}
