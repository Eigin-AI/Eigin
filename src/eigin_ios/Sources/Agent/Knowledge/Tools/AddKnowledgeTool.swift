import Foundation

struct AddKnowledgeTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "add_knowledge",
        displayName: Localized.Tools.Add.knowledge,
        defaultPermissionLevel: .always, category: .knowledge
    )

    let name = "add_knowledge"
    let knowledgeService: any KnowledgeService
    let spaceID: UUID?
    let agentID: UUID?
    let chatID: UUID?
    var isSmallContext: Bool = false
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .knowledge
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    func definition() -> ToolDefinition {
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Add knowledge. Types: actor, thing, fact, output, note.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "type": .init(
                            type: "string",
                            description: "Knowledge type.",
                            enum: ["actor", "thing", "fact", "output", "note"]
                        ),
                        "id": .init(type: "string", description: "Entry ID (snake_case)."),
                        "data": .init(type: "object", description: "Data name-value pairs."),
                    ],
                    required: ["type", "id", "data"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: """
            Add a new entry to your knowledge base. \
            Types: actor (people, organisations, AI agents), thing (objects, places, software, concepts), \
            fact (structured truths with a source), output (documents and artefacts), \
            note (lightweight highlights — only requires content). \
            If you get a schema error, the error message shows the expected fields.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "type": .init(
                        type: "string",
                        description: "Knowledge type.",
                        enum: ["actor", "thing", "fact", "output", "note"]
                    ),
                    "id": .init(
                        type: "string",
                        description: "Entry ID (snake_case). Must be unique within its type."
                    ),
                    "data": .init(
                        type: "object",
                        description: """
                        Field name-value pairs. \
                        Use plain strings for text, enum, and reference values. \
                        References are strings like "actor.alice" or "thing.eigin". \
                        Lists are arrays of strings. \
                        For notes, only "content" is required.
                        """
                    ),
                    "tags": .init(
                        type: "array",
                        description:
                        "Optional tags for searchability (e.g. [\"work\", \"preference\"]).",
                        items: .init(type: "string")
                    ),
                    "importance": .init(
                        type: "number",
                        description: """
                        Optional 0–1 importance (default 0.5). Raise above 0.5 for \
                        rare-but-critical facts (e.g. an allergy) so they surface \
                        even when seldom used; lower for low-stakes trivia.
                        """
                    ),
                ],
                required: ["type", "id", "data"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let callID = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: callID, content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }
        guard let entityType = args["type"] as? String else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Missing 'type' parameter"]), isError: true
            )
        }
        guard var entityID = args["id"] as? String else {
            return ToolResult(
                toolCallID: callID, content: ToolHelpers.output(errors: ["Missing 'id' parameter"]),
                isError: true
            )
        }
        // Strip type prefix if the LLM included it (e.g. "actor.daniel" → "daniel").
        if entityID.hasPrefix("\(entityType).") {
            entityID = String(entityID.dropFirst(entityType.count + 1))
        }
        if args["data"] == nil {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(
                    errors: [
                        "Missing 'data' parameter. You must provide a 'data' object containing the entry's properties. Received: \(toolCall.function.arguments)",
                    ]
                ),
                isError: true
            )
        }
        guard let dataDict = args["data"] as? [String: Any] else {
            let actual = args["data"] ?? "nil"
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(
                    errors: [
                        "'data' must be an object, not \(type(of: actual)). Received: \(toolCall.function.arguments)",
                    ]
                ),
                isError: true
            )
        }

        // Check for duplicate entity.
        if await (try? knowledgeService.getEntity(
            type: entityType, id: entityID, spaceID: spaceID, agentID: agentID
        )) != nil {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: [
                    "A \(entityType) with ID '\(entityID)' already exists. Use update_knowledge to modify it.",
                ]), isError: true
            )
        }

        let schema = Self.schemaFields[entityType] ?? [:]
        var fields = dataDict.compactMap { key, value -> FirmField? in
            let fieldType = schema[key]
            guard let fieldValue = convertToFirmFieldValue(value, fieldType: fieldType) else {
                return nil
            }
            return FirmField(name: key, value: fieldValue)
        }

        // Auto-add tags if provided.
        if let tags = args["tags"] as? [String], !tags.isEmpty {
            let tagValues = tags.map { FirmFieldValue.string(value: $0) }
            fields.append(FirmField(name: "tags", value: .list(items: tagValues)))
        }

        // Auto-add created_at timestamp.
        let now = LocalDateFormatter.iso8601String(from: Date())
        fields.append(FirmField(name: "created_at", value: .dateTime(value: now)))

        // Auto-link if no relationships provided.
        let relationshipFields: Set = [
            "relates_to",
            "belongs_to",
            "uses",
            "describes",
            "supersedes",
        ]
        let hasRelationships = fields.contains { relationshipFields.contains($0.name) }

        var autoLinkedIDs: [String] = []
        if !hasRelationships {
            let entity = FirmEntity(
                id: "\(entityType).\(entityID)", entityType: entityType, fields: fields
            )
            autoLinkedIDs = await KnowledgeAutoLinker.autoLinks(
                for: entity, knowledgeService: knowledgeService,
                spaceID: spaceID, agentID: agentID
            )
            if !autoLinkedIDs.isEmpty {
                let refs = autoLinkedIDs.map { FirmFieldValue.entityReference(entityId: $0) }
                fields.append(FirmField(name: "relates_to", value: .list(items: refs)))
            }
        }

        let entity = FirmEntity(
            id: "\(entityType).\(entityID)",
            entityType: entityType,
            fields: fields
        )

        do {
            try await knowledgeService.addEntity(
                entity, spaceID: spaceID, agentID: agentID, chatID: chatID
            )

            var result: [String: Any] = [
                "id": "\(entityType).\(entityID)", "status": "created",
            ]

            if let importance = (args["importance"] as? NSNumber)?.doubleValue {
                try? await knowledgeService.setImportance(
                    type: entityType, id: entityID, importance: importance,
                    spaceID: spaceID, agentID: agentID
                )
                result["importance"] = importance
            }

            if !autoLinkedIDs.isEmpty {
                result["auto_linked"] = autoLinkedIDs
            }

            // Gentle, non-blocking nudge if this looks like a duplicate or
            // contradiction of something already known.
            let similar = await KnowledgeConflictHint.similarExisting(
                to: entity, knowledgeService: knowledgeService,
                spaceID: spaceID, agentID: agentID
            )
            if !similar.isEmpty {
                result["similar_existing"] = similar
                result["reconcile_hint"] = KnowledgeConflictHint.message
            }

            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(result: result),
                isError: false
            )
        } catch {
            let schema = try? await knowledgeService.getSchema(
                entityType: entityType, spaceID: spaceID, agentID: agentID
            )
            let message = KnowledgeValidation.formatError(
                error,
                entityType: entityType,
                schema: schema
            )
            return ToolResult(
                toolCallID: callID, content: ToolHelpers.output(errors: [message]), isError: true
            )
        }
    }

    // MARK: - Value conversion

    private func convertToFirmFieldValue(_ value: Any, fieldType: String?) -> FirmFieldValue? {
        if let arr = value as? [Any] {
            let items = arr.compactMap { convertListItem($0) }
            return .list(items: items)
        }
        if let s = value as? String {
            let sanitized = s.replacingOccurrences(of: "\"", with: "'")
            switch fieldType {
            case "enum": return .enum(value: sanitized)
            case "datetime":
                if let date = LocalDateFormatter.parse(s) {
                    return .dateTime(value: LocalDateFormatter.iso8601String(from: date))
                }
                return .dateTime(value: s)
            default: return .string(value: sanitized)
            }
        }
        if let n = value as? Int { return .integer(value: Int64(n)) }
        if let n = value as? Double { return .float(value: n) }
        if let b = value as? Bool { return .boolean(value: b) }
        return nil
    }

    private func convertListItem(_ value: Any) -> FirmFieldValue? {
        if let s = value as? String {
            if s.contains("."), !s.contains(" ") {
                return .entityReference(entityId: s)
            }
            return .string(value: s.replacingOccurrences(of: "\"", with: "'"))
        }
        if let n = value as? Int { return .integer(value: Int64(n)) }
        if let n = value as? Double { return .float(value: n) }
        if let b = value as? Bool { return .boolean(value: b) }
        return nil
    }

    // MARK: - Schema field types

    /// Maps entity type → field name → field type (from BundledKnowledge schemas).
    static let schemaFields: [String: [String: String]] = {
        let sharedRelations: [String: String] = [
            "tags": "list",
            "created_at": "datetime",
            "relates_to": "list",
            "belongs_to": "list",
            "uses": "list",
            "describes": "list",
            "supersedes": "list",
        ]
        return [
            "actor": sharedRelations.merging(["name": "string", "type": "enum"]) { _, new in new },
            "thing": sharedRelations.merging(["name": "string", "category": "enum"]) { _, new in new
            },
            "fact": sharedRelations.merging([
                "name": "string", "claim": "string", "source": "enum", "last_verified": "datetime",
            ]) { _, new in new },
            "output": sharedRelations.merging([
                "name": "string", "content": "string", "authors": "list",
            ]) { _, new in new },
            "note": sharedRelations.merging(["content": "string"]) { _, new in new },
        ]
    }()
}
