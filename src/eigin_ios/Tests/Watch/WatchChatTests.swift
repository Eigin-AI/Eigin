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
            for: Schema(SchemaV4.models, version: SchemaV4.versionIdentifier),
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
