@testable import Eigin
import Foundation
import os.lock
import SwiftData
import Testing

@Suite("SDK knowledge persistence", .serialized)
@MainActor
struct KnowledgePersistenceTests {
    private enum SaveFailure: Error { case rejected }

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func note(_ id: String, _ content: String) -> FirmEntity {
        .init(
            id: "note.\(id)",
            entityType: "note",
            fields: [.init(name: "content", value: .string(value: content))]
        )
    }

    private func content(_ entity: FirmEntity?) -> String? {
        guard case .string(let value)? = entity?.fields.first(where: { $0.name == "content" })?
            .value else { return nil }
        return value
    }

    @Test func asyncServiceEditsRunOffTheMainThread() async throws {
        let container = try container()
        let mainThreadSaves = OSAllocatedUnfairLock(initialState: [Bool]())
        let service: any KnowledgeService = DefaultKnowledgeService(
            modelContainer: container,
            persist: { context in
                mainThreadSaves.withLock { $0.append(Thread.isMainThread) }
                try context.save()
            }
        )
        try await service.addEntity(
            note("entry", "saved from the UI"),
            spaceID: nil,
            agentID: nil,
            chatID: nil
        )
        let saves = mainThreadSaves.withLock { $0 }
        #expect(!saves.isEmpty)
        #expect(saves.allSatisfy { !$0 })
        #expect(try await content(service.getEntity(
            type: "note",
            id: "entry",
            spaceID: nil,
            agentID: nil
        )) == "saved from the UI")
    }

    @Test func failedSavesRetainCommittedGraphAndRows() throws {
        let container = try container()
        let fail = OSAllocatedUnfairLock(initialState: false)
        let service = DefaultKnowledgeService(modelContainer: container, persist: { context in
            if fail.withLock({ $0 }) { throw SaveFailure.rejected }
            try context.save()
        })
        try service.addEntity(note("entry", "committed"), spaceID: nil, agentID: nil)
        fail.withLock { $0 = true }
        #expect(throws: SaveFailure.self) {
            try service.addEntity(note("entry", "unsaved"), spaceID: nil, agentID: nil)
        }
        #expect(throws: SaveFailure.self) {
            try service.deleteEntity(type: "note", id: "entry", spaceID: nil, agentID: nil)
        }
        #expect(throws: SaveFailure.self) {
            try service.setExpired(
                type: "note",
                id: "entry",
                expired: true,
                spaceID: nil,
                agentID: nil
            )
        }
        #expect(try content(service.getEntity(
            type: "note",
            id: "entry",
            spaceID: nil,
            agentID: nil
        )) == "committed")
        let rows = try ModelContext(container).fetch(FetchDescriptor<FirmSource>())
        #expect(rows.count == 1)
        #expect(rows[0].content.contains("committed"))
        #expect(!rows[0].expired)
        fail.withLock { $0 = false }
        try service.addEntity(note("entry", "saved later"), spaceID: nil, agentID: nil)
        #expect(try content(service.getEntity(
            type: "note",
            id: "entry",
            spaceID: nil,
            agentID: nil
        )) == "saved later")
    }

    @Test func lossyTypedEditLeavesCommittedContentUnchanged() throws {
        let container = try container()
        let service = DefaultKnowledgeService(modelContainer: container)
        try service.addEntity(note("entry", "committed"), spaceID: nil, agentID: nil)
        #expect(throws: KnowledgeSDKConversion.SDK.Failure.self) {
            try service.addEntity(note("entry", "Quoted \"text\""), spaceID: nil, agentID: nil)
        }
        #expect(try content(service.getEntity(
            type: "note",
            id: "entry",
            spaceID: nil,
            agentID: nil
        )) == "committed")
        let rows = try ModelContext(container).fetch(FetchDescriptor<FirmSource>())
        #expect(rows.count == 1)
        #expect(rows[0].content.contains("committed"))
    }

    @Test func failedAccessSaveDoesNotSuppressRetry() throws {
        let container = try container()
        let fail = OSAllocatedUnfairLock(initialState: false)
        let service = DefaultKnowledgeService(modelContainer: container, persist: { context in
            if fail.withLock({ $0 }) { throw SaveFailure.rejected }
            try context.save()
        })
        try service.addEntity(note("entry", "saved"), spaceID: nil, agentID: nil)
        fail.withLock { $0 = true }
        service.recordAccess(type: "note", id: "entry", spaceID: nil, agentID: nil)
        fail.withLock { $0 = false }
        service.recordAccess(type: "note", id: "entry", spaceID: nil, agentID: nil)
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<FirmSource>()).first)
        #expect(row.accessCount == 2)
    }

    @Test func deletingScopedWinnerPublishesGlobalFallback() throws {
        let container = try container()
        let context = ModelContext(container)
        let space = UUID()
        let path = "knowledge/note/shared.firm"
        context.insert(FirmSource(path: path, content: "note shared { content = \"global\" }"))
        context.insert(FirmSource(
            path: path,
            content: "note shared { content = \"scoped\" }",
            spaceID: space
        ))
        try context.save()
        let service = DefaultKnowledgeService(modelContainer: container)
        #expect(try content(service.getEntity(
            type: "note",
            id: "shared",
            spaceID: space,
            agentID: nil
        )) == "scoped")
        try service.deleteEntity(type: "note", id: "shared", spaceID: space, agentID: nil)
        #expect(try content(service.getEntity(
            type: "note",
            id: "shared",
            spaceID: space,
            agentID: nil
        )) == "global")
        #expect(try ModelContext(container).fetch(FetchDescriptor<FirmSource>()).count == 1)
    }

    @Test func failedPolicyRebuildCannotServePreviouslyAuthorizedGraph() throws {
        let container = try container()
        let context = ModelContext(container)
        let space = UUID()
        context.insert(FirmSource(
            path: "knowledge/note/secret.firm",
            content: "note secret { content = \"secret\" }",
            spaceID: space
        ))
        try context.save()
        let service = DefaultKnowledgeService(modelContainer: container)
        try service.rebuild(
            spaceID: nil,
            agentID: nil,
            accessPolicy: .init(currentSpaceID: nil, publicSpaceIDs: [space])
        )
        #expect(try service
            .getEntity(type: "note", id: "secret", spaceID: nil, agentID: nil) != nil)
        context.insert(FirmSource(path: "knowledge/note/broken.firm", content: "note broken {}"))
        try context.save()
        #expect(throws: (any Error).self) {
            try service.rebuild(
                spaceID: nil,
                agentID: nil,
                accessPolicy: .init(currentSpaceID: nil, publicSpaceIDs: [])
            )
        }
        #expect(!service.isBuilt)
        #expect(throws: (any Error).self) {
            _ = try service.getEntity(type: "note", id: "secret", spaceID: nil, agentID: nil)
        }
    }

    @Test func failedValidationLeavesPersistenceUntouched() throws {
        let container = try container()
        let service = DefaultKnowledgeService(modelContainer: container)
        let invalid = FirmEntity(id: "note.invalid", entityType: "note", fields: [])
        #expect(throws: (any Error).self) { try service.addEntity(
            invalid,
            spaceID: nil,
            agentID: nil
        ) }
        #expect(try ModelContext(container).fetch(FetchDescriptor<FirmSource>()).isEmpty)
    }

    @Test func concurrentScopesKeepTheirOwnRowsAndSnapshots() async throws {
        let container = try container()
        let concrete = DefaultKnowledgeService(modelContainer: container)
        let service: any KnowledgeService = concrete
        let inputs = (0 ..< 8).map { index in (UUID(), note("shared", "scope \(index)")) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (space, entity) in inputs {
                group.addTask {
                    try await service.addEntity(entity, spaceID: space, agentID: nil, chatID: nil)
                    let actual = try await service.getEntity(
                        type: "note",
                        id: "shared",
                        spaceID: space,
                        agentID: nil
                    )
                    #expect(actual == entity)
                }
            }
            try await group.waitForAll()
        }
        #expect(try ModelContext(container).fetch(FetchDescriptor<FirmSource>()).count == inputs
            .count)
        #expect(try await concrete
            .getEntity(type: "note", id: "shared", spaceID: nil, agentID: nil) == nil)
    }

    @Test func sourceLookupCannotFallBackToPrivateOrOtherAgentRows() throws {
        let container = try container()
        let service = DefaultKnowledgeService(modelContainer: container)
        let privateSpace = UUID()
        let privateAgent = UUID()
        try service.addEntity(
            note("secret", "private"),
            spaceID: privateSpace,
            agentID: privateAgent
        )
        #expect(try service
            .getFirmSource(type: "note", id: "secret", spaceID: nil, agentID: nil) == nil)
        #expect(try service.getFirmSource(
            type: "note",
            id: "secret",
            spaceID: privateSpace,
            agentID: nil
        ) == nil)
        #expect(try service.getFirmSource(
            type: "note",
            id: "secret",
            spaceID: privateSpace,
            agentID: privateAgent
        ) != nil)
    }

    @Test func externalReplacementInvalidatesTheGraphAsWellAsMetadata() throws {
        let container = try container()
        let service = DefaultKnowledgeService(modelContainer: container)
        try service.addEntity(note("entry", "old"), spaceID: nil, agentID: nil)
        let context = ModelContext(container)
        let row = try #require(context.fetch(FetchDescriptor<FirmSource>()).first)
        row.content = "note entry { content = \"external\" }"
        try context.save()
        service.invalidateVisibleSourcesCache()
        #expect(try content(service.getEntity(
            type: "note",
            id: "entry",
            spaceID: nil,
            agentID: nil
        )) == "external")
    }
}
