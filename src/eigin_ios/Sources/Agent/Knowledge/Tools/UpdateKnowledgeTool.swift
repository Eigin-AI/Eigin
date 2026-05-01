import Foundation

/// Updates fields on an existing knowledge entity.
///
/// Fetches the current entity, merges the provided fields over the existing ones,
/// and saves via ``KnowledgeService/addEntity(_:spaceID:agentID:chatID:)`` (which upserts).
struct UpdateKnowledgeTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "update_knowledge",
        displayName: Localized.Tools.Update.knowledge,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "update_knowledge"
    var isSmallContext: Bool = false
    let knowledgeService: any KnowledgeService
    let spaceID: UUID?
    let agentID: UUID?
    let chatID: UUID?
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .agent
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    func definition() -> ToolDefinition {
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Update a knowledge entry's fields.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "type": .init(
                            type: "string",
                            description: "Knowledge type.",
                            enum: ["actor", "thing", "fact", "output", "note"]
                        ),
                        "id": .init(type: "string", description: "Entry ID."),
                        "fields": .init(type: "object", description: "Fields to update."),
                    ],
                    required: ["type", "id", "fields"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: """
            Update an existing knowledge entry. \
            Only the fields you provide are changed — others are kept as-is. \
            Use get_knowledge to see the current state first.
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
                        description: "Entry ID (the short ID, e.g. \"eigin\" not \"thing.eigin\")."
                    ),
                    "fields": .init(
                        type: "object",
                        description: "Field name-value pairs to update. Use plain strings for text, enum, and reference values. References are strings like \"actor.alice\". Lists are arrays of strings. Set valid_until to expire entries (e.g. \"2026-03-25\" or \"2026-03-25 14:00\")."
                    ),
                    "tags": .init(
                        type: "array",
                        description: "Optional: replaces the entry's tags with this list.",
                        items: .init(type: "string")
                    ),
                ],
                required: ["type", "id", "fields"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let callID = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }
        guard let entityType = args["type"] as? String else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Missing 'type' parameter"]),
                isError: true
            )
        }
        guard var entityID = args["id"] as? String else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Missing 'id' parameter"]),
                isError: true
            )
        }
        // Strip type prefix if the LLM included it.
        if entityID.hasPrefix("\(entityType).") {
            entityID = String(entityID.dropFirst(entityType.count + 1))
        }
        guard let fieldsDict = args["fields"] as? [String: Any] else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: ["Missing 'fields' parameter"]),
                isError: true
            )
        }

        // Fetch the existing entity.
        guard let existing = try? await knowledgeService.getEntity(
            type: entityType,
            id: entityID,
            spaceID: spaceID,
            agentID: agentID
        ) else {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers
                    .output(
                        errors: [
                            "Knowledge entry \(entityType).\(entityID) not found. Use add_knowledge to create new entries.",
                        ]
                    ),
                isError: true
            )
        }

        // Build a map of existing fields.
        var mergedFields: [String: FirmField] = [:]
        for field in existing.fields {
            mergedFields[field.name] = field
        }

        // Merge in the new fields.
        let schema = AddKnowledgeTool.schemaFields[entityType] ?? [:]
        for (key, value) in fieldsDict {
            let fieldType = schema[key]
            guard let fieldValue = convertToFirmFieldValue(value, fieldType: fieldType)
            else { continue }
            mergedFields[key] = FirmField(name: key, value: fieldValue)
        }

        // Handle tags replacement if provided.
        if let tags = args["tags"] as? [String] {
            let tagValues = tags.map { FirmFieldValue.string(value: $0) }
            mergedFields["tags"] = FirmField(name: "tags", value: .list(items: tagValues))
        }

        let updated = FirmEntity(
            id: existing.id,
            entityType: entityType,
            fields: Array(mergedFields.values)
        )

        do {
            try await knowledgeService.addEntity(
                updated,
                spaceID: spaceID,
                agentID: agentID,
                chatID: chatID
            )
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(result: [
                    "id": "\(entityType).\(entityID)",
                    "status": "updated",
                ]),
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
                toolCallID: callID,
                content: ToolHelpers.output(errors: [message]),
                isError: true
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
}
