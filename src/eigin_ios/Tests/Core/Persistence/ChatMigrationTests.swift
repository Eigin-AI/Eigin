@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("ChatMigration", .serialized)
struct ChatMigrationTests {
    // MARK: - Helpers

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema(SchemaV3.models, version: SchemaV3.versionIdentifier),
            configurations: config
        )
    }

    @MainActor
    private func makeChat(in container: ModelContainer, spaceID: UUID? = nil) -> Chat {
        let chat = Chat(agentID: UUID())
        chat.spaceID = spaceID
        container.mainContext.insert(chat)
        return chat
    }

    @MainActor
    private func makeKnowledgeSource(
        in container: ModelContainer,
        chatID: UUID,
        spaceID: UUID? = nil
    ) -> FirmSource {
        let source = FirmSource(
            path: "knowledge/note/test.firm",
            content: "note test { content = \"test\" }",
            spaceID: spaceID,
            chatID: chatID
        )
        container.mainContext.insert(source)
        return source
    }

    // MARK: - Tests

    @Test @MainActor func moveChatUpdatesSpaceID() throws {
        let container = try makeContainer()
        let spaceA = UUID()
        let spaceB = UUID()
        let chat = makeChat(in: container, spaceID: spaceA)

        ChatMigration.moveChat(chat, toSpaceID: spaceB, context: container.mainContext)

        #expect(chat.spaceID == spaceB)
    }

    @Test @MainActor func moveChatMigratesKnowledgeSources() throws {
        let container = try makeContainer()
        let spaceA = UUID()
        let spaceB = UUID()
        let chat = makeChat(in: container, spaceID: spaceA)
        let source = makeKnowledgeSource(in: container, chatID: chat.id, spaceID: spaceA)

        ChatMigration.moveChat(chat, toSpaceID: spaceB, context: container.mainContext)

        #expect(source.spaceID == spaceB)
    }

    @Test @MainActor func unrelatedDataUnaffected() throws {
        let container = try makeContainer()
        let spaceA = UUID()
        let spaceB = UUID()
        let chat = makeChat(in: container, spaceID: spaceA)
        let otherChatID = UUID()

        // Knowledge source from a different chat
        let otherSource = makeKnowledgeSource(in: container, chatID: otherChatID, spaceID: spaceA)

        ChatMigration.moveChat(chat, toSpaceID: spaceB, context: container.mainContext)

        #expect(otherSource.spaceID == spaceA)
    }

    @Test @MainActor func removeFromSpaceSetsNil() throws {
        let container = try makeContainer()
        let spaceA = UUID()
        let chat = makeChat(in: container, spaceID: spaceA)
        let source = makeKnowledgeSource(in: container, chatID: chat.id, spaceID: spaceA)

        ChatMigration.moveChat(chat, toSpaceID: nil, context: container.mainContext)

        #expect(chat.spaceID == nil)
        #expect(source.spaceID == nil)
    }
}
