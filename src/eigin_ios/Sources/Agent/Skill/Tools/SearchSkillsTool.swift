import Factory
import Foundation
import SwiftData

/// Agent-initiated catalog search (Layer 2 of skill retrieval): when the
/// hinted skills don't fit, the agent describes what it needs and gets the
/// closest matches from the full activatable catalog (bundled + MCP), ready to
/// pass to `activate_skill`.
struct SearchSkillsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "search_skills",
        displayName: Localized.Tools.Agent.searchSkills,
        description: Localized.Tools.Description.searchSkills,
        defaultPermissionLevel: .always, category: .skills, isUserConfigurable: false
    )

    let name = "search_skills"
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .skills
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    private let chatID: UUID?
    private let skillIndex: any SkillIndexing

    @MainActor
    init(chatID: UUID? = nil, skillIndex: any SkillIndexing = Container.shared.skillIndex()) {
        self.chatID = chatID
        self.skillIndex = skillIndex
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
            Search the skill catalog for skills matching a need. Returns matching \
            skill IDs — activate one with `activate_skill`.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "query": .init(
                        type: "string",
                        description: "What the user needs to do, in your own words."
                    ),
                ],
                required: ["query"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments),
              let query = args["query"] as? String, !query.isEmpty
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'query' parameter"]),
                isError: true
            )
        }

        let skillIndexResult = await skillIndex.search(
            query: query,
            among: activatableSkills(agent: agent),
            threshold: SkillIndex.searchThreshold,
            limit: 5
        )
        guard let skillIndexResult else {
            // Embedder unavailable — search didn't run; don't report a no-match
            // the code never established.
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [
                    "Skill search is unavailable on this device right now.",
                ]),
                isError: false
            )
        }
        guard !skillIndexResult.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["No matching skills found."]),
                isError: false
            )
        }

        let matches: [[String: any Sendable]] = skillIndexResult.map { scored in
            [
                "skill_id": scored.skill.id,
                "name": scored.skill.displayName,
                // Capped: MCP instructions can be long, and this lands in the
                // agent's context every time it searches.
                "description": scored.skill.summaryLine,
            ]
        }
        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["matches": matches]),
            isError: false
        )
    }

    /// Activatable candidates: bundled + MCP skills, minus already-active,
    /// minus skills whose required capabilities aren't connected.
    @MainActor private func activatableSkills(agent: Agent) -> [Skill] {
        guard let chatID, let context = agent.modelContext else {
            return SkillCatalog.activatable(
                from: BundledSkill.all.filter { !$0.alwaysActive },
                activeIDs: [],
                connectedCapabilities: []
            )
        }

        let targetChatID = chatID
        var descriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.id == targetChatID }
        )
        descriptor.fetchLimit = 1
        let chat = (try? context.fetch(descriptor))?.first

        let servers = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        let activeIDs = Set(chat?.activeSkillEntries.map(\.skillID) ?? [])

        return SkillCatalog.activatable(
            from: BundledSkill.all + MCPServerSkill.project(servers: servers),
            activeIDs: activeIDs,
            connectedCapabilities: connectedCapabilities(context: context)
        )
    }

    /// Capabilities provided by at least one connected, enabled integration.
    @MainActor private func connectedCapabilities(context: ModelContext) -> Set<Capability> {
        let integrations = ((try? context.fetch(FetchDescriptor<Integration>())) ?? [])
            .filter(\.isEnabled)
        return Container.shared.integrationManager()
            .connectedCapabilities(integrations: integrations)
    }
}
