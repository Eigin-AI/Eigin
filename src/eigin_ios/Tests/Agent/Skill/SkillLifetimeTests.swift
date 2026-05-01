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
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
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

        // Skills no longer expire by message count — they survive until compaction.
        #expect(chat.activeSkillEntries.count == 1)
        #expect(chat.activeSkillEntries.first?.skillID == "web")
    }

    @Test @MainActor func clearActiveSkillsRemovesAll() throws {
        let container = try makeContainer()
        let chat = makeChat(in: container)

        activate("web", at: .now, on: chat)
        activate("email", at: .now, on: chat)
        #expect(chat.activeSkillEntries.count == 2)

        chat.clearActiveSkills()
        #expect(chat.activeSkillEntries.isEmpty)
    }

    @Test @MainActor func isSkillActiveReflectsEntries() throws {
        let container = try makeContainer()
        let chat = makeChat(in: container)

        #expect(!chat.isSkillActive("web"))

        activate("web", at: .now, on: chat)
        #expect(chat.isSkillActive("web"))
        #expect(!chat.isSkillActive("email"))

        chat.clearActiveSkills()
        #expect(!chat.isSkillActive("web"))
    }
}
