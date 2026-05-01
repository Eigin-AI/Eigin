import Foundation

/// Extracts high-signal text from a knowledge entity for embedding.
///
/// Rather than embedding the full .firm DSL source, we embed only the
/// primary semantic fields for each entity type. This reduces noise and
/// improves cosine similarity precision for semantic search.
enum KnowledgeEmbedding {
    /// Extract the text to embed for a given entity, based on its type.
    static func embeddingText(for entity: FirmEntity) -> String {
        switch entity.entityType {
        case "actor":
            actorText(entity)
        case "thing":
            thingText(entity)
        case "fact":
            factText(entity)
        case "output":
            outputText(entity)
        case "note":
            noteText(entity)
        default:
            // Fallback: concatenate all string fields.
            entity.fields.compactMap { field -> String? in
                if case .string(let v) = field.value { return v }
                return nil
            }.joined(separator: " ")
        }
    }

    // MARK: - Per-type extraction

    /// Actor: "Name, type" — e.g. "Daniel Rothmann, human"
    private static func actorText(_ entity: FirmEntity) -> String {
        let name = stringField(entity, "name") ?? entity.id
        let type = enumField(entity, "type")
        return [name, type].compactMap(\.self).joined(separator: ", ")
    }

    /// Thing: "Name, category" — e.g. "Eigin, digital"
    private static func thingText(_ entity: FirmEntity) -> String {
        let name = stringField(entity, "name") ?? entity.id
        let category = enumField(entity, "category")
        return [name, category].compactMap(\.self).joined(separator: ", ")
    }

    /// Fact: "Name: claim" or just "claim" — e.g. "Eigin privacy: Eigin runs on-device"
    private static func factText(_ entity: FirmEntity) -> String {
        let name = stringField(entity, "name")
        let claim = stringField(entity, "claim") ?? entity.id
        if let name, !name.isEmpty {
            return "\(name): \(claim)"
        }
        return claim
    }

    /// Output: "Name: content" (content truncated to 500 chars)
    private static func outputText(_ entity: FirmEntity) -> String {
        let name = stringField(entity, "name") ?? entity.id
        let content = stringField(entity, "content") ?? ""
        let truncated = content.count > 500 ? String(content.prefix(500)) : content
        if truncated.isEmpty { return name }
        return "\(name): \(truncated)"
    }

    /// Note: content verbatim
    private static func noteText(_ entity: FirmEntity) -> String {
        stringField(entity, "content") ?? entity.id
    }

    // MARK: - Field helpers

    private static func stringField(_ entity: FirmEntity, _ name: String) -> String? {
        guard let field = entity.fields.first(where: { $0.name == name }) else { return nil }
        if case .string(let v) = field.value { return v }
        return nil
    }

    private static func enumField(_ entity: FirmEntity, _ name: String) -> String? {
        guard let field = entity.fields.first(where: { $0.name == name }) else { return nil }
        if case .enum(let v) = field.value { return v }
        return nil
    }
}
