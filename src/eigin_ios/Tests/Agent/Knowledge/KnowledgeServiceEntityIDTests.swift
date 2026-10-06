@testable import Eigin
import Foundation
import SwiftData
import Testing

/// Regression tests for #285: rows stored under a raw entity ID (`…_v1`) must
/// update, supersede, and delete cleanly when addressed by the Firm-normalized
/// ID (`…_v_1`), instead of failing with a misleading `EntityAlreadyExists`.
@Suite("Knowledge entity ID storage", .serialized)
@MainActor
struct KnowledgeServiceEntityIDTests {
    // MARK: - Harness

    private func makeService() throws -> DefaultKnowledgeService {
        let container = try ModelContainer(
            for: Schema(SchemaV10.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return DefaultKnowledgeService(modelContainer: container)
    }

    private func note(_ id: String, content: String) -> FirmEntity {
        FirmEntity(
            id: "note.\(id)",
            entityType: "note",
            fields: [
                FirmField(name: "content", value: .string(value: content)),
                FirmField(
                    name: "created_at",
                    value: .dateTime(value: LocalDateFormatter.iso8601String(from: .now))
                ),
            ]
        )
    }

    // MARK: - #285: update via normalized ID

    @Test func updateViaNormalizedIDReplacesRawIDRow() async throws {
        let service = try makeService()

        // Created as `…_v1` (raw, as add_knowledge receives it). The graph
        // reports it back as `…_v_1`.
        try await service.addEntity(
            note("eigin_draft_v1", content: "short draft"),
            spaceID: nil, agentID: nil
        )
        #expect(
            try await service.getEntity(
                type: "note", id: "eigin_draft_v_1", spaceID: nil, agentID: nil
            ) != nil
        )

        // Update addressed by the normalized ID, with large content — the
        // exact shape that used to fail with EntityAlreadyExists (#285). The
        // old repro content was ~15KB; 699 lines (~17KB) stays comfortably in
        // that regime, without a trailing newline (the Firm DSL round-trip
        // chomps one).
        let bigContent = String(repeating: "# trust stack narrative\n", count: 699) + "# end"
        try await service.addEntity(
            note("eigin_draft_v_1", content: bigContent),
            spaceID: nil, agentID: nil
        )

        // Exactly one row survived, at the canonical path, holding the new
        // content.
        let matchingRows = try await service.allVisibleSources(spaceID: nil, agentID: nil)
            .filter { $0.path.contains("eigin_draft") }
        let row = try #require(
            matchingRows.count == 1 ? matchingRows[0] : nil,
            "Expected one eigin_draft row, got \(matchingRows.count): \(matchingRows.map(\.path))"
        )
        #expect(row.path == "knowledge/note/eigin_draft_v_1.firm")
        #expect(row.content.contains("trust stack narrative"))

        let updated = try #require(
            try await service.getEntity(
                type: "note",
                id: "eigin_draft_v_1",
                spaceID: nil,
                agentID: nil
            )
        )
        guard case .string(let actualContent)? = updated.fields
            .first(where: { $0.name == "content" })?.value
        else {
            Issue.record("Updated entity has no content field: \(updated.fields.map(\.name))")
            return
        }
        if actualContent != bigContent {
            let firstDiff = zip(actualContent, bigContent).first(where: { $0 != $1 })
            let counts = "\(actualContent.count)/\(bigContent.count)"
            Issue
                .record(
                    "Content round-trip mismatch: counts \(counts), first diff \(String(describing: firstDiff))"
                )
        }
        // The original raw ID still resolves to the updated entity too —
        // lookups are normalization-tolerant in both directions.
        let viaRawID = try #require(
            try await service.getEntity(
                type: "note",
                id: "eigin_draft_v1",
                spaceID: nil,
                agentID: nil
            )
        )
        guard case .string(let rawContent)? = viaRawID.fields
            .first(where: { $0.name == "content" })?.value
        else {
            Issue.record("Entity fetched via raw ID has no content field")
            return
        }
        #expect(rawContent == bigContent)
    }

    @Test func supersedeFlowsThroughNormalizedIDs() async throws {
        let service = try makeService()
        try await service.addEntity(
            note("old_draft_v1", content: "old"), spaceID: nil, agentID: nil
        )
        try await service.addEntity(
            note("old_draft_v2", content: "new"), spaceID: nil, agentID: nil
        )

        // The supersede tool: fetch the new entity (normalized ID), link it to
        // the old, expire the old.
        let replacement = try #require(
            try await service.getEntity(
                type: "note",
                id: "old_draft_v_2",
                spaceID: nil,
                agentID: nil
            )
        )
        try await appendKnowledgeRelation(
            "supersedes", targets: ["note.old_draft_v_1"], on: replacement,
            knowledgeService: service, spaceID: nil, agentID: nil, chatID: nil
        )
        try await service.setExpired(
            type: "note", id: "old_draft_v_1", expired: true, spaceID: nil, agentID: nil
        )

        // One row per entity (no EntityAlreadyExists, no forked duplicates).
        let rows = try await service.allVisibleSources(spaceID: nil, agentID: nil)
            .filter { $0.path.contains("old_draft") }
        #expect(rows.count == 2)

        // The new entry carries the supersedes link; the old is soft-hidden.
        #expect(rows.first { $0.path.contains("old_draft_v_2.firm") }?.expired == false)
        #expect(rows.first { $0.path.contains("old_draft_v_1.firm") }?.expired == true)
        let updated = try await service.getEntity(
            type: "note", id: "old_draft_v_2", spaceID: nil, agentID: nil
        )
        let linkField = try #require(updated?.fields.first { $0.name == "supersedes" })
        #expect(
            linkField.value == .list(items: [.entityReference(entityId: "note.old_draft_v_1")])
        )
    }

    // MARK: - Scope: no forking

    @Test func updateFromSpaceUpdatesGlobalRowInPlace() async throws {
        let service = try makeService()
        try await service.addEntity(
            note("meeting_notes", content: "global version"), spaceID: nil, agentID: nil
        )

        let space = UUID()
        try await service.addEntity(
            note("meeting_notes", content: "edited from space"), spaceID: space, agentID: nil
        )

        // The edit landed on the global row — no space-scoped fork was created.
        let rows = try await service.allVisibleSources(spaceID: space, agentID: nil)
            .filter { $0.path.contains("meeting_notes") }
        let row = try #require(
            rows.count == 1 ? rows[0] : nil,
            "Expected one meeting_notes row, got \(rows.count): \(rows.map(\.path))"
        )
        #expect(row.spaceID == nil)
        #expect(row.content.contains("edited from space"))
    }

    // MARK: - Bundled entities

    @Test func updateBundledEntityThrowsClearError() async throws {
        let service = try makeService()
        // thing.eigin ships as a bundled seed entity.
        do {
            try await service.addEntity(
                FirmEntity(
                    id: "thing.eigin", entityType: "thing",
                    fields: [FirmField(name: "name", value: .string(value: "Eigin"))]
                ),
                spaceID: nil, agentID: nil
            )
            Issue.record("Expected cannotModifyBundled")
        } catch let error as KnowledgeServiceError {
            guard case .cannotModifyBundled = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        // Nothing was persisted.
        let rows = try await service.allVisibleSources(spaceID: nil, agentID: nil)
            .filter { $0.path.hasPrefix("knowledge/") && $0.path.contains("/eigin.firm") }
        #expect(rows.isEmpty)
    }

    // MARK: - Mutator lookups tolerate raw vs normalized IDs

    @Test func setExpiredResolvesRawRowByNormalizedID() async throws {
        let service = try makeService()
        try await service.addEntity(
            note("expiry_probe_v1", content: "probe"), spaceID: nil, agentID: nil
        )

        try await service.setExpired(
            type: "note", id: "expiry_probe_v_1", expired: true, spaceID: nil, agentID: nil
        )

        let rows = try await service.allVisibleSources(spaceID: nil, agentID: nil)
            .filter { $0.path.contains("expiry_probe") }
        let row = try #require(
            rows.count == 1 ? rows[0] : nil,
            "Expected one expiry_probe row, got \(rows.count): \(rows.map(\.path))"
        )
        #expect(row.expired)
    }

    @Test func deleteResolvesRawRowByNormalizedID() async throws {
        let service = try makeService()
        try await service.addEntity(
            note("delete_probe_v1", content: "probe"), spaceID: nil, agentID: nil
        )

        try await service.deleteEntity(
            type: "note", id: "delete_probe_v_1", spaceID: nil, agentID: nil
        )

        let rows = try await service.allVisibleSources(spaceID: nil, agentID: nil)
            .filter { $0.path.contains("delete_probe") }
        #expect(rows.isEmpty)
    }

    @Test func deleteBundledEntityThrows() async throws {
        let service = try makeService()
        // thing.eigin ships as a bundled seed entity.
        do {
            try await service.deleteEntity(
                type: "thing", id: "eigin", spaceID: nil, agentID: nil
            )
            Issue.record("Expected cannotDeleteBundled")
        } catch let error as KnowledgeServiceError {
            guard case .cannotDeleteBundled = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func expireBundledEntityThrows() async throws {
        let service = try makeService()
        do {
            try await service.setExpired(
                type: "thing", id: "eigin", expired: true, spaceID: nil, agentID: nil
            )
            Issue.record("Expected cannotModifyBundled")
        } catch let error as KnowledgeServiceError {
            guard case .cannotModifyBundled = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func deleteUnknownIDThrows() async throws {
        let service = try makeService()
        do {
            try await service.deleteEntity(
                type: "note", id: "no_such_entity", spaceID: nil, agentID: nil
            )
            Issue.record("Expected entityNotFound")
        } catch let error as KnowledgeServiceError {
            guard case .entityNotFound = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }
}
