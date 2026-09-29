@testable import Eigin
import Foundation
import SwiftData
import Testing

/// Store-migration regression tests for the Chat/Message schema move (V10).
///
/// Moving `Chat` and `Message` to a new schema version rewires every older
/// schema's compiled relationships to the new classes, so containers built
/// from an outdated model list crash with a `BackingData` cast failure the
/// moment a store actually contains chat rows. These tests pin the current
/// schema as the migration target and prove legacy stores — seeded at several
/// points in the chain — come back through with their rows intact.
@Suite("ChatMessageStoreMigration", .serialized)
struct ChatMessageStoreMigrationTests {
    @MainActor
    private func seedLegacyStore(
        at url: URL,
        models: [any PersistentModel.Type],
        version: Schema.Version
    ) throws {
        let container = try ModelContainer(
            for: Schema(models, version: version),
            configurations: ModelConfiguration(url: url)
        )
        defer { container.mainContext.rollback() }
        let context = container.mainContext

        if version.major <= 3 {
            // V1–V3 Chat has no activeFlow; seeding pre-V4 shape.
            let chat = SchemaV1.Chat(agentID: UUID())
            context.insert(chat)
            let message = SchemaV1.Message(role: "user", content: "hello")
            message.chat = chat
            context.insert(message)
        } else {
            let chat = SchemaV4.Chat(agentID: UUID())
            context.insert(chat)
            let user = SchemaV4.Message(role: "user", content: "hello")
            user.chat = chat
            context.insert(user)
            let summary = SchemaV4.Message(
                role: "system",
                content: "Summary of earlier conversation:\n\nOld stuff"
            )
            summary.isCompactionSummary = true
            summary.chat = chat
            context.insert(summary)
            let reply = SchemaV4.Message(role: "assistant", content: "hi")
            reply.chat = chat
            context.insert(reply)
        }
        try context.save()
    }

    @MainActor
    private func migrate(_ url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            migrationPlan: EiginMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    @Test @MainActor func migratesV9ChatRowsThroughTheFullChain() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-migration-v9-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        try seedLegacyStore(
            at: url, models: SchemaV9.models, version: SchemaV9.versionIdentifier
        )
        let migrated = try migrate(url)

        let chats = try migrated.mainContext.fetch(FetchDescriptor<Chat>())
        let messages = try migrated.mainContext.fetch(FetchDescriptor<Message>())
        #expect(chats.count == 1)
        #expect(messages.count == 3)
        #expect(messages.first?.chat?.id == chats.first?.id)
    }

    @Test @MainActor func migratesV4ChatRowsThroughTheFullChain() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-migration-v4-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        try seedLegacyStore(
            at: url, models: SchemaV4.models, version: SchemaV4.versionIdentifier
        )
        let migrated = try migrate(url)

        let chats = try migrated.mainContext.fetch(FetchDescriptor<Chat>())
        let messages = try migrated.mainContext.fetch(FetchDescriptor<Message>())
        #expect(chats.count == 1)
        #expect(messages.count == 3)

        // The pre-retention compaction summary survives with its flag intact and
        // no retained count, which `prepareTurn` treats as legacy (0 retained).
        let summary = try #require(messages.first { $0.isCompactionSummary })
        #expect(summary.content.hasPrefix("Summary of earlier conversation:"))
        #expect(summary.compactionRetainedMessageCount == nil)
    }

    @Test @MainActor func migratesV1ChatRowsThroughTheFullChain() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-migration-v1-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        try seedLegacyStore(
            at: url, models: SchemaV1.models, version: SchemaV1.versionIdentifier
        )
        let migrated = try migrate(url)

        let chats = try migrated.mainContext.fetch(FetchDescriptor<Chat>())
        #expect(chats.count == 1)
    }
}
