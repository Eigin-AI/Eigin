@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Initiative migration", .serialized)
struct InitiativeMigrationTests {
    @Test @MainActor func upgradingKeepsExistingSchedulesSilent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store")
        let intentID: UUID
        do {
            let old = try ModelContainer(
                for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
                configurations: ModelConfiguration(url: url)
            )
            let intent = Intent(
                agentID: UUID(),
                content: "Existing news agreement",
                schedules: [IntentSchedule(
                    content: "Morning",
                    frequency: .daily,
                    hour: 7,
                    minute: 0
                )]
            )
            intentID = intent.id
            old.mainContext.insert(intent)
            try old.mainContext.save()
        }
        let migrated = try ModelContainer(
            for: Schema(SchemaV11.models, version: SchemaV11.versionIdentifier),
            migrationPlan: EiginMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let intents = try migrated.mainContext.fetch(FetchDescriptor<Intent>())
        #expect(intents.first?.id == intentID)
        #expect(intents.first?.schedules.first?.hour == 7)
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<IntentInitiative>()) == 0)
    }
}
