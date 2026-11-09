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
            for: Schema(SchemaV14.models, version: SchemaV14.versionIdentifier),
            migrationPlan: EiginMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let intents = try migrated.mainContext.fetch(FetchDescriptor<Intent>())
        #expect(intents.first?.id == intentID)
        #expect(intents.first?.schedules.first?.hour == 7)
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<IntentInitiative>()) == 0)
    }

    @Test @MainActor func upgradePreservesClaimsAndStartsDiscoveryWithoutHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store")
        let chatID: UUID
        do {
            let old = try ModelContainer(
                for: Schema(SchemaV12.models, version: SchemaV12.versionIdentifier),
                configurations: ModelConfiguration(url: url)
            )
            let context = old.mainContext
            let agent = Agent(name: "Agent", providerID: UUID(), model: "test")
            let intent = Intent(
                agentID: agent.id,
                content: "Routine",
                schedules: [IntentSchedule(content: "Daily", frequency: .daily, hour: 7, minute: 0)]
            )
            let agreement = IntentInitiative(
                intentID: intent.id,
                scheduleID: intent.schedules[0].id,
                instructions: "Help",
                notificationBody: "Ready?"
            )
            let chat = Chat(agentID: agent.id)
            chatID = chat.id
            context.insert(agent)
            context.insert(intent)
            context.insert(agreement)
            context.insert(chat)
            context.insert(InitiativeRegistration(id: "legacy", payload: Data()))
            context.insert(InitiativeOccurrence(
                id: "legacy:1",
                registrationID: "legacy",
                deliveredAt: .now,
                chatID: chat.id,
                intentIDs: [intent.id]
            ))
            try context.save()
        }
        let migrated = try ModelContainer(
            for: Schema(SchemaV14.models, version: SchemaV14.versionIdentifier),
            migrationPlan: EiginMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = migrated.mainContext
        #expect(try context.fetch(FetchDescriptor<InitiativeOccurrence>()).first?.chatID == chatID)
        #expect(try context.fetchCount(FetchDescriptor<InitiativeRegistration>()) == 1)
        try WaitingInitiativeStore.reconcile(context: context)
        #expect(try context.fetchCount(FetchDescriptor<WaitingInitiative>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<InitiativeCursor>()) == 1)
    }
}
