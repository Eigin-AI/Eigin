import Foundation
import SwiftData

extension DefaultKnowledgeService {
    func query(
        _ queryString: String,
        spaceID: UUID?,
        agentID: UUID?
    ) throws -> FirmQueryResult {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.query(queryString: queryString)
    }

    func getEntity(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) throws -> FirmEntity? {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.getEntity(entityType: type, id: id)
    }

    func listEntities(type: String, spaceID: UUID?, agentID: UUID?) throws -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        let qualified = try session.listEntities(entityType: type)
        // App callers use short IDs for entity and relationship lookups.
        let prefix = type + "."
        return qualified.map { id in
            id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
        }
    }

    func listSchemas(spaceID: UUID?, agentID: UUID?) throws -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.listSchemas()
    }

    func getRelated(
        type: String,
        id: String,
        direction: FirmDirection,
        spaceID: UUID?,
        agentID: UUID?
    ) throws -> [FirmEntity] {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.getRelated(entityType: type, id: id, direction: direction)
    }

    func getSource(path: String, spaceID: UUID?, agentID: UUID?) throws -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.sources().first { $0.path == path }?.content
    }

    func findEntitySource(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) throws -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.findEntitySource(entityType: type, id: id)?.path
    }

    func getSchema(entityType: String, spaceID: UUID?, agentID: UUID?) throws -> FirmSchema? {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.getSchema(entityType: entityType)
    }

    /// Entities of `type` visible in the scope, excluding soft-hidden
    /// (`expired`) memories. Expiry lives on the `FirmSource` row, resolved to
    /// the shadow winner, so a scoped copy can expire independently.
    func unexpiredEntities(
        type: String,
        spaceID: UUID?,
        agentID: UUID?
    ) throws -> [FirmEntity] {
        stateLock.lock()
        defer { stateLock.unlock() }
        let visible = try allVisibleSources(spaceID: spaceID, agentID: agentID)
        let expiredKeys = Set(visible.filter(\.expired).map { entityKey(for: $0.path) })
        let entityIDs = try listEntities(type: type, spaceID: spaceID, agentID: agentID)
        var result: [FirmEntity] = []
        for entityID in entityIDs {
            let shortID = entityID.hasPrefix("\(type).")
                ? String(entityID.dropFirst(type.count + 1)) : entityID
            if expiredKeys.contains("\(type).\(shortID)") { continue }
            guard let entity = try getEntity(
                type: type, id: entityID, spaceID: spaceID, agentID: agentID
            ) else { continue }
            result.append(entity)
        }
        return result
    }

    func isRetired(type: String, id: String, spaceID: UUID?, agentID: UUID?) throws -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try isRetired(type: type, id: id, spaceID: spaceID, agentID: agentID, visited: [])
    }

    func isRetired(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?,
        visited: Set<String>
    ) throws -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        var visited = visited
        let rawID = id.hasPrefix("\(type).") ? String(id.dropFirst(type.count + 1)) : id
        let shortID = FirmIDNormalization.normalize(rawID)
        let key = "\(type).\(shortID)"
        guard visited.insert(key).inserted else { return false }

        let visible = try allVisibleSources(spaceID: spaceID, agentID: agentID)
        if visible.contains(where: { $0.expired && entityKey(for: $0.path) == key }) {
            return true
        }
        // Explicit result type — the type checker crashes without it.
        let fetched: FirmEntity? = try getEntity(
            type: type, id: shortID, spaceID: spaceID, agentID: agentID
        )
        guard let fetched else { return false }

        // Only live predecessors retire their superseded targets.
        let incoming = try getRelated(
            type: fetched.entityType, id: KnowledgePresentation.shortID(fetched),
            direction: .incoming, spaceID: spaceID, agentID: agentID
        )
        let qualifiedKey = FirmIDNormalization.normalize(fetched.id)
        for predecessor in incoming
            where KnowledgeNeighborhood.references(predecessor, predicate: "supersedes")
            .map(FirmIDNormalization.normalize).contains(qualifiedKey)
        {
            if try !isRetired(
                type: predecessor.entityType,
                id: KnowledgePresentation.shortID(predecessor),
                spaceID: spaceID, agentID: agentID, visited: visited
            ) { return true }
        }
        return false
    }
}
