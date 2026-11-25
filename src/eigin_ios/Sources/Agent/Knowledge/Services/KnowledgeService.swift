import Foundation
import SwiftData

/// Manages the agent's unified knowledge base backed by Firm.
///
/// Loads bundled schemas and seed entities first, then user/agent-created
/// content from SwiftData, builds the Firm graph, and exposes query and
/// mutation operations.
///
/// Knowledge is scoped to spaces and agents: `spaceID/agentID: nil` means global
/// (visible everywhere). A specific spaceID/agentID means only visible in that
/// space/agent. The graph is rebuilt when the active space or agent changes.
protocol KnowledgeService: Sendable {
    var isBuilt: Bool { get }
    func rebuild(spaceID: UUID?, agentID: UUID?, accessPolicy: SpaceAccessPolicy?) async throws
    func query(_ queryString: String, spaceID: UUID?, agentID: UUID?) async throws
        -> FirmQueryResult
    func getEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> FirmEntity?
    func listEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws -> [String]
    func listSchemas(spaceID: UUID?, agentID: UUID?) async throws -> [String]
    func getRelated(
        type: String,
        id: String,
        direction: FirmDirection,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws
        -> [FirmEntity]
    func addEntity(_ entity: FirmEntity, spaceID: UUID?, agentID: UUID?, chatID: UUID?) async throws
    func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
    func setExpired(
        type: String, id: String, expired: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws
    func setContested(
        type: String, id: String, contested: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws
    func setImportance(
        type: String, id: String, importance: Double, spaceID: UUID?, agentID: UUID?
    ) async throws
    /// Stamp `lastReviewedAt` on the given entries (qualified IDs like
    /// `"fact.x"`), marking that consolidation surfaced them this run.
    func markReviewed(_ qualifiedIDs: [String], spaceID: UUID?, agentID: UUID?) async throws
    func isBundled(path: String) -> Bool
    func getSource(path: String, spaceID: UUID?, agentID: UUID?) async throws -> String?
    func findEntitySource(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> String?
    func getSchema(entityType: String, spaceID: UUID?, agentID: UUID?) async throws -> FirmSchema?
    func getFirmSource(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> FirmSource?
    func recordAccess(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async
    /// Batch variant of ``recordAccess(type:id:spaceID:agentID:)``.
    /// Records several explicit retrievals in one write transaction.
    func recordAccess(
        _ entities: [(type: String, id: String)],
        spaceID: UUID?,
        agentID: UUID?
    ) async
    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource]
    func unexpiredEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws
        -> [FirmEntity]
    /// Whether a memory is hidden from the knowledge views: its source is
    /// soft-hidden (expired), or an active entry supersedes it via a
    /// `supersedes` edge. Search keeps its own include_expired path; this
    /// gates presentation only (graph, list, detail).
    func isRetired(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> Bool
}

enum KnowledgeServiceError: LocalizedError {
    case notBuilt
    case entityNotFound(type: String, id: String)
    case cannotDeleteBundled(type: String, id: String)
    case cannotModifyBundled(type: String, id: String)

    var errorDescription: String? {
        switch self {
        case .notBuilt:
            "Knowledge workspace has not been built."
        case .entityNotFound(let type, let id):
            "Could not find a deletable source file for \(type).\(id). It may be stored in a legacy multi-entity file that needs manual cleanup."
        case .cannotDeleteBundled(let type, let id):
            "Cannot delete \(type).\(id) because it is a bundled knowledge entry."
        case .cannotModifyBundled(let type, let id):
            "Cannot modify \(type).\(id) because it is a bundled knowledge entry."
        }
    }
}
