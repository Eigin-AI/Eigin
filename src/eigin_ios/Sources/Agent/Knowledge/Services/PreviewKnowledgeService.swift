import Foundation

/// No-op implementation used as the environment default and for previews.
struct PreviewKnowledgeService: KnowledgeService {
    var isBuilt: Bool {
        false
    }

    func rebuild(
        spaceID: UUID?,
        agentID: UUID?,
        accessPolicy: SpaceAccessPolicy? = nil
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
        nil
    }

    func listEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        []
    }

    func listSchemas(spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        []
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
        chatID: UUID? = nil
    ) async throws {}
    func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws {}
    func setExpired(
        type: String, id: String, expired: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws {}
    func setContested(
        type: String, id: String, contested: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws {}
    func setImportance(
        type: String, id: String, importance: Double, spaceID: UUID?, agentID: UUID?
    ) async throws {}
    func markReviewed(_ qualifiedIDs: [String], spaceID: UUID?, agentID: UUID?) async throws {}
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

    func getSchema(entityType: String, spaceID: UUID?, agentID: UUID?) async throws -> FirmSchema? {
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

    func recordAccess(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async {}

    func recordAccess(
        _ entities: [(type: String, id: String)],
        spaceID: UUID?,
        agentID: UUID?
    ) async {}

    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
        []
    }

    func unexpiredEntities(
        type: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [FirmEntity] {
        []
    }

    func isRetired(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws -> Bool {
        false
    }
}
