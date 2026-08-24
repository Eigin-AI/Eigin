import Foundation

struct SearchKnowledgeTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "search_knowledge",
        displayName: Localized.Tools.Knowledge.search,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "search_knowledge"
    let knowledgeService: any KnowledgeService
    let spaceID: UUID?
    let agentID: UUID?
    var isSmallContext: Bool = false
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
                description: "Search your knowledge base.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "query": .init(type: "string", description: "Search query."),
                    ],
                    required: ["query"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: """
            Search your knowledge base. \
            With a query: returns ranked results scored by semantic similarity and keyword match. \
            Without a query: returns an overview of what you know (counts and recent entries per type). \
            Results are summaries — use get_knowledge to retrieve full details. \
            By default, expired (forgotten or superseded) entries are hidden. \
            Set include_expired to true to search them too.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "query": .init(
                        type: "string",
                        description: "Search query. Omit or leave empty for an overview of all knowledge."
                    ),
                    "type": .init(
                        type: "string",
                        description: "Optional: filter to a specific knowledge type.",
                        enum: ["actor", "thing", "fact", "output", "note"]
                    ),
                    "limit": .init(
                        type: "integer",
                        description: "Maximum number of results to return. Defaults to 10."
                    ),
                    "include_expired": .init(
                        type: "boolean",
                        description: "Include expired (forgotten or superseded) entries. Defaults to false."
                    ),
                ]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let callID = toolCall.id

        let args = ToolHelpers.parseArguments(toolCall.function.arguments)
        let query = (args?["query"] as? String) ?? ""
        let typeFilter = args?["type"] as? String
        let limit = (args?["limit"] as? Int) ?? 10
        let includeExpired = (args?["include_expired"] as? Bool) ?? false

        do {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                return try await overviewResult(callID: callID, typeFilter: typeFilter)
            } else {
                return try await searchResult(
                    callID: callID,
                    query: query,
                    typeFilter: typeFilter,
                    limit: limit,
                    includeExpired: includeExpired
                )
            }
        } catch {
            return ToolResult(
                toolCallID: callID,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }

    // MARK: - Overview (no query)

    private func overviewResult(callID: String, typeFilter: String?) async throws -> ToolResult {
        let schemaNames: [String] = if let typeFilter {
            [typeFilter]
        } else {
            try await knowledgeService.listSchemas(spaceID: spaceID, agentID: agentID)
        }

        // Build a map from source path → updatedAt so we can sort entries by recency.
        let visibleSources = try await knowledgeService.allVisibleSources(
            spaceID: spaceID,
            agentID: agentID
        )
        let updatedAtByPath: [String: Date] = Dictionary(
            visibleSources.map { ($0.path, $0.updatedAt) },
            uniquingKeysWith: { _, second in second }
        )

        let recentCount = 5
        var types: [[String: Any]] = []

        for schemaName in schemaNames.sorted() {
            let entityIDs = try await knowledgeService.listEntities(
                type: schemaName,
                spaceID: spaceID,
                agentID: agentID
            )

            // Sort entity IDs by their source's updatedAt (most recent first).
            let sorted = entityIDs.sorted { a, b in
                let pathA = BundledKnowledge.entityPath(
                    prefix: BundledKnowledge.knowledgePrefix,
                    type: schemaName,
                    id: a
                )
                let pathB = BundledKnowledge.entityPath(
                    prefix: BundledKnowledge.knowledgePrefix,
                    type: schemaName,
                    id: b
                )
                let dateA = updatedAtByPath[pathA] ?? .distantPast
                let dateB = updatedAtByPath[pathB] ?? .distantPast
                return dateA > dateB
            }

            // Get the most recently updated entries for preview.
            var recentSummaries: [[String: Any]] = []
            for entityID in sorted.prefix(recentCount) {
                if let entity = try await knowledgeService.getEntity(
                    type: schemaName,
                    id: entityID,
                    spaceID: spaceID,
                    agentID: agentID
                ) {
                    recentSummaries.append([
                        "id": entity.id,
                        "summary": knowledgeSummary(for: entity),
                    ])
                }
            }

            var typeInfo: [String: Any] = [
                "type": schemaName,
                "count": entityIDs.count,
            ]
            if !recentSummaries.isEmpty {
                typeInfo["recent"] = recentSummaries
            }
            types.append(typeInfo)
        }

        return ToolResult(
            toolCallID: callID,
            content: ToolHelpers.output(result: ["overview": types]),
            isError: false
        )
    }

    // MARK: - Ranked search (with query)

    private func searchResult(
        callID: String,
        query: String,
        typeFilter: String?,
        limit: Int,
        includeExpired: Bool = false
    ) async throws -> ToolResult {
        let scored = try await KnowledgeSearchEngine.search(
            query: query,
            typeFilter: typeFilter,
            includeExpired: includeExpired,
            limit: limit,
            knowledgeService: knowledgeService,
            spaceID: spaceID,
            agentID: agentID
        )

        // Surfacing by search is an indirect use signal for each result shown.
        for result in scored {
            await knowledgeService.recordAccess(
                type: result.entity.entityType,
                id: result.qualifiedID,
                kind: .indirect,
                spaceID: spaceID,
                agentID: agentID
            )
        }

        let entries: [[String: Any]] = scored.map { result in
            var entry: [String: Any] = [
                "id": result.entity.id,
                "type": result.entity.entityType,
                "summary": knowledgeSummary(for: result.entity),
                "score": Double(String(format: "%.4f", result.score))!,
            ]
            if let chatID = result.chatID {
                entry["has_context"] = true
                entry["chat_id"] = chatID.uuidString
            }
            return entry
        }

        return ToolResult(
            toolCallID: callID,
            content: ToolHelpers.output(result: ["results": entries, "count": entries.count]),
            isError: false
        )
    }
}
