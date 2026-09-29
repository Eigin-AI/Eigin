@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("FirmSource schema migration", .serialized)
struct FirmSourceMigrationTests {
    /// Seeds a V7 store with a single FirmSource, then lets the container
    /// deallocate so the file is closed before V8 reopens it.
    @MainActor
    private func seedV7Store(at url: URL) throws {
        let container = try ModelContainer(
            for: Schema(SchemaV7.models, version: SchemaV7.versionIdentifier),
            configurations: ModelConfiguration(url: url)
        )
        let source = SchemaV1.FirmSource(
            path: "knowledge/fact/likes_tea.firm",
            content: "fact likes_tea { claim = \"Likes tea\" }"
        )
        container.mainContext.insert(source)
        try container.mainContext.save()
    }

    @Test @MainActor func migratesV7FirmSourceSeedingMemorySignals() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("firmsource-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        try seedV7Store(at: url)
        let before = Date()

        // Reopen under the current schema, running the full V7 → … → V10 chain.
        let migrated = try ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            migrationPlan: EiginMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )

        let sources = try migrated.mainContext.fetch(FetchDescriptor<FirmSource>())
        let source = try #require(sources.first)

        // Content preserved.
        #expect(source.path == "knowledge/fact/likes_tea.firm")

        // Seeded as touched once at upgrade time — the grace period that keeps
        // pre-existing knowledge from looking ancient-and-unused to eviction.
        #expect(source.accessCount == 1)
        let lastAccessed = try #require(source.lastAccessedAt)
        #expect(lastAccessed >= before)

        // Other signals start neutral.
        #expect(source.importance == 0.5)
        #expect(source.expired == false)
        #expect(source.lastReviewedAt == nil)
    }
}
