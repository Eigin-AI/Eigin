@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Skill Lifetime", .serialized)
struct SkillLifetimeTests {
    // MARK: - Helpers

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            configurations: config
        )
    }

    @MainActor
    private func makeChat(in container: ModelContainer) -> Chat {
        let chat = Chat(agentID: UUID())
        container.mainContext.insert(chat)
        return chat
    }

    /// Activates a skill at a given base date.
    private func activate(_ skillID: String, at date: Date, on chat: Chat) {
        chat.activeSkillEntries.append(
            ActiveSkillEntry(
                skillID: skillID,
                activatedAt: date,
                activatingToolCallID: "test-\(skillID)"
            )
        )
    }

    // MARK: - Tests

    @Test @MainActor func skillSurvivesManyMessages() throws {
        let container = try makeContainer()
        let chat = makeChat(in: container)

        activate("web", at: .now, on: chat)

        // Skills stay active for the life of the chat, including across compaction.
        #expect(chat.activeSkillEntries.count == 1)
        #expect(chat.activeSkillEntries.first?.skillID == "web")
    }

    @Test @MainActor func isSkillActiveReflectsEntries() throws {
        let container = try makeContainer()
        let chat = makeChat(in: container)

        #expect(!chat.isSkillActive("web"))

        activate("web", at: .now, on: chat)
        #expect(chat.isSkillActive("web"))
        #expect(!chat.isSkillActive("email"))
    }
}
