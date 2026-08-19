import Factory
import Foundation

extension ToolRegistry {
    /// All domain tool kits. Each kit owns its tool construction and capabilities.
    ///
    /// `nonisolated(unsafe)` is safe here: the array is an immutable `let` of
    /// metatypes with no shared mutable state.
    nonisolated(unsafe) static let allKits: [any ToolKit.Type] = [
        AgentToolKit.self,
        KnowledgeToolKit.self,
        IntentToolKit.self,
        SkillToolKit.self,
        SpaceToolKit.self,
        ChatToolKit.self,
        WebToolKit.self,
        ScheduleToolKit.self,
        HealthToolKit.self,
        SystemToolKit.self,
    ]

    /// All built-in capabilities collected from kits + special-purpose tools.
    ///
    /// Integration capabilities (e.g. email) are included statically — derived
    /// from ``BundledIntegrationType/all`` rather than hardcoded per-domain —
    /// so they always show in the permissions UI and resolve correctly for
    /// `AgentPermissionPolicy`, even though the tools themselves only exist in
    /// a turn's tool set when the matching integration is connected. Deduped
    /// by key since two types could one day provide the same capability.
    static let allKitCapabilities: [ToolCapability] =
        allKits.flatMap { $0.capabilities }
            + integrationCapabilities
            + [DoneTool.capability, BackgroundNotifyTool.capability]

    private static var integrationCapabilities: [ToolCapability] {
        var seenKeys = Set<String>()
        return BundledIntegrationType.all.flatMap(\.toolCapabilities)
            .filter { seenKeys.insert($0.key).inserted }
    }

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
        mcpTools: [any Tool] = [],
        mcpSkills: [Skill] = [],
        integrationToolsByCapability: [Capability: [any Tool]] = [:],
        onBrowse: BrowseHandler? = nil,
        onPresentOptions: OptionsHandler? = nil
    ) -> ToolRegistry {
        let context = ToolContext(
            voiceNames: voiceNames,
            accessPolicy: accessPolicy,
            spaceID: spaceID, chatID: chatID, agentID: agentID,
            canPromptUser: (permissionPolicy as? AgentPermissionPolicy)?.canPromptUser ?? true,
            onBrowse: onBrowse,
            onPresentOptions: onPresentOptions
        )
        var tools = allChatTools(context: context)
        tools += mcpTools

        // Filter to tools required by active skills (union of all requiredTools).
        // Tools not claimed by any skill (bundled or MCP-projected — e.g.
        // ActivateSkillTool) pass through automatically. MCP tools are claimed
        // by their server's projected skill, so — like bundled on-demand skill
        // tools — they only enter context once that skill is active.
        let skillRequiredKeys = Set(activeSkills.flatMap { $0.requiredTools.map(\.key) })
        if !skillRequiredKeys.isEmpty {
            let allSkillToolKeys = Set(BundledSkill.all.flatMap { $0.requiredTools.map(\.key) })
                .union(mcpSkills.flatMap { $0.requiredTools.map(\.key) })
            tools = tools.filter { tool in
                skillRequiredKeys.contains(tool.name) || !allSkillToolKeys.contains(tool.name)
            }
        }

        // Integration tools are gated by capability rather than the requiredTools key
        // filter above (an integration's tool set can vary by which provider is
        // selected, so it isn't a fixed key list like a skill's).
        let activeCapabilities = Set(activeSkills.flatMap(\.requiredCapabilities))
        for capability in activeCapabilities {
            tools += integrationToolsByCapability[capability] ?? []
        }

        // User permissions always win — .never tools are excluded
        let filtered = tools.filter { permissionPolicy.permissionLevel(for: $0.name) != .never }
        return ToolRegistry(tools: filtered)
    }

    /// Tool set for small-context models (≤16K, e.g. Gemma 4 E2B).
    ///
    /// Curated tool set for small-context (on-device) models.
    ///
    /// Keeps the declaration footprint small and only includes tools the model
    /// can use reliably with simple string parameters: knowledge search and web
    /// access. Scheduling tools require temporal reasoning the model isn't
    /// reliable at; they'll be revisited when a simplified date API is designed.
    @MainActor static func smallChat(
        chatID: UUID? = nil,
        agentID: UUID? = nil,
        permissionPolicy: ToolPermissionPolicy,
        activeSkill: Skill? = nil,
        onBrowse: BrowseHandler? = nil
    ) -> ToolRegistry {
        let knowledgeService = Container.shared.knowledgeService()
        var searchKnowledge = SearchKnowledgeTool(
            knowledgeService: knowledgeService, spaceID: nil, agentID: agentID
        )
        searchKnowledge.isSmallContext = true
        var webSearch = WebSearchTool()
        webSearch.isSmallContext = true
        var webFetch = WebFetchTool(onBrowse: onBrowse)
        webFetch.isSmallContext = true
        let tools: [any Tool] = [searchKnowledge, webSearch, webFetch]
        let filtered = tools.filter {
            permissionPolicy.permissionLevel(for: $0.name) != .never
        }
        return ToolRegistry(tools: filtered, isSmallContext: true)
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

    /// Onboarding conversation tool set.
    ///
    /// The agent gets to know the user, records what it learns into its core
    /// documents, proposes its own identity, and signals completion. Restricted:
    /// no web, skills, intents, spaces, or scheduling.
    @MainActor
    static func onboarding(
        agentID: UUID,
        onDone: (@Sendable () -> Void)? = nil
    ) -> ToolRegistry {
        let voiceService = Container.shared.voiceService()
        let knowledgeService = Container.shared.knowledgeService()
        let tools: [any Tool] = [
            ReadCoreTool(),
            EditCoreTool(),
            SetPresentationTool(
                voiceService: voiceService,
                voiceNames: [],
                knowledgeService: knowledgeService,
                agentID: agentID
            ),
            SearchKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: nil,
                agentID: agentID
            ),
            GetKnowledgeTool(
                knowledgeService: knowledgeService,
                spaceID: nil,
                agentID: agentID
            ),
            DoneTool(onDone: onDone),
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

        // Background can read intents but not create, edit, or resolve them
        let excludedFromBackground: Set<String> = [
            AddIntentTool.capability.key,
            UpdateIntentTool.capability.key,
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
