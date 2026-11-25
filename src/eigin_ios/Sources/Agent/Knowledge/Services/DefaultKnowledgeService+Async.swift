import Foundation

extension DefaultKnowledgeService {
    @concurrent
    func rebuild(spaceID: UUID?, agentID: UUID?, accessPolicy: SpaceAccessPolicy?) async throws {
        try withTransaction { try rebuild(
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: accessPolicy
        ) }
    }

    @concurrent
    func query(
        _ queryString: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> FirmQueryResult {
        try withTransaction { try query(queryString, spaceID: spaceID, agentID: agentID) }
    }

    @concurrent
    func getEntity(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> FirmEntity? {
        try withTransaction { try getEntity(type: type, id: id, spaceID: spaceID, agentID: agentID)
        }
    }

    @concurrent
    func listEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        try withTransaction { try listEntities(type: type, spaceID: spaceID, agentID: agentID) }
    }

    @concurrent
    func listSchemas(spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        try withTransaction { try listSchemas(spaceID: spaceID, agentID: agentID) }
    }

    @concurrent
    func getRelated(
        type: String,
        id: String,
        direction: FirmDirection,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [FirmEntity] {
        try withTransaction { try getRelated(
            type: type,
            id: id,
            direction: direction,
            spaceID: spaceID,
            agentID: agentID
        ) }
    }

    @concurrent
    func addEntity(
        _ entity: FirmEntity,
        spaceID: UUID?,
        agentID: UUID?,
        chatID: UUID?
    ) async throws {
        try withTransaction { try addEntity(
            entity,
            spaceID: spaceID,
            agentID: agentID,
            chatID: chatID
        ) }
    }

    @concurrent
    func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws {
        try withTransaction { try deleteEntity(
            type: type,
            id: id,
            spaceID: spaceID,
            agentID: agentID
        ) }
    }

    @concurrent
    func setExpired(
        type: String,
        id: String,
        expired: Bool,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws {
        try withTransaction { try setExpired(
            type: type,
            id: id,
            expired: expired,
            spaceID: spaceID,
            agentID: agentID
        ) }
    }

    @concurrent
    func setContested(
        type: String,
        id: String,
        contested: Bool,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws {
        try withTransaction { try setContested(
            type: type,
            id: id,
            contested: contested,
            spaceID: spaceID,
            agentID: agentID
        ) }
    }

    @concurrent
    func setImportance(
        type: String,
        id: String,
        importance: Double,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws {
        try withTransaction { try setImportance(
            type: type,
            id: id,
            importance: importance,
            spaceID: spaceID,
            agentID: agentID
        ) }
    }

    @concurrent
    func markReviewed(_ qualifiedIDs: [String], spaceID: UUID?, agentID: UUID?) async throws {
        try withTransaction { try markReviewed(qualifiedIDs, spaceID: spaceID, agentID: agentID) }
    }

    @concurrent
    func getSource(path: String, spaceID: UUID?, agentID: UUID?) async throws -> String? {
        try withTransaction { try getSource(path: path, spaceID: spaceID, agentID: agentID) }
    }

    @concurrent
    func findEntitySource(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> String? {
        try withTransaction { try findEntitySource(
            type: type,
            id: id,
            spaceID: spaceID,
            agentID: agentID
        ) }
    }

    @concurrent
    func getSchema(entityType: String, spaceID: UUID?, agentID: UUID?) async throws -> FirmSchema? {
        try withTransaction { try getSchema(
            entityType: entityType,
            spaceID: spaceID,
            agentID: agentID
        ) }
    }

    @concurrent
    func getFirmSource(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> FirmSource? {
        try withTransaction { try getFirmSource(
            type: type,
            id: id,
            spaceID: spaceID,
            agentID: agentID
        ) }
    }

    @concurrent
    func recordAccess(type: String, id: String, spaceID: UUID?, agentID: UUID?) async {
        withTransaction { recordAccess(type: type, id: id, spaceID: spaceID, agentID: agentID) }
    }

    @concurrent
    func recordAccess(
        _ entities: [(type: String, id: String)],
        spaceID: UUID?,
        agentID: UUID?
    ) async {
        withTransaction { recordAccess(entities, spaceID: spaceID, agentID: agentID) }
    }

    @concurrent
    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
        try withTransaction { try allVisibleSources(spaceID: spaceID, agentID: agentID) }
    }

    @concurrent
    func unexpiredEntities(
        type: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [FirmEntity] {
        try withTransaction { try unexpiredEntities(type: type, spaceID: spaceID, agentID: agentID)
        }
    }

    @concurrent
    func isRetired(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws -> Bool {
        try withTransaction { try isRetired(type: type, id: id, spaceID: spaceID, agentID: agentID)
        }
    }

    /// Keeps each synchronous operation uninterrupted on the concurrent executor.
    private func withTransaction<Value>(_ operation: () throws -> Value) rethrows -> Value {
        try stateLock.withLock(operation)
    }
}
