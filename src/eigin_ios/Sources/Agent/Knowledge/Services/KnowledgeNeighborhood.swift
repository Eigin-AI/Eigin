import Foundation

/// A named reference between the focused entity and one immediate neighbor.
struct KnowledgeRelationship: Identifiable {
    let predicate: String
    let incoming: Bool
    let entity: FirmEntity

    var id: String {
        "\(incoming):\(predicate):\(entity.id)"
    }
}

/// A single service query supplies both the graph and its named relationship rows.
struct KnowledgeNeighborhood {
    let focus: FirmEntity
    let neighbors: [FirmEntity]
    let relationships: [KnowledgeRelationship]

    init(focus: FirmEntity, related: [FirmEntity]) {
        self.focus = focus
        var seen: Set<String> = []
        neighbors = related.filter {
            $0.id != focus.id && seen.insert($0.id).inserted
        }.sorted { $0.id < $1.id }
        relationships = neighbors.flatMap { neighbor in
            KnowledgePresentation.predicates.flatMap { predicate -> [KnowledgeRelationship] in
                var rows: [KnowledgeRelationship] = []
                if Self.references(focus, predicate: predicate).contains(neighbor.id) {
                    rows.append(.init(predicate: predicate, incoming: false, entity: neighbor))
                }
                if Self.references(neighbor, predicate: predicate).contains(focus.id) {
                    rows.append(.init(predicate: predicate, incoming: true, entity: neighbor))
                }
                return rows
            }
        }
    }

    /// IDs referenced by `predicate` fields on `entity`, compared like for
    /// like with graph entity IDs (qualified).
    static func references(_ entity: FirmEntity, predicate: String) -> Set<String> {
        func ids(_ value: FirmFieldValue) -> [String] {
            switch value {
            case .entityReference(let entityId): [entityId]
            case .fieldReference(let entityId, _): [entityId]
            case .list(let items): items.flatMap(ids)
            default: []
            }
        }
        return Set(entity.fields.filter { $0.name == predicate }.flatMap { ids($0.value) })
    }
}

/// Stored content and identity without invented descriptions or inferred subject types.
struct KnowledgePresentation {
    /// Short sheet description; full content remains available in entity details.
    var summary: String? {
        guard let content else { return nil }
        guard content.count > 140 else { return content }
        return String(content.prefix(139)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static let types = ["actor", "thing", "fact", "output", "note"]
    static let predicates = ["relates_to", "belongs_to", "uses", "describes", "supersedes"]

    let name: String
    let content: String?
    let fields: [FirmField]

    init(_ entity: FirmEntity) {
        func string(_ key: String) -> String? {
            guard case .string(let value) = entity.fields.first(where: { $0.name == key })?.value,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        let id = Self.shortID(entity)
        if let storedName = string("name") {
            name = storedName
        } else if id.range(of: "^[a-z]+(?:_[a-z]+)*$", options: .regularExpression) != nil {
            let words = id.replacingOccurrences(of: "_", with: " ")
            name = words.prefix(1).uppercased() + words.dropFirst()
        } else {
            name = id
        }
        let primary: String? = switch entity.entityType {
        case "fact": "claim"
        case "output", "note": "content"
        default: nil
        }
        content = primary.flatMap(string)
        fields = entity.fields.filter {
            $0.name != "name" && $0.name != "tags" && $0.name != primary
                && !Self.predicates.contains($0.name)
        }
    }

    static func isBundled(_ entity: FirmEntity) -> Bool {
        let path = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.bundledPrefix,
            type: entity.entityType,
            id: shortID(entity)
        )
        return BundledKnowledge.allSources.contains { $0.path == path }
    }

    static func shortID(_ entity: FirmEntity) -> String {
        let prefix = entity.entityType + "."
        return entity.id.hasPrefix(prefix) ? String(entity.id.dropFirst(prefix.count)) : entity.id
    }
}

// MARK: - Localized labels

/// Localized display names for canonical types and relationship predicates.
enum KnowledgeLabels {
    static func typeName(_ type: String) -> String {
        switch type {
        case "actor": Localized.Facts.Kind.actor
        case "thing": Localized.Facts.Kind.thing
        case "fact": Localized.Facts.Kind.fact
        case "output": Localized.Facts.Kind.output
        case "note": Localized.Facts.Kind.note
        default: type.capitalized
        }
    }

    static func categoryName(_ type: String) -> String {
        switch type {
        case "actor": Localized.Facts.Kind.actors
        case "thing": Localized.Facts.Kind.things
        case "fact": Localized.Facts.Kind.facts
        case "output": Localized.Facts.Kind.outputs
        case "note": Localized.Facts.Kind.notes
        default: type.capitalized
        }
    }

    static func predicate(_ name: String) -> String {
        switch name {
        case "relates_to": Localized.Knowledge.Relationship.relatesTo
        case "belongs_to": Localized.Knowledge.Relationship.belongsTo
        case "uses": Localized.Knowledge.Relationship.uses
        case "describes": Localized.Knowledge.Relationship.describes
        case "supersedes": Localized.Knowledge.Relationship.supersedes
        default: name
        }
    }

    /// A named relationships row: the stored predicate plus an incoming marker.
    static func relationshipLabel(_ relationship: KnowledgeRelationship) -> String {
        let label = predicate(relationship.predicate)
        return relationship
            .incoming ? "\(label) \(Localized.Knowledge.Relationship.incoming)" : label
    }
}
