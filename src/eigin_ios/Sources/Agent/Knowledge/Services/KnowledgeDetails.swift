import Foundation

/// Loads stored relationship predicates and reports deletion failures without leaving details.
@MainActor
@Observable
final class KnowledgeDetails {
    private(set) var relationships: [KnowledgeRelationship] = []
    private(set) var relationshipError: (any Error)?
    private(set) var isDeleting = false
    private let entity: FirmEntity
    private let service: any KnowledgeService
    private let agentID: UUID?

    init(entity: FirmEntity, service: any KnowledgeService, agentID: UUID?) {
        self.entity = entity
        self.service = service
        self.agentID = agentID
    }

    func load() async {
        relationshipError = nil
        do {
            let related = try await service.getRelated(
                type: entity.entityType, id: KnowledgePresentation.shortID(entity),
                direction: .both,
                spaceID: nil, agentID: agentID
            )
            try Task.checkCancellation()
            relationships = KnowledgeNeighborhood(focus: entity, related: related).relationships
        } catch is CancellationError {
            return
        } catch {
            relationshipError = error
        }
    }

    /// The caller dismisses and updates its list only after a successful delete.
    func delete() async -> Bool {
        guard !isDeleting, !KnowledgePresentation.isBundled(entity) else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteEntity(
                type: entity.entityType,
                id: KnowledgePresentation.shortID(entity),
                spaceID: nil,
                agentID: agentID
            )
            return true
        } catch {
            return false
        }
    }
}

/// Display only populated stored values, preserving references and full text.
enum KnowledgeFormatting {
    static func label(_ name: String) -> String {
        let words = name.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func value(_ value: FirmFieldValue) -> String? {
        switch value {
        case .string(let text), .enum(let text), .path(let text), .dateTime(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        case .integer(let number): return "\(number)"
        case .float(let number): return "\(number)"
        case .boolean(let flag): return flag ? Localized.Knowledge.Value.yes : Localized.Knowledge
            .Value.no
        case .entityReference(let id): return id
        case .fieldReference(let entityID, let fieldID): return "\(entityID).\(fieldID)"
        case .currency(let amount, let code): return "\(amount) \(code)"
        case .list(let items):
            let values = items.compactMap(Self.value)
            return values.isEmpty ? nil : values.joined(separator: " · ")
        }
    }
}
