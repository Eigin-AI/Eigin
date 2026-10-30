import Factory
import Foundation
import SwiftData

extension SkillSession {
    struct Unavailable: LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    /// Prepares a skill's selected integrations or MCP server under the run's access rules.
    func prepare(
        skill: Skill,
        context: ModelContext
    ) async throws -> (skill: Skill, tools: [any Tool]) {
        if BundledSkill.skill(forID: skill.id) == nil {
            return try await prepareServer(skillID: skill.id, context: context)
        }
        let manager = Container.shared.integrationManager()
        let integrations = (try? context.fetch(FetchDescriptor<Integration>())) ?? []
        let selections = (try? context.fetch(FetchDescriptor<CapabilityProviderSelection>())) ?? []
        var tools: [any Tool] = []
        var errors: [String] = []
        let toolContext = ToolContext(
            accessPolicy: accessPolicy, spaceID: accessPolicy.currentSpaceID,
            chatID: chatID, agentID: agentID,
            canPromptUser: toolAccess == .interactive &&
                ((permissionPolicy as? AgentPermissionPolicy)?.canPromptUser ?? true)
        )
        for capability in skill.requiredCapabilities.union(skill.optionalCapabilities) {
            guard let integration = manager.activeIntegration(
                for: capability, integrations: integrations, selections: selections
            ), let type = BundledIntegrationType.type(forID: integration.typeID) else {
                if skill.requiredCapabilities.contains(capability) {
                    errors.append("Connect \(capability.displayName) in Settings → Connections")
                }
                continue
            }
            if toolAccess == .unattended,
               let error = await manager.authorizationError(for: integration)
            {
                if skill.requiredCapabilities.contains(capability) {
                    errors.append("\(type.displayName): \(error)")
                }
                continue
            }
            tools += type.makeTools(capability, integration, toolContext)
        }
        guard errors.isEmpty else { throw Unavailable(message: errors.joined(separator: "; ")) }
        return (skill, tools)
    }

    private func prepareServer(
        skillID: String,
        context: ModelContext
    ) async throws -> (skill: Skill, tools: [any Tool]) {
        let servers = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        nonisolated(unsafe) let matched = MCPServerSkill.server(
            forSkillID: skillID,
            servers: servers
        )
        guard matched != nil else { throw Unavailable(message: "Unknown skill '\(skillID)'") }
        nonisolated(unsafe) let server = matched!
        let manager = Container.shared.mcpServerManager()
        if let error = await manager.connect(server: server) {
            throw Unavailable(
                message: "Couldn't connect to '\(server.name)': \(error). Reauthorization may be needed in Settings."
            )
        }
        guard let projected = MCPServerSkill.skill(forID: skillID, servers: servers) else {
            throw Unavailable(message: "Unknown skill '\(skillID)'")
        }
        return await (projected, isSmallContext ? [] : manager.toolProxies(serverID: server.id))
    }
}
