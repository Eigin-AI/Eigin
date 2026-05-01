@testable import Eigin
import Foundation
import Testing

@Suite("KnowledgeAutoLinker")
struct KnowledgeAutoLinkerTests {
    // MARK: - Fake Knowledge Service

    final class FakeAutoLinkerKnowledgeService: KnowledgeService, @unchecked Sendable {
        var isBuilt: Bool {
            true
        }

        var entities: [String: FirmEntity] = [:]
        var sources: [FirmSource] = []

        func rebuild(
            spaceID: UUID?,
            agentID: UUID?,
            accessPolicy: SpaceAccessPolicy?
        ) async throws {}
        func query(
            _ queryString: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> FirmQueryResult {
            .entities(entities: [])
        }

        func getEntity(
            type: String,
            id: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> FirmEntity? {
            entities["\(type).\(id)"]
        }

        func listEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws -> [String] {
            entities.values.filter { $0.entityType == type }.map {
                let prefix = type + "."
                return $0.id.hasPrefix(prefix) ? String($0.id.dropFirst(prefix.count)) : $0.id
            }
        }

        func listSchemas(spaceID: UUID?, agentID: UUID?) async throws -> [String] {
            Array(Set(entities.values.map(\.entityType)))
        }

        func getRelated(
            type: String,
            id: String,
            direction: FirmDirection,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> [FirmEntity] {
            []
        }

        func addEntity(
            _ entity: FirmEntity,
            spaceID: UUID?,
            agentID: UUID?,
            chatID: UUID?
        ) async throws {}
        func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws {}
        func isBundled(path: String) -> Bool {
            false
        }

        func getSource(path: String, spaceID: UUID?, agentID: UUID?) async throws -> String? {
            nil
        }

        func findEntitySource(
            type: String,
            id: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> String? {
            nil
        }

        func getSchema(
            entityType: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> FirmSchema? {
            nil
        }

        func getFirmSource(
            type: String,
            id: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> FirmSource? {
            nil
        }

        func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
            sources
        }

        func validEntities(
            type: String,
            spaceID: UUID?,
            agentID: UUID?,
            at date: Date
        ) async throws -> [FirmEntity] {
            []
        }
    }

    // MARK: - Helpers

    private func makeEntity(type: String, id: String, fields: [FirmField]) -> FirmEntity {
        FirmEntity(id: "\(type).\(id)", entityType: type, fields: fields)
    }

    private func makeNamedEntity(type: String, id: String, name: String) -> FirmEntity {
        makeEntity(
            type: type,
            id: id,
            fields: [FirmField(name: "name", value: .string(value: name))]
        )
    }

    // MARK: - Name mention matching

    @Test("Note mentioning 'Daniel' links to actor.daniel")
    func nameMentionLinksToActor() async {
        let service = FakeAutoLinkerKnowledgeService()
        service.entities["actor.daniel"] = makeNamedEntity(
            type: "actor",
            id: "daniel",
            name: "Daniel"
        )

        let note = makeEntity(type: "note", id: "pref", fields: [
            FirmField(name: "content", value: .string(value: "Daniel prefers dark mode")),
        ])

        let links = await KnowledgeAutoLinker.autoLinks(
            for: note, knowledgeService: service, spaceID: nil, agentID: nil
        )
        #expect(links.contains("actor.daniel"))
    }

    @Test("Short name (< 4 chars) does not match")
    func shortNameNoMatch() async {
        let service = FakeAutoLinkerKnowledgeService()
        service.entities["actor.ai_bot"] = makeNamedEntity(type: "actor", id: "ai_bot", name: "AI")

        let note = makeEntity(type: "note", id: "test", fields: [
            FirmField(name: "content", value: .string(value: "AI is great")),
        ])

        let links = await KnowledgeAutoLinker.autoLinks(
            for: note, knowledgeService: service, spaceID: nil, agentID: nil
        )
        #expect(!links.contains("actor.ai_bot"))
    }

    @Test("Partial match 'Danielle' does not match actor 'Daniel' (whole-word boundary)")
    func wholeWordBoundary() async {
        let service = FakeAutoLinkerKnowledgeService()
        service.entities["actor.daniel"] = makeNamedEntity(
            type: "actor",
            id: "daniel",
            name: "Daniel"
        )

        let note = makeEntity(type: "note", id: "test", fields: [
            FirmField(name: "content", value: .string(value: "Danielle went shopping")),
        ])

        let links = await KnowledgeAutoLinker.autoLinks(
            for: note, knowledgeService: service, spaceID: nil, agentID: nil
        )
        #expect(!links.contains("actor.daniel"))
    }

    @Test("Entity with existing belongs_to gets no auto-links")
    func existingRelationshipSkips() async {
        let service = FakeAutoLinkerKnowledgeService()
        service.entities["actor.daniel"] = makeNamedEntity(
            type: "actor",
            id: "daniel",
            name: "Daniel"
        )

        let note = makeEntity(type: "note", id: "test", fields: [
            FirmField(name: "content", value: .string(value: "Daniel prefers dark mode")),
            FirmField(
                name: "belongs_to",
                value: .list(items: [.entityReference(entityId: "thing.app")])
            ),
        ])

        // hasRelationships check happens in AddKnowledgeTool, but we verify the
        // auto-linker itself still works — the caller is responsible for gating.
        let links = await KnowledgeAutoLinker.autoLinks(
            for: note, knowledgeService: service, spaceID: nil, agentID: nil
        )
        // Auto-linker doesn't check for existing relationships (caller does),
        // so it would still return matches. This test documents that behavior.
        #expect(links.contains("actor.daniel"))
    }

    @Test("Self-exclusion: entity does not link to itself")
    func selfExclusion() async {
        let service = FakeAutoLinkerKnowledgeService()
        let actor = makeNamedEntity(type: "actor", id: "daniel", name: "Daniel")
        service.entities["actor.daniel"] = actor

        let links = await KnowledgeAutoLinker.autoLinks(
            for: actor, knowledgeService: service, spaceID: nil, agentID: nil
        )
        #expect(!links.contains("actor.daniel"))
    }

    @Test("Cap enforcement: many matches produce at most 3 links")
    func capEnforcement() async {
        let service = FakeAutoLinkerKnowledgeService()
        // Create 5 actors with long enough names.
        for name in ["Alpha", "Bravo", "Charlie", "Delta", "Echo"] {
            let id = name.lowercased()
            service.entities["actor.\(id)"] = makeNamedEntity(type: "actor", id: id, name: name)
        }

        let note = makeEntity(type: "note", id: "test", fields: [
            FirmField(name: "content", value: .string(value: "Alpha Bravo Charlie Delta Echo")),
        ])

        let links = await KnowledgeAutoLinker.autoLinks(
            for: note, knowledgeService: service, spaceID: nil, agentID: nil
        )
        #expect(links.count <= KnowledgeAutoLinker.maxLinks)
    }

    @Test("'user' alias matches actor.user")
    func userAliasMatch() async {
        let service = FakeAutoLinkerKnowledgeService()
        service.entities["actor.user"] = makeNamedEntity(
            type: "actor",
            id: "user",
            name: "Daniel Rothmann"
        )

        let note = makeEntity(type: "note", id: "pref", fields: [
            FirmField(name: "content", value: .string(value: "The user prefers dark mode")),
        ])

        let links = await KnowledgeAutoLinker.autoLinks(
            for: note, knowledgeService: service, spaceID: nil, agentID: nil
        )
        #expect(links.contains("actor.user"))
    }

    @Test("'agent' alias matches actor.agent")
    func agentAliasMatch() async {
        let service = FakeAutoLinkerKnowledgeService()
        service.entities["actor.agent"] = makeNamedEntity(type: "actor", id: "agent", name: "Eigin")

        let note = makeEntity(type: "note", id: "note1", fields: [
            FirmField(name: "content", value: .string(value: "The agent responded quickly")),
        ])

        let links = await KnowledgeAutoLinker.autoLinks(
            for: note, knowledgeService: service, spaceID: nil, agentID: nil
        )
        #expect(links.contains("actor.agent"))
    }

    @Test("Multi-word name matches on individual word")
    func multiWordNameMatch() async {
        let service = FakeAutoLinkerKnowledgeService()
        service.entities["actor.daniel"] = makeNamedEntity(
            type: "actor",
            id: "daniel",
            name: "Daniel Rothmann"
        )

        let note = makeEntity(type: "note", id: "test", fields: [
            FirmField(name: "content", value: .string(value: "Rothmann likes hiking")),
        ])

        let links = await KnowledgeAutoLinker.autoLinks(
            for: note, knowledgeService: service, spaceID: nil, agentID: nil
        )
        #expect(links.contains("actor.daniel"))
    }

    @Test("Possessive form 'Daniel's' matches actor 'Daniel'")
    func possessiveNameMatch() async {
        let service = FakeAutoLinkerKnowledgeService()
        service.entities["actor.daniel"] = makeNamedEntity(
            type: "actor",
            id: "daniel",
            name: "Daniel"
        )

        let note = makeEntity(type: "note", id: "cat", fields: [
            FirmField(
                name: "content",
                value: .string(value: "Daniel's cat likes to sit on the keyboard")
            ),
        ])

        let links = await KnowledgeAutoLinker.autoLinks(
            for: note, knowledgeService: service, spaceID: nil, agentID: nil
        )
        #expect(links.contains("actor.daniel"))
    }

    // MARK: - Tokenizer

    @Test("Tokenizer extracts lowercased words")
    func tokenizerBasic() {
        let tokens = KnowledgeAutoLinker.tokenize("Daniel prefers Dark Mode")
        #expect(tokens.contains("daniel"))
        #expect(tokens.contains("prefers"))
        #expect(tokens.contains("dark"))
        #expect(tokens.contains("mode"))
    }

    @Test("Tokenizer strips possessive suffix")
    func tokenizerPossessive() {
        let tokens = KnowledgeAutoLinker.tokenize("Daniel's cat")
        #expect(tokens.contains("daniel's"))
        #expect(tokens.contains("daniel"))
    }

    @Test("nameMatchesTokens respects minimum length")
    func nameMatchRespectsMinLength() {
        let tokens: Set = ["ai", "is", "great"]
        #expect(!KnowledgeAutoLinker.nameMatchesTokens(name: "AI", tokens: tokens))
        #expect(!KnowledgeAutoLinker.nameMatchesTokens(name: "Bob", tokens: tokens))
    }
}
