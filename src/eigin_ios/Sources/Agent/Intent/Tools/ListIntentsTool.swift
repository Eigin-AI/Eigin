import Foundation

struct ListIntentsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "list_intents",
        displayName: Localized.Tools.Agent.listIntents,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "list_intents"
    var isSmallContext: Bool = false
    let intentService: any IntentService
    let accessPolicy: SpaceAccessPolicy
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

    init(
        intentService: any IntentService = PreviewIntentService(),
        accessPolicy: SpaceAccessPolicy = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
    ) {
        self.intentService = intentService
        self.accessPolicy = accessPolicy
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "List your intents — goals you've set for yourself. By default returns only active intents sorted by strength.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "limit": .init(
                        type: "integer",
                        description: "Maximum number of intents to return. Default 10."
                    ),
                    "include_resolved": .init(
                        type: "boolean",
                        description: "Include resolved and dismissed intents. Default false."
                    ),
                ]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id
        let args = ToolHelpers.parseArguments(toolCall.function.arguments)
        let limit = (args?["limit"] as? Int) ?? 10
        let includeResolved = (args?["include_resolved"] as? Bool) ?? false

        do {
            let intents: [IntentSnapshot] = if includeResolved {
                try await intentService.allIntents(
                    agentID: agent.id,
                    limit: limit,
                    accessPolicy: accessPolicy
                )
            } else {
                try await intentService.activeIntents(
                    agentID: agent.id,
                    limit: limit,
                    accessPolicy: accessPolicy
                )
            }
            let items: [[String: Any]] = intents.map { intent in
                let daysActive = Int(Date.now.timeIntervalSince(intent.createdAt) / 86400)
                var entry: [String: Any] = [
                    "id": intent.id.uuidString,
                    "content": intent.content,
                    "strength": round(intent.effectiveStrength * 100) / 100,
                    "days_active": daysActive,
                    "reinforced_count": intent.reinforcedCount,
                ]
                if includeResolved {
                    entry["status"] = intent.status.rawValue
                }
                return entry
            }
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["intents": items, "count": items.count]),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
