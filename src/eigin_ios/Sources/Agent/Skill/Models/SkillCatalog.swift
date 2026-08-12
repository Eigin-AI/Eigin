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
