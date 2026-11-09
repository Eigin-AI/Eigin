@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Prepared follow-up migration")
@MainActor struct FollowUpMigrationTests {
    @Test func v13RequestsAndWaitingStateSurviveUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        let instant = Date.now
        do {
            let container = try ModelContainer(
                for: Schema(SchemaV13.models, version: SchemaV13.versionIdentifier),
                configurations: ModelConfiguration(url: url)
            )
            let context = container.mainContext
            let agent = Agent(name: "Agent", providerID: UUID(), model: "test")
            context.insert(agent)
            context.insert(Chat(agentID: agent.id))
            let request = SchemaV1.AgentInitiativeRequest(
                agentID: agent.id,
                message: "Prepared",
                title: "Title",
                summary: "Briefing"
            )
            context.insert(request)
            let handled = SchemaV1.AgentInitiativeRequest(agentID: agent.id, message: "Handled")
            handled.handledAt = instant
            context.insert(handled)
            context.insert(InitiativeCursor(
                initiativeID: UUID(),
                revision: "revision",
                evaluatedThrough: instant,
                timeZoneIdentifier: "UTC"
            ))
            context.insert(WaitingInitiative(
                id: "waiting",
                initiativeID: UUID(),
                revision: "revision",
                agentID: agent.id,
                spaceID: nil,
                dueAt: instant,
                registrationID: "registration",
                body: "Invitation"
            ))
            try context.save()
        }
        let migrated = try ModelContainer(
            for: Schema(SchemaV14.models, version: SchemaV14.versionIdentifier),
            migrationPlan: EiginMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = migrated.mainContext
        let requests = try context.fetch(FetchDescriptor<AgentInitiativeRequest>())
        #expect(requests.count == 2)
        #expect(requests
            .allSatisfy {
                $0.dueAt == nil && $0.spaceID == nil && $0.chatID == nil && $0.disposition == nil
            })
        let pending = try #require(requests.first(where: { $0.message == "Prepared" }))
        #expect(pending.title == "Title")
        #expect(pending.summary == "Briefing")
        #expect(pending.handledAt == nil)
        #expect(requests.first(where: { $0.message == "Handled" })?.handledAt == instant)
        #expect(try context.fetchCount(FetchDescriptor<Chat>()) == 1)
        #expect(try context.fetch(FetchDescriptor<InitiativeCursor>()).first?
            .evaluatedThrough == instant)
        #expect(try WaitingMessageStore.messages(context: context).map(\.body) == ["Invitation"])
    }
}
