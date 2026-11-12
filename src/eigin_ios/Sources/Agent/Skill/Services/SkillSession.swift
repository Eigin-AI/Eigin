import Factory
import Foundation
import SwiftData

/// Discovers, activates, and prepares skills for a chat turn or an unattended run.
@MainActor
final class SkillSession {
    enum ToolAccess {
        case interactive
        case unattended
        /// Unattended context gathering with classified read tools.
        case preparation
    }

    private(set) var activeSkills: [Skill] = []
    private(set) var unavailableNotes: [String] = []
    private var toolsBySkill: [String: [any Tool]] = [:]
    let chatID: UUID?
    let toolAccess: ToolAccess
    let permissionPolicy: any ToolPermissionPolicy
    let accessPolicy: SpaceAccessPolicy
    let agentID: UUID
    let connectionRequest: SkillConnectionRequest?
    let isSmallContext: Bool

    init(
        chatID: UUID? = nil,
        toolAccess: ToolAccess = .interactive,
        permissionPolicy: any ToolPermissionPolicy,
        accessPolicy: SpaceAccessPolicy,
        agentID: UUID,
        connectionRequest: SkillConnectionRequest? = nil,
        isSmallContext: Bool = false
    ) {
        self.chatID = chatID
        self.toolAccess = toolAccess
        self.permissionPolicy = permissionPolicy
        self.accessPolicy = accessPolicy
        self.agentID = agentID
        self.connectionRequest = connectionRequest
        self.isSmallContext = isSmallContext
    }

    /// Current enabled MCP skills, projected without connecting.
    func mcpSkills(context: ModelContext?) -> [Skill] {
        guard !isSmallContext, let context else { return [] }
        return MCPServerSkill.project(servers: servers(context: context))
    }

    /// Catalog candidates excluding skills already active in this session or chat.
    func candidates(context: ModelContext?) -> [Skill] {
        let ids = context.flatMap { chat(context: $0) }.map {
            Set($0.activeSkillEntries.map(\.skillID).filter { id in
                guard let context else { return true }
                return SkillCatalog.skill(forID: id, mcpServers: servers(context: context))?
                    .connectionPresetID == nil
            })
        } ?? Set(activeSkills.map(\.id))
        return SkillCatalog.activatable(
            from: BundledSkill.all + mcpSkills(context: context),
            activeIDs: ids,
            connectedCapabilities: connectedCapabilities(context: context)
        )
    }

    /// Capabilities granted to enabled integration records.
    func connectedCapabilities(context: ModelContext?) -> Set<Capability> {
        guard let context else { return [] }
        return Container.shared.integrationManager().connectedCapabilities(
            integrations: integrations(context: context)
        )
    }

    /// Prepared tools filtered by the current run's permission rule.
    func tools(skills: [Skill]? = nil) -> [any Tool] {
        (skills ?? activeSkills).flatMap { toolsBySkill[$0.id] ?? [] }
            .filter { allows($0.name) }
    }

    /// Refreshes skill projections and tools from current connections and provider selections.
    func prepareActiveSkills(agent: Agent, initialSkills: [Skill] = []) async {
        guard let context = agent.modelContext else { return }
        if let chat = chat(context: context) {
            activeSkills = SkillCatalog.activeSkills(
                for: chat, mcpServers: servers(context: context),
                connectedCapabilities: connectedCapabilities(context: context)
            )
        } else if activeSkills.isEmpty {
            activeSkills = initialSkills
        }
        toolsBySkill = toolsBySkill.filter { key, _ in activeSkills.contains { $0.id == key } }
        unavailableNotes = []
        for (index, skill) in activeSkills.enumerated() {
            if isSmallContext, BundledSkill.skill(forID: skill.id) == nil { continue }
            do {
                let prepared = try await prepare(skill: skill, context: context)
                toolsBySkill[skill.id] = prepared.tools
                activeSkills[index] = prepared.skill
            } catch {
                toolsBySkill.removeValue(forKey: skill.id)
                unavailableNotes
                    .append(
                        "\(skill.displayName) is currently unavailable (\(error.localizedDescription))."
                    )
            }
        }
    }

    /// Activates a skill with shared preparation and optional chat persistence.
    func activate(skillID: String, agent: Agent, toolCallID: String) async -> ToolResult {
        guard let context = agent.modelContext else {
            return failure("No chat context available", toolCallID: toolCallID)
        }
        let targetChat = chat(context: context)
        guard toolAccess != .interactive || targetChat != nil else {
            return failure(
                chatID == nil ? "No chat context available" : "Chat not found",
                toolCallID: toolCallID
            )
        }
        guard let skill = SkillCatalog.skill(forID: skillID, mcpServers: servers(context: context))
        else {
            return failure("Unknown skill '\(skillID)'", toolCallID: toolCallID)
        }
        guard !skill.alwaysActive else {
            return failure("Skill '\(skillID)' is always active", toolCallID: toolCallID)
        }
        if let presetID = skill.connectionPresetID,
           let preset = MCPPreset.all.first(where: { $0.id == presetID })
        {
            guard toolAccess == .interactive else {
                return failure(
                    Prompt.Skills.backgroundConnectionUnavailable(connections: preset.displayName),
                    toolCallID: toolCallID
                )
            }
            targetChat?.activeSkillEntries.removeAll { $0.skillID == skillID }
            activeSkills.removeAll { $0.id == skillID }
            toolsBySkill.removeValue(forKey: skillID)
            let request = connectionRequest ?? SkillConnectionRequest(
                chatID: chatID, onConnectCapability: nil,
                capabilityDeclines: DeclinedCapabilities(), connectionGate: nil, userMessageID: nil
            )
            if let result = await request.connect(
                preset: preset, agent: agent, context: context, toolCallID: toolCallID
            ) { return result }
        }
        let missing = SkillCatalog.missingCapabilities(
            of: skill,
            connected: connectedCapabilities(context: context)
        )
        if !missing.isEmpty, toolAccess == .interactive {
            targetChat?.activeSkillEntries.removeAll { $0.skillID == skillID }
            let request = connectionRequest ?? SkillConnectionRequest(
                chatID: chatID, onConnectCapability: nil,
                capabilityDeclines: DeclinedCapabilities(), connectionGate: nil, userMessageID: nil
            )
            if let result = await request.connect(
                missing, skillID: skillID, agent: agent, context: context, toolCallID: toolCallID
            ) { return result }
        }
        do {
            let prepared = try await prepare(skill: skill, context: context)
            toolsBySkill[skillID] = prepared.tools
            activeSkills.removeAll { $0.id == skillID }
            activeSkills.append(prepared.skill)
            if let targetChat {
                connectionRequest?.connectionGate?.clear(chatID: targetChat.id, skillID: skillID)
                SkillActivation.activate(
                    skillID: skillID,
                    on: targetChat,
                    activatingToolCallID: toolCallID
                )
            }
            return ToolResult(
                toolCallID: toolCallID,
                content: ToolHelpers.output(result: [
                    "activated": skillID,
                    "tools_available": availableToolKeys(skill: prepared.skill),
                    "instruction": prepared.skill.instruction,
                ]), isError: false
            )
        } catch {
            return failure(error.localizedDescription, toolCallID: toolCallID)
        }
    }

    private func allows(_ name: String) -> Bool {
        if toolAccess == .preparation, !PreparationToolPolicy.allows(name) { return false }
        let level = permissionPolicy.permissionLevel(for: name)
        return toolAccess == .interactive ? level != .never : level == .always
    }

    private func availableToolKeys(skill: Skill) -> [String] {
        let contributed = tools(skills: [skill])
        let registry: ToolRegistry = if isSmallContext {
            .smallChat(
                chatID: chatID,
                agentID: agentID,
                permissionPolicy: permissionPolicy,
                activeSkill: skill
            )
        } else if toolAccess != .interactive {
            .background(
                permissionPolicy: permissionPolicy,
                additionalTools: contributed,
                preparationOnly: toolAccess == .preparation,
                onSignal: { _ in }
            )
        } else {
            .chat(
                permissionPolicy: permissionPolicy,
                activeSkills: BundledSkill.alwaysActive + [skill],
                mcpTools: contributed
            )
        }
        let contributedNames = Set(contributed.map(\.name))
        return registry.definitions.map(\.function.name).filter { name in
            contributedNames.contains(name) || !Set(ToolRegistry.capabilities(for: name))
                .isDisjoint(with: skill.requiredTools)
        }.sorted()
    }

    private func chat(context: ModelContext) -> Chat? {
        guard let chatID else { return nil }
        return try? context.fetch(FetchDescriptor<Chat>(predicate: #Predicate { $0.id == chatID }))
            .first
    }

    private func servers(context: ModelContext) -> [MCPServer] {
        (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
    }

    private func integrations(context: ModelContext) -> [Integration] {
        ((try? context.fetch(FetchDescriptor<Integration>())) ?? []).filter(\.isEnabled)
    }

    private func failure(_ message: String, toolCallID: String) -> ToolResult {
        ToolResult(
            toolCallID: toolCallID,
            content: ToolHelpers.output(errors: [message]),
            isError: true
        )
    }
}
