@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("WatchChat", .serialized)
struct WatchChatTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: config
        )
    }

    @MainActor
    private func clearStoredID() {
        UserDefaults.standard.removeObject(forKey: StorageKey.watchChat)
    }

    @Test("resolve creates and stores the chat")
    @MainActor func resolveCreates() throws {
        let container = try makeContainer()
        clearStoredID()
        defer { clearStoredID() }

        let agentID = UUID()
        let chat = WatchChat.resolve(in: container.mainContext, agentID: agentID)

        #expect(chat.agentID == agentID)
        #expect(WatchChat.storedID() == chat.id)
    }

    @Test("resolve reuses the stored chat")
    @MainActor func resolveReuses() throws {
        let container = try makeContainer()
        clearStoredID()
        defer { clearStoredID() }

        let first = WatchChat.resolve(in: container.mainContext, agentID: UUID())
        let second = WatchChat.resolve(in: container.mainContext, agentID: UUID())

        #expect(first.id == second.id)
    }

    @Test("same local day reuses the chat across UTC midnight")
    @MainActor func sameLocalDayReuses() throws {
        let container = try makeContainer()
        clearStoredID()
        defer { clearStoredID() }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(ISO8601DateFormatter().date(from: "2026-03-07T23:00:00Z"))
        let first = WatchChat.resolve(
            in: container.mainContext, agentID: UUID(), now: start, calendar: calendar
        )
        let second = WatchChat.resolve(
            in: container.mainContext, agentID: UUID(),
            now: start.addingTimeInterval(2 * 3600), calendar: calendar
        )

        #expect(second.id == first.id)
    }

    @Test("local midnight rotates the chat and retains history on a short DST day")
    @MainActor func nextLocalDayRotates() throws {
        let container = try makeContainer()
        clearStoredID()
        defer { clearStoredID() }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(ISO8601DateFormatter().date(from: "2026-03-08T08:00:00Z"))
        let nextDay = try #require(ISO8601DateFormatter().date(from: "2026-03-09T07:00:00Z"))
        let agentID = UUID()
        let first = WatchChat.resolve(
            in: container.mainContext, agentID: agentID, now: start, calendar: calendar
        )
        first.updatedAt = nextDay
        try container.mainContext.save()

        let second = WatchChat.resolve(
            in: container.mainContext, agentID: agentID, now: nextDay, calendar: calendar
        )
        try container.mainContext.save()
        let chats = try container.mainContext.fetch(FetchDescriptor<Chat>())

        #expect(second.id != first.id)
        #expect(second.agentID == agentID)
        #expect(second.createdAt == nextDay)
        #expect(WatchChat.storedID() == second.id)
        #expect(chats.count == 2)
        #expect(chats.contains { $0.id == first.id })
        let followUp = WatchChat.resolve(
            in: container.mainContext, agentID: agentID,
            now: nextDay.addingTimeInterval(60), calendar: calendar
        )
        #expect(followUp.id == second.id)
    }

    @Test("deleting the chat resets it")
    @MainActor func deletedChatResets() throws {
        let container = try makeContainer()
        clearStoredID()
        defer { clearStoredID() }

        let first = WatchChat.resolve(in: container.mainContext, agentID: UUID())
        container.mainContext.delete(first)
        try container.mainContext.save()

        let second = WatchChat.resolve(in: container.mainContext, agentID: UUID())

        #expect(second.id != first.id)
    }

    @Test("storedID is nil before first use")
    @MainActor func storedIDNilBeforeUse() {
        clearStoredID()
        defer { clearStoredID() }

        #expect(WatchChat.storedID() == nil)
    }
}
