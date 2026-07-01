@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("PrimaryAgent")
struct PrimaryAgentTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
            configurations: config
        )
    }

    @Test("primary is the oldest agent by createdAt")
    func primaryIsOldest() {
        let older = Agent(name: "Original", providerID: UUID(), model: "gpt-4o")
        older.createdAt = Date(timeIntervalSince1970: 0)
        older.bootstrapComplete = false

        let newer = Agent(name: "Accidental", providerID: UUID(), model: "gpt-4o")
        newer.createdAt = Date(timeIntervalSince1970: 1000)
        newer.bootstrapComplete = true

        #expect([newer, older].primary === older)
        #expect([older, newer].primary === older)
    }

    @Test("primary is nil for an empty collection")
    func primaryIsNilWhenEmpty() {
        let agents: [Agent] = []
        #expect(agents.primary == nil)
    }

    @Test @MainActor func primaryDescriptorFetchesOldestAgent() throws {
        let container = try makeContainer()

        let older = Agent(name: "Original", providerID: UUID(), model: "gpt-4o")
        older.createdAt = Date(timeIntervalSince1970: 0)
        older.bootstrapComplete = false
        container.mainContext.insert(older)

        let newer = Agent(name: "Accidental", providerID: UUID(), model: "gpt-4o")
        newer.createdAt = Date(timeIntervalSince1970: 1000)
        newer.bootstrapComplete = true
        container.mainContext.insert(newer)

        let fetched = try container.mainContext.fetch(Agent.primaryDescriptor)

        #expect(fetched.primary?.name == "Original")
    }
}
