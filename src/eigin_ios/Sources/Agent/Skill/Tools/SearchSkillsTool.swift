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

    private let skillSession: SkillSession?
    private let chatID: UUID?
    private let skillIndex: any SkillIndexing

    @MainActor
    init(
        chatID: UUID? = nil,
        skillSession: SkillSession? = nil,
        skillIndex: any SkillIndexing = Container.shared.skillIndex()
    ) {
        self.chatID = chatID
        self.skillSession = skillSession
        self.skillIndex = skillIndex
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: skillSession?.toolAccess == .unattended
                ? Prompt.Skills.backgroundSearch
                : """
                Search the skill catalog for skills matching a need. Returns matching \
                skill IDs — activate one with `activate_skill`. A match with `needs` \
                asks the user to connect that integration when activated, so activate \
                it only when their request depends on it.
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

        let connected = connectedCapabilities(agent: agent)
        let matches: [[String: any Sendable]] = skillIndexResult.map { scored in
            var match: [String: any Sendable] = [
                "skill_id": scored.skill.id,
                "name": scored.skill.displayName,
                // Capped: MCP instructions can be long, and this lands in the
                // agent's context every time it searches.
                "description": scored.skill.summaryLine,
            ]
            if let needed = SkillCatalog.connectionNeeded(for: scored.skill, connected: connected) {
                // Offer-framing: see AvailableSkillsSource.line.
                match["connecting"] = skillSession?.toolAccess == .unattended
                    ? Prompt.Skills.backgroundConnectionUnavailable(connections: needed)
                    : "activating this skill asks the user to connect \(needed)"
            }
            return match
        }
        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["matches": matches]),
            isError: false
        )
    }

    /// Activatable candidates: bundled + MCP skills, minus already-active.
    /// Skills that need connecting are included, declined or not: searching
    /// is asking, so the agent can find them and activation answers for them.
    @MainActor private func session(agent: Agent) -> SkillSession {
        skillSession ?? SkillSession(
            chatID: chatID, permissionPolicy: AlwaysAllowPolicy(),
            accessPolicy: SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: []),
            agentID: agent.id
        )
    }

    @MainActor private func activatableSkills(agent: Agent) -> [Skill] {
        guard skillSession != nil || chatID != nil else {
            return SkillCatalog.activatable(
                from: BundledSkill.all, activeIDs: [], connectedCapabilities: []
            )
        }
        return session(agent: agent).candidates(context: agent.modelContext)
    }

    @MainActor private func connectedCapabilities(agent: Agent) -> Set<Capability> {
        session(agent: agent).connectedCapabilities(context: agent.modelContext)
    }
}
