#if DEBUG || EIGIN_DEV
import Foundation

/// Configurable fake ``KnowledgeService`` for tests.
///
/// Defaults to an empty, happy-path no-op. Tests populate the public
/// fixtures (`entities`, `sources`, `relatedIncoming`, `relatedOutgoing`)
/// as needed, and the public flags control error injection.
final class FakeKnowledgeService: KnowledgeService, @unchecked Sendable {
    // MARK: - Fixtures

    /// Entity graph keyed by qualified ID (`"actor.mette"`).
    var entities: [String: FirmEntity] = [:]
    /// FirmSource rows used for embedding lookup and chat-id mapping.
    var sources: [FirmSource] = []
    /// Incoming related entities keyed by qualified ID.
    var relatedIncoming: [String: [FirmEntity]] = [:]
    /// Outgoing related entities keyed by qualified ID.
    var relatedOutgoing: [String: [FirmEntity]] = [:]
    /// Records each `getRelated` call as `(qualifiedID, direction)` in order.
    private(set) var relatedRequests: [(String, FirmDirection)] = []
    /// When set, replaces the canned related result for the given qualified ID.
    var relatedOverride: ((String) async throws -> [FirmEntity])?

    // MARK: - Observability

    /// Every `spaceID` this fake has been called with, in order. Use to
    /// assert scope-passthrough across passes.
    private(set) var receivedSpaceIDs: [UUID?] = []
    /// Every `agentID` this fake has been called with, in order.
    private(set) var receivedAgentIDs: [UUID?] = []

    // MARK: - Error injection

    /// When set, `getRelated` throws instead of returning.
    var throwOnGetRelated: Bool = false
    /// When set, deletion fails without changing the stored entities.
    var throwOnDeleteEntity = false
    /// When set, category enumeration fails.
    var throwOnListSchemas = false

    // MARK: - KnowledgeService

    var isBuilt: Bool {
        true
    }

    func rebuild(spaceID: UUID?, agentID: UUID?, accessPolicy: SpaceAccessPolicy?) async throws {}

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
        record(spaceID: spaceID, agentID: agentID)
        return entities["\(type).\(id)"]
    }

    func listEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        record(spaceID: spaceID, agentID: agentID)
        return entities.values
            .filter { $0.entityType == type }
            .map { short(from: $0.id, type: type) }
    }

    func listSchemas(spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        if throwOnListSchemas { throw NSError(domain: "FakeKnowledgeService", code: 3) }
        record(spaceID: spaceID, agentID: agentID)
        return Array(Set(entities.values.map(\.entityType))).sorted()
    }

    func getRelated(
        type: String, id: String, direction: FirmDirection,
        spaceID: UUID?, agentID: UUID?
    ) async throws -> [FirmEntity] {
        if throwOnGetRelated {
            throw NSError(domain: "FakeKnowledgeService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "throwOnGetRelated set",
            ])
        }
        record(spaceID: spaceID, agentID: agentID)
        let qualifiedID = "\(type).\(id)"
        relatedRequests.append((qualifiedID, direction))
        if let relatedOverride {
            return try await relatedOverride(qualifiedID)
        }
        let incoming = relatedIncoming[qualifiedID] ?? []
        switch direction {
        case .incoming: return incoming
        case .outgoing: return relatedOutgoing[qualifiedID] ?? []
        case .both:
            var seen: Set<String> = []
            return (incoming + (relatedOutgoing[qualifiedID] ?? [])).filter {
                seen.insert($0.id).inserted
            }
        @unknown default: return []
        }
    }

    func addEntity(
        _ entity: FirmEntity,
        spaceID: UUID?,
        agentID: UUID?,
        chatID: UUID?
    ) async throws {
        entities[entity.id] = entity
    }

    func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws {
        record(spaceID: spaceID, agentID: agentID)
        if throwOnDeleteEntity { throw NSError(domain: "FakeKnowledgeService", code: 2) }
        entities["\(type).\(id)"] = nil
    }

    /// Qualified IDs (`"fact.x"`) currently soft-hidden via ``setExpired``.
    private(set) var expiredIDs: Set<String> = []

    func setExpired(
        type: String, id: String, expired: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws {
        record(spaceID: spaceID, agentID: agentID)
        let key = "\(type).\(id)"
        if expired { expiredIDs.insert(key) } else { expiredIDs.remove(key) }
    }

    /// Qualified IDs (`"fact.x"`) currently flagged via ``setContested``.
    private(set) var contestedIDs: Set<String> = []

    func setContested(
        type: String, id: String, contested: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws {
        record(spaceID: spaceID, agentID: agentID)
        let key = "\(type).\(id)"
        if contested { contestedIDs.insert(key) } else { contestedIDs.remove(key) }
    }

    /// Importance values (`"fact.x"` → value) set via ``setImportance``.
    private(set) var importanceByID: [String: Double] = [:]

    func setImportance(
        type: String, id: String, importance: Double, spaceID: UUID?, agentID: UUID?
    ) async throws {
        record(spaceID: spaceID, agentID: agentID)
        importanceByID["\(type).\(id)"] = importance
    }

    /// Qualified IDs stamped via ``markReviewed``.
    private(set) var reviewedIDs: [String] = []

    func markReviewed(_ qualifiedIDs: [String], spaceID: UUID?, agentID: UUID?) async throws {
        record(spaceID: spaceID, agentID: agentID)
        reviewedIDs.append(contentsOf: qualifiedIDs)
    }

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
        kind: KnowledgeAccessKind,
        spaceID: UUID?,
        agentID: UUID?
    ) async {}

    func recordAccess(
        _ entities: [(type: String, id: String)],
        kind: KnowledgeAccessKind,
        spaceID: UUID?,
        agentID: UUID?
    ) async {}

    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
        record(spaceID: spaceID, agentID: agentID)
        return sources
    }

    func unexpiredEntities(
        type: String, spaceID: UUID?, agentID: UUID?
    ) async throws -> [FirmEntity] {
        record(spaceID: spaceID, agentID: agentID)
        return entities.values.filter { $0.entityType == type && !expiredIDs.contains($0.id) }
    }

    /// Qualified IDs (`"fact.x"`) reported as retired by ``isRetired`` in
    /// addition to expired entries (``setExpired``).
    var retiredIDs: Set<String> = []

    func isRetired(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws -> Bool {
        record(spaceID: spaceID, agentID: agentID)
        let key = "\(type).\(id)"
        return retiredIDs.contains(key) || expiredIDs.contains(key)
    }

    // MARK: - Helpers

    private func record(spaceID: UUID?, agentID: UUID?) {
        receivedSpaceIDs.append(spaceID)
        receivedAgentIDs.append(agentID)
    }

    private func short(from entityID: String, type: String) -> String {
        let prefix = type + "."
        return entityID.hasPrefix(prefix) ? String(entityID.dropFirst(prefix.count)) : entityID
    }
}
#endif
