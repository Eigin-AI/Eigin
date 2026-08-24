import Foundation

/// Shared formatting for knowledge tool results.
func formatKnowledgeEntity(_ entity: FirmEntity) -> [String: Any] {
    var dict: [String: Any] = [
        "id": entity.id,
        "type": entity.entityType,
    ]

    var data: [String: Any] = [:]
    for field in entity.fields {
        data[field.name] = formatKnowledgeFieldValue(field.value)
    }
    dict["data"] = data

    return dict
}

/// Format an entity with its relationship ID lists (always included) and
/// optionally expanded related entity details.
func formatKnowledgeEntityWithRelations(
    _ entity: FirmEntity,
    knowledgeService: any KnowledgeService,
    spaceID: UUID?,
    agentID: UUID? = nil,
    includeRelatedDetail: Bool = false,
    relatedLimit: Int = 5
) async -> [String: Any] {
    var dict = formatKnowledgeEntity(entity)

    let shortID = knowledgeShortID(from: entity.id, type: entity.entityType)

    // Always include the full relationship ID lists.
    let incoming = await (try? knowledgeService.getRelated(
        type: entity.entityType, id: shortID,
        direction: .incoming, spaceID: spaceID, agentID: agentID
    )) ?? []
    let outgoing = await (try? knowledgeService.getRelated(
        type: entity.entityType, id: shortID,
        direction: .outgoing, spaceID: spaceID, agentID: agentID
    )) ?? []

    var relationships: [String: Any] = [:]
    if !outgoing.isEmpty { relationships["references"] = outgoing.map(\.id) }
    if !incoming.isEmpty { relationships["referenced_by"] = incoming.map(\.id) }
    if !relationships.isEmpty { dict["relationships"] = relationships }

    // Optionally expand the top N related entities with full detail, sorted by recency.
    if includeRelatedDetail {
        let allRelated = (incoming + outgoing)
        // De-duplicate by ID.
        var seen = Set<String>()
        let unique = allRelated.filter { seen.insert($0.id).inserted }
        // Sort by created_at descending (most recent first).
        let sorted = unique.sorted { a, b in
            let aDate = dateFromEntity(a)
            let bDate = dateFromEntity(b)
            return aDate > bDate
        }
        let top = Array(sorted.prefix(relatedLimit))
        if !top.isEmpty {
            dict["related_detail"] = top.map { formatKnowledgeEntity($0) }
        }
    }

    return dict
}

/// Extract the short ID from a qualified ID (e.g. "thing.eigin" → "eigin").
func knowledgeShortID(from qualifiedID: String, type: String) -> String {
    let prefix = type + "."
    return qualifiedID.hasPrefix(prefix) ? String(qualifiedID.dropFirst(prefix.count)) : qualifiedID
}

/// The five knowledge entity types.
let knowledgeEntityTypes: Set<String> = ["actor", "thing", "fact", "output", "note"]

/// Parse a qualified ID ("fact.likes_tea") into `(type, id)`, validating the
/// type. Returns nil if the string isn't `type.id` with a known type.
func parseQualifiedKnowledgeID(_ raw: String) -> (type: String, id: String)? {
    let parts = raw.split(separator: ".", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    let type = String(parts[0])
    guard knowledgeEntityTypes.contains(type) else { return nil }
    return (type, String(parts[1]))
}

/// Append entity references to a list relation on `entity`, then upsert it.
/// Existing references are preserved; duplicates are skipped. No-op if every
/// target is already linked.
@MainActor
func appendKnowledgeRelation(
    _ relation: String,
    targets: [String],
    on entity: FirmEntity,
    knowledgeService: any KnowledgeService,
    spaceID: UUID?,
    agentID: UUID?,
    chatID: UUID?
) async throws {
    var fields = entity.fields
    var existing: [FirmFieldValue] = []
    if let field = fields.first(where: { $0.name == relation }),
       case .list(let items) = field.value
    {
        existing = items
    }
    let existingIDs = Set(existing.compactMap { value -> String? in
        if case .entityReference(let id) = value { id } else { nil }
    })
    let newRefs = targets
        .filter { !existingIDs.contains($0) }
        .map { FirmFieldValue.entityReference(entityId: $0) }
    guard !newRefs.isEmpty else { return }

    fields.removeAll { $0.name == relation }
    fields.append(FirmField(name: relation, value: .list(items: existing + newRefs)))
    let updated = FirmEntity(id: entity.id, entityType: entity.entityType, fields: fields)
    try await knowledgeService.addEntity(
        updated, spaceID: spaceID, agentID: agentID, chatID: chatID
    )
}

/// Parse a created_at date from an entity's fields for sorting purposes.
private func dateFromEntity(_ entity: FirmEntity) -> Date {
    if let field = entity.fields.first(where: { $0.name == "created_at" }),
       case .dateTime(let v) = field.value
    {
        return LocalDateFormatter.parse(v) ?? .distantPast
    }
    return .distantPast
}

/// Format a summary of an entity for search results (truncated primary field).
func knowledgeSummary(for entity: FirmEntity, maxLength: Int = 80) -> String {
    let primaryField: String? = switch entity.entityType {
    case "actor": stringFieldValue(entity, "name")
    case "thing": stringFieldValue(entity, "name")
    case "fact": stringFieldValue(entity, "claim") ?? stringFieldValue(entity, "name")
    case "output": stringFieldValue(entity, "name")
    case "note": stringFieldValue(entity, "content")
    default: nil
    }

    let text = primaryField ?? entity.id
    if text.count > maxLength {
        return String(text.prefix(maxLength - 1)) + "…"
    }
    return text
}

private func stringFieldValue(_ entity: FirmEntity, _ name: String) -> String? {
    guard let field = entity.fields.first(where: { $0.name == name }) else { return nil }
    if case .string(let v) = field.value { return v }
    return nil
}

/// Minimum similarity score for link suggestions. Entities below this
/// threshold are too weakly related to suggest as link targets.
private let linkSuggestionMinScore: Double = 0.3

/// Suggest entities the agent might want to link a newly added entry to.
///
/// Always includes existing actors (user, agent, etc.) so they're visible as link
/// targets. Then adds semantically similar entities from the rest of the graph,
/// up to `limit` total. Excludes the entity itself.
func linkSuggestions(
    for entity: FirmEntity,
    knowledgeService: any KnowledgeService,
    spaceID: UUID?,
    agentID: UUID?,
    limit: Int = 5
) async -> [[String: Any]] {
    var suggestions: [[String: Any]] = []
    var seen = Set<String>()

    // Always include existing actors (user, agent, etc.).
    if let actorIDs = try? await knowledgeService.listEntities(
        type: "actor", spaceID: spaceID, agentID: agentID
    ) {
        for actorID in actorIDs {
            let qualifiedID = "actor.\(actorID)"
            guard qualifiedID != entity.id else { continue }
            guard let actor = try? await knowledgeService.getEntity(
                type: "actor", id: actorID, spaceID: spaceID, agentID: agentID
            ) else { continue }
            suggestions.append([
                "id": actor.id,
                "summary": knowledgeSummary(for: actor),
            ])
            seen.insert(qualifiedID)
        }
    }

    // Fill remaining slots with semantically similar entities.
    let remaining = limit - suggestions.count
    guard remaining > 0 else { return suggestions }

    let text = KnowledgeEmbedding.embeddingText(for: entity)
    guard let queryEmbedding = EmbeddingHelpers.embed(text) else { return suggestions }

    let scored: [KnowledgeSearchEngine.ScoredEntity]
    do {
        scored = try await KnowledgeSearchEngine.score(
            queryEmbedding: queryEmbedding,
            keywordNeedle: nil,
            includeExpired: true,
            knowledgeService: knowledgeService,
            spaceID: spaceID,
            agentID: agentID
        )
    } catch {
        return suggestions
    }

    let filtered = scored
        .filter {
            $0.score > linkSuggestionMinScore && $0.qualifiedID != entity.id && !seen
                .contains($0.qualifiedID)
        }
        .sorted { $0.score > $1.score }

    for item in filtered.prefix(remaining) {
        suggestions.append([
            "id": item.entity.id,
            "summary": knowledgeSummary(for: item.entity),
        ])
    }

    return suggestions
}

func formatKnowledgeFieldValue(_ value: FirmFieldValue) -> Any {
    switch value {
    case .string(let v): return v
    case .integer(let v): return v
    case .float(let v): return v
    case .boolean(let v): return v
    case .enum(let v): return v
    case .entityReference(let id): return id
    case .fieldReference(let entityId, let fieldId): return "\(entityId).\(fieldId)"
    case .currency(let amount, let code): return "\(amount) \(code)"
    case .dateTime(let v):
        if let date = LocalDateFormatter.parse(v) {
            return LocalDateFormatter.string(from: date)
        }
        return v
    case .path(let v): return v
    case .list(let items): return items.map { formatKnowledgeFieldValue($0) }
    }
}
