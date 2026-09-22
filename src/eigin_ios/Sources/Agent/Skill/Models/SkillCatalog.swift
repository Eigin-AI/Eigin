import Foundation

/// Centralized skill lookup across both sources of activatable skills:
/// compile-time bundled skills and runtime-projected MCP server skills.
///
/// Callers that need to resolve a skill ID of unknown origin (e.g.
/// ``ActivateSkillTool``, active-skill resolution) should go through here
/// rather than querying ``BundledSkill`` directly.
enum SkillCatalog {
    /// Resolves a skill by ID, checking bundled skills first, then servers.
    static func skill(forID id: String, mcpServers: [MCPServer]) -> Skill? {
        BundledSkill.skill(forID: id) ?? MCPServerSkill.skill(forID: id, servers: mcpServers)
    }

    /// Resolves a chat's persisted skill entries, dropping skills whose
    /// required capabilities are no longer connected — shared by the text
    /// chat, live call, and watch turn paths.
    static func activeSkills(
        for chat: Chat,
        mcpServers: [MCPServer],
        connectedCapabilities: Set<Capability>
    ) -> [Skill] {
        resolvable(
            from: chat.activeSkillEntries.compactMap {
                skill(forID: $0.skillID, mcpServers: mcpServers)
            },
            connectedCapabilities: connectedCapabilities
        )
    }

    /// Drops resolved skills whose required capabilities are no longer
    /// connected. The active-skill gate shared by the text chat, live call,
    /// and watch turn paths — kept in one place so the three can't drift.
    static func resolvable(
        from skills: [Skill],
        connectedCapabilities: Set<Capability>
    ) -> [Skill] {
        skills.filter { skill in
            skill.requiredCapabilities.isEmpty
                || !skill.requiredCapabilities.isDisjoint(with: connectedCapabilities)
        }
    }

    /// Filters `candidates` down to skills that could be activated right now: on-demand,
    /// not already active, and capability-satisfied.
    static func activatable(
        from candidates: [Skill],
        activeIDs: Set<String>,
        connectedCapabilities: Set<Capability>
    ) -> [Skill] {
        candidates.filter { skill in
            guard !skill.alwaysActive, !activeIDs.contains(skill.id) else { return false }
            guard skill.requiredCapabilities.isEmpty
                || !skill.requiredCapabilities.isDisjoint(with: connectedCapabilities)
            else { return false }
            return true
        }
    }
}
