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

    /// Filters `candidates` down to skills the agent could activate: on-demand,
    /// not already active, and either capability-satisfied or connectable,
    /// since activating one that needs connecting asks the person in the chat.
    /// Skills whose capabilities were all `declined` are left out, so a no
    /// isn't raised again unprompted.
    static func activatable(
        from candidates: [Skill],
        activeIDs: Set<String>,
        connectedCapabilities: Set<Capability>,
        declined: Set<Capability> = []
    ) -> [Skill] {
        candidates.filter { skill in
            guard !skill.alwaysActive, !activeIDs.contains(skill.id) else { return false }
            let missing = missingCapabilities(of: skill, connected: connectedCapabilities)
            return missing.isEmpty || !missing.isSubset(of: declined)
        }
    }

    /// The capabilities a skill still needs connecting: every required one
    /// it doesn't have. A skill needs all of them — its instructions describe
    /// tools each capability provides, so it only advertises when complete.
    static func missingCapabilities(
        of skill: Skill,
        connected: Set<Capability>
    ) -> Set<Capability> {
        skill.requiredCapabilities.subtracting(connected)
    }

    /// The integrations that could connect what a skill needs, by name,
    /// e.g. "Apple Health", "Google or Microsoft or Other email" (any one of
    /// a capability's providers is enough), or "Apple Calendar and Apple
    /// Reminders" (a skill needs all of its capabilities). `nil` when the
    /// skill needs nothing connected.
    static func connectionNeeded(for skill: Skill, connected: Set<Capability>) -> String? {
        let missing = missingCapabilities(of: skill, connected: connected)
        guard !missing.isEmpty else { return nil }
        let names = providerNames(for: missing)
        return names.isEmpty ? nil : names
    }

    /// The integrations that could provide any of the capabilities, in
    /// catalogue order.
    static func providers(for missing: Set<Capability>) -> [IntegrationType] {
        BundledIntegrationType.all
            .filter { !$0.providedCapabilities.isDisjoint(with: missing) }
    }

    /// The names of the integrations that could provide the capabilities,
    /// grouped per capability and joined for reading: within a capability
    /// with "or" (any provider is enough), across capabilities with "and"
    /// (a skill needs all of them).
    static func providerNames(for missing: Set<Capability>) -> String {
        let groups = Capability.allCases
            .filter { missing.contains($0) }
            .map { providers(for: [$0]).map(\.displayName).joined(separator: " or ") }
        return ListFormatter.localizedString(byJoining: groups)
    }
}
