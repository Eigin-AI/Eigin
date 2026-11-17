import Factory
import Foundation
import SwiftData

/// Host turn orchestration shared by chat, live calls, and watch turns.
///
/// Gathers prompts, hints, and tools, delegates message preparation to the SDK,
/// and coordinates token estimation and compaction.
enum MessagePipeline {
    /// Compaction tuning for capable models (the summarisation path).
    enum Compaction {
        /// Context windows at or above this size use ``largeWindowThreshold``.
        static let largeWindowLimit: Int = 500_000

        /// Trigger for windows at or above ``largeWindowLimit``.
        static let largeWindowThreshold: Double = 0.25

        /// Trigger for windows below ``largeWindowLimit``. At 25%, a 300k
        /// model would compact after only 75k tokens; 50% keeps 150k of
        /// conversation before summarising.
        static let smallWindowThreshold: Double = 0.5

        /// Context usage ratio at which summarisation triggers. Large windows
        /// trigger earlier (in fraction terms): they have enough headroom, and
        /// long contexts cost more and rot attention earlier.
        static func threshold(for contextWindow: Int) -> Double {
            contextWindow >= largeWindowLimit ? largeWindowThreshold : smallWindowThreshold
        }

        /// Fraction of the context window kept verbatim after a summary, so
        /// what just happened survives compaction at full fidelity. Scales
        /// with the window: a 128k model retains ~6.4k tokens, a 32k model
        /// ~1.6k.
        static let retainedFraction: Double = 0.05

        /// Minimum recent turns (user message + everything after it) kept
        /// verbatim, even when they exceed ``retainedFraction``.
        static let minimumRetainedTurns = 2
    }

    /// Compaction tuning for small-context on-device models. They can't afford
    /// a summarisation call; the oldest messages are dropped instead, with
    /// hysteresis so the kept prefix — and the on-device KV cache — stays
    /// stable between trims.
    enum SmallContext {
        /// Context windows at or below this size use the sliding window.
        static let windowLimit: Int = 16000

        /// When kept history exceeds the budget, it is trimmed back to this
        /// fraction of it in one step, so the boundary only moves occasionally
        /// instead of every turn.
        static let slidingWindowLowWaterFraction: Double = 0.5

        /// Fraction of the window usable as input budget. The character-based
        /// token estimator can undercount up to 2x for multilingual
        /// SentencePiece models (e.g. Gemma/Danish), so truncate well before
        /// the real limit to leave the engine headroom.
        static let inputSafetyFactor: Double = 0.75
    }

    struct TurnInputs {
        let apiMessages: [ChatMessage]
        /// Original history order used to retain stored rows through compaction.
        let historyMessageIDs: [String]
        let registry: ToolRegistry
        let skillSession: SkillSession
        let estimatedTokens: Int
        let contextWindow: Int
        let isSmallContext: Bool
    }

    // MARK: - Turn Preparation

    /// Prepares the inputs for a single chat turn.
    @MainActor
    static func prepareTurn(
        messages: [ChatMessage],
        agent: Agent,
        // The model the turn will run on, which is the agent's own unless the router
        // routed elsewhere. Sizes the prompt budget and picks the tool registry.
        model: String? = nil,
        space: Space?,
        permissionPolicy: AgentPermissionPolicy,
        spaceID: UUID?,
        chatID: UUID? = nil,
        integrations: [Integration] = [],
        activeSkills: [Skill] = [],
        activeFlow: FlowState? = nil,
        gatekeeper: Gatekeeper,
        mode: InteractionMode,
        hasSpaces: Bool,
        onBrowse: BrowseHandler? = nil,
        onPresentOptions: OptionsHandler? = nil,
        onConnectCapability: ConnectCapabilityHandler? = nil,
        skillConnectionGate: SkillConnectionGate? = nil,
        userMessageID: String? = nil
    ) async throws -> TurnInputs {
        if let chatID {
            try InitiativeConversationService.validateTurn(
                chatID: chatID,
                messages: messages,
                context: ModelContext(Container.shared.modelContainer())
            )
        }
        let turnModel = model ?? agent.model
        let contextWindow = KnownModelCatalog.lookup(turnModel)?.contextWindow ?? 128_000
        let isSmallContextModel = contextWindow <= SmallContext.windowLimit
        let integrationManager = Container.shared.integrationManager()

        // 2. Compute space access policy and fetch provider
        let accessPolicy: SpaceAccessPolicy
        var providerSnapshot: ProviderSnapshot?
        if let context = agent.modelContext {
            let publicSpaces = (try? context.fetch(FetchDescriptor<Space>(
                predicate: #Predicate { $0.isPrivate == false }
            ))) ?? []
            let publicSpaceIDs = Set(publicSpaces.map(\.id))
            accessPolicy = SpaceAccessPolicy(
                currentSpaceID: spaceID,
                publicSpaceIDs: publicSpaceIDs
            )

            // Fetch provider for GeneralInfoSource
            let targetProviderID = agent.providerID
            if let provider = try? context.fetch(FetchDescriptor<Provider>(
                predicate: #Predicate { $0.id == targetProviderID }
            )).first {
                providerSnapshot = ProviderSnapshot(name: provider.name, baseURL: provider.baseURL)
            }
        } else {
            accessPolicy = SpaceAccessPolicy(currentSpaceID: spaceID, publicSpaceIDs: [])
        }

        let skillSession = SkillSession(
            chatID: chatID, permissionPolicy: permissionPolicy, accessPolicy: accessPolicy,
            agentID: agent.id,
            connectionRequest: SkillConnectionRequest(
                chatID: chatID, onConnectCapability: onConnectCapability,
                capabilityDeclines: DeclinedCapabilities(), connectionGate: skillConnectionGate,
                userMessageID: userMessageID
            ),
            isSmallContext: isSmallContextModel
        )
        await skillSession.prepareActiveSkills(agent: agent, initialSkills: activeSkills)
        let mcpSkills = skillSession.mcpSkills(context: agent.modelContext)

        // Fallback if provider not found (shouldn't happen in practice)
        let provider = providerSnapshot ?? ProviderSnapshot(name: "Unknown", baseURL: "")

        // 3. Prime the knowledge service with the access policy so public space knowledge is
        // visible
        let knowledgeService = Container.shared.knowledgeService()
        try? await knowledgeService.rebuild(
            spaceID: spaceID,
            agentID: agent.id,
            accessPolicy: accessPolicy
        )

        // 4. Fetch active intents
        let intentService = Container.shared.intentService()
        let activeIntents = await (try? intentService.activeIntents(
            agentID: agent.id,
            limit: 5,
            accessPolicy: accessPolicy
        )) ?? []

        // 5. Build voice name list (context tier already determined above)
        let isSmallContext = isSmallContextModel

        let voiceService = Container.shared.voiceService()
        let languageManager = Container.shared.languageManager()
        let language = languageManager.currentLanguage
        let (recommended, other) = voiceService.voices(for: language)
        let voiceNames = (recommended + other).map(\.name)

        // Combine always-active skills with any additionally activated skills
        let allActiveSkills = BundledSkill.alwaysActive + skillSession.activeSkills
            .filter { !$0.alwaysActive }

        // 6. Build tool registry
        let builtRegistry = if isSmallContext {
            ToolRegistry.smallChat(
                spaceID: spaceID,
                chatID: chatID,
                agentID: agent.id,
                permissionPolicy: permissionPolicy,
                activeSkill: activeSkills.last.flatMap { BundledSkill.skill(forID: $0.id) },
                onBrowse: onBrowse
            )
        } else {
            ToolRegistry.chat(
                voiceNames: voiceNames,
                accessPolicy: accessPolicy,
                spaceID: spaceID, chatID: chatID,
                agentID: agent.id,
                permissionPolicy: permissionPolicy,
                activeSkills: allActiveSkills,
                skillSession: skillSession,
                mcpSkills: mcpSkills,
                onBrowse: onBrowse,
                onPresentOptions: onPresentOptions,
                onConnectCapability: onConnectCapability,
                skillConnectionGate: skillConnectionGate,
                userMessageID: userMessageID
            )
        }

        let registry = builtRegistry

        // Select history before gathering hints from the active conversation.
        let selected = try MessagePreparationSDKConversion.select(messages)
        let conversationMessages = MessagePreparationSDKConversion.conversation(
            selected,
            history: messages
        )

        // 8. Ask the Gatekeeper for the per-turn hint block
        let hintInput = SystemHintInput(
            agentID: agent.id,
            bootstrapComplete: agent.bootstrapComplete,
            hasSpaces: hasSpaces,
            messages: conversationMessages,
            space: space
                .map { SpaceSnapshot(
                    id: $0.id,
                    name: $0.name,
                    emoji: $0.emoji,
                    instructions: $0.instructions
                ) },
            spaceID: spaceID,
            language: languageManager.currentLanguage,
            mode: mode,
            vocabulary: mode == .text
                ? []
                : Container.shared.vocabularyStore().entries(agentName: agent.name),
            activeIntents: activeIntents,
            activeSkills: allActiveSkills,
            availableSkills: BundledSkill.all + mcpSkills,
            connectedCapabilities: integrationManager
                .connectedCapabilities(integrations: integrations),
            declinedCapabilities: DeclinedCapabilities().declined,
            activeFlow: activeFlow,
            unavailableSkillNotes: skillSession.unavailableNotes,
            provider: provider,
            modelID: turnModel,
            isSmallContext: isSmallContext,
            chatID: chatID
        )
        let preprocessing = await gatekeeper.beforeTurn(hintInput)
        let systemHint = preprocessing.hint

        // Prepare request-only messages without resolving attachment bytes.
        let supportsVision = KnownModelCatalog.lookup(turnModel)?.supportsVision ?? false
        let reasoningOrigin = ReasoningOrigin.destination(
            providerID: agent.providerID, baseURL: provider.baseURL, model: turnModel
        )
        let systemPrompt = isSmallContext ? SystemPrompt.buildSmall(for: agent) : SystemPrompt
            .build(for: agent)
        let apiMessages = MessagePreparationSDKConversion.prepare(
            selected, history: messages, systemPrompt: systemPrompt,
            systemHint: systemHint, supportsVision: supportsVision
        )

        // 10. Token estimation
        let estimatedTokens = TokenEstimator.estimateRequest(
            messages: apiMessages.map { $0.reasoningScoped(to: reasoningOrigin) },
            toolDefinitions: registry.definitions
        )

        AppLogger.debug(
            "Pipeline: ~\(public: estimatedTokens)/\(public: contextWindow) tokens, \(public: apiMessages.count) messages",
            category: .chat
        )

        return TurnInputs(
            apiMessages: apiMessages,
            historyMessageIDs: messages.map(\.localID),
            registry: registry,
            skillSession: skillSession,
            estimatedTokens: estimatedTokens,
            contextWindow: contextWindow,
            isSmallContext: isSmallContext
        )
    }

    // MARK: - Compaction

    struct CompactionResult {
        let apiMessages: [ChatMessage]
        let summary: ChatMessage?
        /// Whether the chat's needsCompaction flag should remain set (for retry on next turn).
        let needsCompaction: Bool
    }

    /// Compacts everything except the recent messages when usage warrants it
    /// (see ``Compaction``), resuming from `[system, summary, retained…]`.
    /// Summarisation runs in-conversation (see ``CompactionService``).
    ///
    /// Callers should update their `needsCompaction` flag from the result.
    static func compactIfNeeded(
        apiMessages: [ChatMessage],
        historyMessageIDs: [String]? = nil,
        estimatedTokens: Int,
        contextWindow: Int,
        needsCompaction: Bool = false,
        baseURL: String,
        providerID: UUID,
        model: String,
        chatService: any ChatService,
        tools: [ToolDefinition]? = nil,
        cacheKey: String? = nil,
        onProgress: (@Sendable (CompactionPhase) -> Void)? = nil
    ) async -> CompactionResult {
        let reasoningOrigin = ReasoningOrigin.destination(
            providerID: providerID, baseURL: baseURL, model: model
        )
        let budgetMessages = apiMessages.map { $0.reasoningScoped(to: reasoningOrigin) }
        // Small-context models: use sliding window (drop oldest messages) instead
        // of expensive LLM-based summarisation.
        if contextWindow <= SmallContext.windowLimit {
            // Reserve space for generation output so the KV cache doesn't
            // evict the system prompt during generation.
            let maxOutput = KnownModelCatalog.lookup(model)?.maxOutput ?? 256
            let inputBudget = Int(Double(contextWindow - maxOutput) * SmallContext
                .inputSafetyFactor)
            guard estimatedTokens > inputBudget else {
                return CompactionResult(
                    apiMessages: apiMessages,
                    summary: nil,
                    needsCompaction: false
                )
            }
            let systemPrompt = apiMessages.first!
            let systemTokens = TokenEstimator.estimate(systemPrompt.content ?? "") + 4
            let highMark = max(inputBudget - systemTokens, 0)
            let lowMark = Int(Double(highMark) * SmallContext.slidingWindowLowWaterFraction)
            let conversationMessages = Array(budgetMessages.dropFirst())
            let truncated = CompactionService.windowedForBudget(
                messages: conversationMessages,
                highMark: highMark,
                lowMark: lowMark
            )
            AppLogger.info(
                "Sliding window: kept \(public: truncated.count)/\(public: conversationMessages.count) messages (budget \(public: highMark), low-water \(public: lowMark))",
                category: .chat
            )
            return CompactionResult(
                apiMessages: [systemPrompt] + apiMessages.suffix(truncated.count),
                summary: nil,
                needsCompaction: false
            )
        }

        let threshold = Int(Double(contextWindow) * Compaction.threshold(for: contextWindow))
        let isEmergency = estimatedTokens > contextWindow

        // A previous attempt left the flag stuck on; once a shrinking
        // conversation is well below the threshold, stop retrying.
        if needsCompaction && !isEmergency && estimatedTokens < threshold / 2 {
            return CompactionResult(apiMessages: apiMessages, summary: nil, needsCompaction: false)
        }

        guard isEmergency || estimatedTokens > threshold || needsCompaction else {
            return CompactionResult(apiMessages: apiMessages, summary: nil, needsCompaction: false)
        }

        AppLogger.info(
            "Compaction triggered — tokens: \(public: estimatedTokens)/\(public: contextWindow), emergency: \(public: isEmergency)",
            category: .chat
        )

        // Compact the older history; keep the recent tail verbatim so current
        // work survives compaction at full fidelity.
        let conversationMessages = Array(apiMessages.dropFirst()) // drop system prompt
        guard conversationMessages.count > 1 else {
            return CompactionResult(apiMessages: apiMessages, summary: nil, needsCompaction: false)
        }

        let retainedBudget = Int(Double(contextWindow) * Compaction.retainedFraction)
        let retainedCount = CompactionService.retainedTail(
            messages: Array(budgetMessages.dropFirst()),
            tokenBudget: retainedBudget,
            minimumTurns: Compaction.minimumRetainedTurns
        ).count
        var retained = Array(conversationMessages.suffix(retainedCount))
        // Degenerate conversation with no user turn anywhere — still keep the
        // newest message out of the summary so the payload ends on a model
        // reply the conversation can continue from.
        if retained.isEmpty {
            retained = [conversationMessages.last!]
        }
        let covered = Array(conversationMessages.dropLast(retained.count))

        guard !covered.isEmpty else {
            return CompactionResult(apiMessages: apiMessages, summary: nil, needsCompaction: false)
        }

        AppLogger.info(
            "Compacting \(public: covered.count) messages, retaining \(public: retained.count)",
            category: .chat
        )

        // Same tools and cache key as the turn itself, so the summarise request
        // keeps the turn's provider cache prefix byte-identical.
        let outcome = await CompactionService.compact(
            apiMessages: apiMessages,
            coveredCount: covered.count,
            retainedCount: retained.count,
            contextWindow: contextWindow,
            tools: tools,
            cacheKey: cacheKey,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            chatService: chatService,
            onProgress: onProgress
        )

        if outcome.droppedAllCovered {
            // Minimum-turn retention can itself blow the window-fit budget —
            // warn when the fallback payload still exceeds what fits.
            let fallbackTokens = TokenEstimator.estimateRequest(
                messages: ([apiMessages[0]] + retained)
                    .map { $0.reasoningScoped(to: reasoningOrigin) },
                toolDefinitions: tools ?? []
            )
            if fallbackTokens > contextWindow {
                AppLogger.warning(
                    "Compaction fallback exceeds the window (\(public: fallbackTokens)/\(public: contextWindow))",
                    category: .chat
                )
            }
            return CompactionResult(
                apiMessages: [apiMessages[0]] + retained,
                summary: nil, needsCompaction: false
            )
        }

        guard let summary = outcome.summary else {
            return CompactionResult(apiMessages: apiMessages, summary: nil, needsCompaction: true)
        }

        var summaryMessage = ChatMessage(
            role: "system",
            content: "Summary of earlier conversation:\n\n\(summary)"
        )
        summaryMessage.isCompactionSummary = true
        // Retention counts stored rows, including duplicates removed from the request.
        let historyIDs = historyMessageIDs ?? conversationMessages.map(\.localID)
        let retainedIDs = Set(retained.map(\.localID))
        let boundary = historyIDs.firstIndex(where: retainedIDs.contains) ?? historyIDs.endIndex
        summaryMessage.compactionRetainedMessageCount = historyIDs.distance(
            from: boundary,
            to: historyIDs.endIndex
        )

        AppLogger.info("Summary stored (\(public: summary.count) chars)", category: .chat)

        return CompactionResult(
            apiMessages: [apiMessages[0], summaryMessage] + retained,
            summary: summaryMessage, needsCompaction: false
        )
    }
}
