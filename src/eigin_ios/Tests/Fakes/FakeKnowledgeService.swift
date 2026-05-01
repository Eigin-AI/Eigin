@testable import Eigin
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

    // MARK: - Observability

    /// Every `spaceID` this fake has been called with, in order. Use to
    /// assert scope-passthrough across passes.
    private(set) var receivedSpaceIDs: [UUID?] = []
    /// Every `agentID` this fake has been called with, in order.
    private(set) var receivedAgentIDs: [UUID?] = []

    // MARK: - Error injection

    /// When set, `getRelated` throws instead of returning.
    var throwOnGetRelated: Bool = false

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
        switch direction {
        case .incoming: return relatedIncoming[qualifiedID] ?? []
        case .outgoing: return relatedOutgoing[qualifiedID] ?? []
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
        entities["\(type).\(id)"] = nil
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

    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
        record(spaceID: spaceID, agentID: agentID)
        return sources
    }

    func validEntities(
        type: String, spaceID: UUID?, agentID: UUID?, at date: Date
    ) async throws -> [FirmEntity] {
        record(spaceID: spaceID, agentID: agentID)
        return entities.values.filter { $0.entityType == type }
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
