import Factory
import Foundation

extension ToolRegistry {
    /// All domain tool kits. Each kit owns its tool construction and capabilities.
    static let allKits: [any ToolKit.Type] = [
        AgentToolKit.self,
        KnowledgeToolKit.self,
        IntentToolKit.self,
        SkillToolKit.self,
        SpaceToolKit.self,
        ChatToolKit.self,
        WebToolKit.self,
        ScheduleToolKit.self,
        FoodToolKit.self,
        SystemToolKit.self,
    ]

    /// All built-in capabilities collected from kits + special-purpose tools.
    static let allKitCapabilities: [ToolCapability] =
        allKits.flatMap { $0.capabilities }
            + [DoneTool.capability, BackgroundNotifyTool.capability]

    /// Full chat tool set from all kits.
    @MainActor
    private static func allChatTools(context: ToolContext) -> [any Tool] {
        allKits.flatMap { $0.tools(context: context) }
    }

    /// Chat tool set filtered by a permission policy and active skills.
    @MainActor
    static func chat(
        voiceNames: [String] = [],
        accessPolicy: SpaceAccessPolicy = SpaceAccessPolicy(
            currentSpaceID: nil,
            publicSpaceIDs: []
        ),
        spaceID: UUID? = nil, chatID: UUID? = nil,
        agentID: UUID? = nil,
        permissionPolicy: ToolPermissionPolicy,
        activeSkills: [Skill] = [],
        additionalTools: [any Tool] = [],
        onCompose: ComposeEmailHandler? = nil,
        onBrowse: BrowseHandler? = nil,
        onPresentOptions: OptionsHandler? = nil
    ) -> ToolRegistry {
        let context = ToolContext(
            voiceNames: voiceNames,
            accessPolicy: accessPolicy,
            spaceID: spaceID, chatID: chatID, agentID: agentID,
            canPromptUser: (permissionPolicy as? AgentPermissionPolicy)?.canPromptUser ?? true,
            onCompose: onCompose,
            onBrowse: onBrowse,
            onPresentOptions: onPresentOptions
        )
        var tools = allChatTools(context: context)
        tools += additionalTools

        // Filter to tools required by active skills (union of all requiredTools).
        // Tools not claimed by any skill (e.g. ActivateSkillTool) pass through automatically.
        let skillRequiredKeys = Set(activeSkills.flatMap { $0.requiredTools.map(\.key) })
        if !skillRequiredKeys.isEmpty {
            let allSkillToolKeys = Set(BundledSkill.all.flatMap { $0.requiredTools.map(\.key) })
            tools = tools.filter { tool in
                skillRequiredKeys.contains(tool.name)
                    || !allSkillToolKeys.contains(tool.name)
                    || additionalTools.contains { $0.name == tool.name }
            }
        }

        // User permissions always win — .never tools are excluded
        let filtered = tools.filter { permissionPolicy.permissionLevel(for: $0.name) != .never }
        return ToolRegistry(tools: filtered)
    }

    /// Tool set for small-context models (≤16K).
    ///
    /// Small-context models cannot use tools, so the registry is empty.
    @MainActor static func smallChat(
        chatID: UUID? = nil,
        agentID: UUID? = nil,
        permissionPolicy: ToolPermissionPolicy,
        activeSkill: Skill? = nil
    ) -> ToolRegistry {
        ToolRegistry(tools: [], isSmallContext: true)
    }

    /// Space bootstrap tool set.
    @MainActor
    static func spaceBootstrap(
        voiceNames: [String] = [],
        spaceID: UUID? = nil, agentID: UUID? = nil,
        onDone: (@Sendable () -> Void)? = nil
    ) -> ToolRegistry {
        let voiceService = Container.shared.voiceService()
        let knowledgeService = Container.shared.knowledgeService()
        let tools: [any Tool] = [
            ReadCoreTool(),
            GetPresentationTool(voiceService: voiceService),
            CreateSpaceTool(),
            DoneTool(onDone: onDone),
            SearchKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: spaceID,
                agentID: agentID
            ),
            GetKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: spaceID,
                agentID: agentID
            ),
        ]
        return ToolRegistry(tools: tools)
    }

    /// Background prompt tool set.
    @MainActor
    static func background(
        accessPolicy: SpaceAccessPolicy = SpaceAccessPolicy(
            currentSpaceID: nil,
            publicSpaceIDs: []
        ),
        permissionPolicy: (any ToolPermissionPolicy)? = nil,
        agentID: UUID? = nil,
        additionalTools: [any Tool] = [],
        onSignal: @escaping @Sendable (BackgroundToolSignal) -> Void
    ) -> ToolRegistry {
        let context = ToolContext(
            accessPolicy: accessPolicy,
            agentID: agentID,
            canPromptUser: false
        )
        var tools = allChatTools(context: context)

        // Background can read intents but not create/resolve them
        let excludedFromBackground: Set<String> = [
            SetIntentTool.capability.key,
            ResolveIntentTool.capability.key,
        ]
        tools.removeAll { excludedFromBackground.contains($0.name) }
        tools += additionalTools

        // Filter to only .always permission tools
        let alwaysTools = tools.filter { tool in
            if let policy = permissionPolicy {
                return policy.permissionLevel(for: tool.name) == .always
            }
            let caps = ToolRegistry.capabilities(for: tool.name)
            return caps.contains { $0.defaultPermissionLevel == .always }
        }

        var result = alwaysTools
        result.append(BackgroundNotifyTool(onSignal: onSignal))
        return ToolRegistry(tools: result)
    }
}
