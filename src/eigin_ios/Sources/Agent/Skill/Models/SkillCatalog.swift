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
}
