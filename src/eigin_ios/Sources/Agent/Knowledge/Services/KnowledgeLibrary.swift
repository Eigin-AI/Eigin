import Foundation

/// A stored entity with its list and detail presentation prepared once per load.
struct KnowledgeItem: Identifiable {
    let entity: FirmEntity
    let presentation: KnowledgePresentation
    var id: String {
        entity.id
    }

    init(_ entity: FirmEntity) {
        self.entity = entity
        presentation = KnowledgePresentation(entity)
    }
}

/// A category preview contains at most four items; the category page keeps the full set.
struct KnowledgeCategory: Identifiable {
    let type: String
    var items: [KnowledgeItem]
    var id: String {
        type
    }

    var preview: [KnowledgeItem] {
        Array(items.prefix(4))
    }

    var hasMore: Bool {
        items.count > 4
    }
}

/// Loads canonical knowledge categories and keeps previews and full lists in sync after deletion.
@MainActor
@Observable
final class KnowledgeLibrary {
    private(set) var categories: [KnowledgeCategory] = []
    private(set) var isLoading = true
    private(set) var error: (any Error)?
    private let service: any KnowledgeService
    private let agentID: UUID?
    private var generation = 0

    init(service: any KnowledgeService, agentID: UUID?) {
        self.service = service
        self.agentID = agentID
    }

    func load() async {
        generation += 1
        let ticket = generation
        isLoading = true
        error = nil
        defer { if generation == ticket { isLoading = false } }
        do {
            let schemas = try await service.listSchemas(spaceID: nil, agentID: agentID)
            var loaded: [KnowledgeCategory] = []
            for type in KnowledgePresentation.types where schemas.contains(type) {
                try Task.checkCancellation()
                let ids = try await service.listEntities(type: type, spaceID: nil, agentID: agentID)
                var entities: [(item: KnowledgeItem, date: Date?)] = []
                for id in ids {
                    try Task.checkCancellation()
                    if try await service.isRetired(
                        type: type, id: id, spaceID: nil, agentID: agentID
                    ) { continue }
                    if let entity = try await service.getEntity(
                        type: type,
                        id: id,
                        spaceID: nil,
                        agentID: agentID
                    ) {
                        entities.append((KnowledgeItem(entity), Self.createdAt(entity)))
                    }
                }
                entities.sort { left, right in
                    if left.date != right.date {
                        return (left.date ?? .distantPast) > (right.date ?? .distantPast)
                    }
                    return left.item.id < right.item.id
                }
                if !entities.isEmpty { loaded.append(KnowledgeCategory(
                    type: type,
                    items: entities.map(\.item)
                )) }
            }
            try Task.checkCancellation()
            guard generation == ticket else { return }
            categories = loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == ticket else { return }
            self.error = error
        }
    }

    func remove(_ id: String) {
        for index in categories.indices {
            categories[index].items.removeAll { $0.id == id }
        }
        categories.removeAll { $0.items.isEmpty }
    }

    private static func createdAt(_ entity: FirmEntity) -> Date? {
        guard case .dateTime(let value) = entity.fields.first(where: { $0.name == "created_at" })?
            .value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
    }
}
