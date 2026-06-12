@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Intent schema migration", .serialized)
struct IntentMigrationTests {
    /// Seeds a V1 store with a decaying intent, then lets the container
    /// deallocate so the file is closed before V2 reopens it.
    @MainActor
    private func seedV1Store(at url: URL, agentID: UUID) throws {
        let container = try ModelContainer(
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
            configurations: ModelConfiguration(url: url)
        )
        let intent = SchemaV1.Intent(agentID: agentID, content: "Stay at 1900 calories")
        intent.reinforcedCount = 3
        container.mainContext.insert(intent)
        try container.mainContext.save()
    }

    @Test @MainActor func migratesV1IntentToV2PreservingContent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("intent-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let agentID = UUID()
        try seedV1Store(at: url, agentID: agentID)

        // Reopen the same store under V2 with the migration plan.
        let migrated = try ModelContainer(
            for: Schema(SchemaV2.models, version: SchemaV2.versionIdentifier),
            migrationPlan: EiginMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )

        let intents = try migrated.mainContext.fetch(FetchDescriptor<Intent>())
        let intent = try #require(intents.first)
        #expect(intent.content == "Stay at 1900 calories")
        // New collections default to empty; the dropped decay field is gone.
        #expect(intent.tasks.isEmpty)
        #expect(intent.events.isEmpty)
        #expect(intent.schedules.isEmpty)
        #expect(intent.isActive)
    }
}
