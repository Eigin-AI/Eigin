import Foundation

/// Resolves the tools a skill can use from built-ins and active connections.
@MainActor
enum SkillTools {
    static func resolve(
        for skill: Skill,
        integrations: [Integration],
        selections: [CapabilityProviderSelection],
        manager: IntegrationManager
    ) -> [ToolCapability] {
        var tools = skill.requiredTools
        for capability in skill.requiredCapabilities.union(skill.optionalCapabilities) {
            guard let integration = manager.activeIntegration(
                for: capability, integrations: integrations, selections: selections
            ), let type = BundledIntegrationType.type(forID: integration.typeID),
            let category = capability.toolCategory else { continue }
            tools.formUnion(type.toolCapabilities.filter { $0.category == category })
        }
        return tools.sorted {
            if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
            return $0.key < $1.key
        }
    }
}
