import Factory
import Foundation
import SwiftData

/// Shared turn-preparation and post-turn logic used by both chat and live calls.
///
/// Consolidates MCP tool discovery, tool registry construction, system prompt
/// building, ``Gatekeeper`` hydration, API message assembly, token estimation,
/// and compaction into a single pipeline so chat and live calls stay in sync.
enum MessagePipeline {
    /// Compaction tuning for capable models (the summarisation path).
    enum Compaction {
        /// Context usage ratio at which summarisation triggers. Deliberately
        /// aggressive: long contexts cost more and rot attention earlier.
        static let threshold: Double = 0.25

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

    /// Synthetic assistant acknowledgement inserted after a compaction summary
    /// so the outgoing conversation starts with a valid user→assistant turn.
    private static let compactionAck = "Understood — continuing from there."

    struct TurnInputs {
        let apiMessages: [ChatMessage]
        let registry: ToolRegistry
        /// Tool-call intents from the Gatekeeper (today: skill activations), run
        /// by the agent loop as a synthetic pre-round before the first model stream.
        let initialToolCalls: [ToolCall]
        let mcpTools: [any Tool]
        /// Every enabled MCP server projected into a ``Skill`` (catalog
        /// entries), not just active ones — reused when rebuilding the
        /// registry mid-turn so newly activated servers gate correctly.
        let mcpSkills: [Skill]
        /// Connected integrations' tools grouped by capability, for reuse when
        /// rebuilding the registry mid-turn (e.g. on skill activation).
        let integrationToolsByCapability: [Capability: [any Tool]]
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
        mcpServers: [MCPServer],
        integrations: [Integration] = [],
        activeSkills: [Skill] = [],
        activeFlow: FlowState? = nil,
        gatekeeper: Gatekeeper,
        mode: InteractionMode,
        hasSpaces: Bool,
        needsCompaction: Bool,
        onBrowse: BrowseHandler? = nil,
        onPresentOptions: OptionsHandler? = nil
    ) async -> TurnInputs {
        // 1. Cache-driven MCP catalog: `mcpSkills` is a projection of persisted
        // server data, no connection needed. Only servers backing an active
        // skill get connected (see ``ActivateSkillTool``) and have tools
        // injected. Skipped for small-context models, which never get MCP tools.
        let turnModel = model ?? agent.model
        let contextWindow = KnownModelCatalog.lookup(turnModel)?.contextWindow ?? 128_000
        let isSmallContextModel = contextWindow <= SmallContext.windowLimit
        let mcpServerManager = Container.shared.mcpServerManager()
        nonisolated(unsafe) let servers = mcpServers
        let mcpSkills = isSmallContextModel ? [] : MCPServerSkill.project(servers: servers)
        let activeMCPSkillIDs = Set(activeSkills.map(\.id)).intersection(mcpSkills.map(\.id))
        nonisolated(unsafe) let activeMCPServers = activeMCPSkillIDs.compactMap {
            MCPServerSkill.server(forSkillID: $0, servers: servers)
        }
        let mcpTools = isSmallContextModel
            ? []
            : await mcpServerManager.prepareTools(servers: activeMCPServers)

        // An active MCP skill whose server failed to connect this turn keeps
        // its instructions rendered (see below) but surfaces a note so the
        // agent can tell the user, rather than losing its tools silently.
        let unavailableMCPNotes: [String] = activeMCPServers.compactMap { server in
            guard let error = mcpServerManager.connectionErrors[server.id] else { return nil }
            return "\(server.name) is currently unavailable (\(error)). The user may need to reauthorize it in Settings → MCP Servers."
        }

        // 1b. Build integration tools, grouped by capability, gated in ToolAssembly
        // behind active skills (unlike MCP tools, which are always injected above).
        let integrationManager = Container.shared.integrationManager()
        let capabilitySelections: [CapabilityProviderSelection] = {
            guard let context = agent.modelContext else { return [] }
            return (try? context.fetch(FetchDescriptor<CapabilityProviderSelection>())) ?? []
        }()
        let integrationToolsByCapability = integrationManager.toolsByCapability(
            integrations: integrations,
            selections: capabilitySelections,
            context: ToolContext(spaceID: spaceID, chatID: chatID, agentID: agent.id)
        )

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
        let allActiveSkills = BundledSkill.alwaysActive + activeSkills.filter { !$0.alwaysActive }

        // 6. Build tool registry
        let builtRegistry = if isSmallContext {
            ToolRegistry.smallChat(
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
                mcpTools: mcpTools,
                mcpSkills: mcpSkills,
                integrationToolsByCapability: integrationToolsByCapability,
                onBrowse: onBrowse,
                onPresentOptions: onPresentOptions
            )
        }

        let registry = builtRegistry

        // 7. Extract the compaction summary (if any) and the conversation slice
        //    around it — see ``splitAtLatestSummary``. The summary is rendered as
        //    a synthetic user+assistant pair inside ``buildAPIMessages``; the hint
        //    block is appended to the last *real* user message, not the synthetic
        //    one.
        let (compactionSummary, conversationMessages) = splitAtLatestSummary(messages)

        // 8. Ask the Gatekeeper for the per-turn hint block
        let hintInput = SystemHintInput(
            agentID: agent.id,
            bootstrapComplete: agent.bootstrapComplete,
            needsCompaction: needsCompaction,
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
            activeIntents: activeIntents,
            activeSkills: allActiveSkills,
            availableSkills: BundledSkill.all + mcpSkills,
            connectedCapabilities: integrationManager
                .connectedCapabilities(integrations: integrations),
            activeFlow: activeFlow,
            unavailableSkillNotes: unavailableMCPNotes,
            provider: provider,
            modelID: turnModel,
            isSmallContext: isSmallContext
        )
        let preprocessing = await gatekeeper.beforeTurn(hintInput)
        let systemHint = preprocessing.hint

        // 9. Build API messages
        // Apply image stripping before assembly: keep only the most recent
        // `maxLiveImageTurns` image-bearing user turns; strip all images
        // unconditionally when the model does not support vision.
        let supportsVision = KnownModelCatalog.lookup(turnModel)?.supportsVision ?? false
        let strippedConversation = applyImageStripping(
            conversationMessages,
            supportsVision: supportsVision
        )

        let apiMessages: [ChatMessage] = if isSmallContext {
            buildSmallAPIMessages(
                agent: agent,
                conversationMessages: strippedConversation,
                compactionSummary: compactionSummary,
                systemHint: systemHint
            )
        } else {
            buildAPIMessages(
                agent: agent,
                conversationMessages: strippedConversation,
                compactionSummary: compactionSummary,
                systemHint: systemHint
            )
        }

        // 10. Token estimation
        let estimatedTokens = TokenEstimator.estimateRequest(
            messages: apiMessages,
            toolDefinitions: registry.definitions
        )

        AppLogger.debug(
            "Pipeline: ~\(public: estimatedTokens)/\(public: contextWindow) tokens, \(public: apiMessages.count) messages",
            category: .chat
        )

        return TurnInputs(
            apiMessages: apiMessages,
            registry: registry,
            initialToolCalls: preprocessing.toolCallIntents,
            mcpTools: mcpTools,
            mcpSkills: mcpSkills,
            integrationToolsByCapability: integrationToolsByCapability,
            estimatedTokens: estimatedTokens,
            contextWindow: contextWindow,
            isSmallContext: isSmallContext
        )
    }

    // MARK: - API Message Assembly

    /// Splits persisted messages at the latest compaction summary into the
    /// summary's content and the conversation slice to send to the model.
    ///
    /// The slice is everything after the summary plus the
    /// ``ChatMessage/compactionRetainedMessageCount`` messages immediately before
    /// it — those were kept verbatim when the summary was made. Returns the
    /// input unchanged (as the conversation) when there is no summary.
    static func splitAtLatestSummary(
        _ messages: [ChatMessage]
    ) -> (summary: String?, conversation: [ChatMessage]) {
        guard let summaryIndex = messages.lastIndex(where: { $0.isCompactionSummary }) else {
            return (nil, messages)
        }
        let retainedCount = messages[summaryIndex].compactionRetainedMessageCount ?? 0
        let retainedStart = messages.index(
            summaryIndex, offsetBy: -retainedCount, limitedBy: messages.startIndex
        ) ?? messages.startIndex
        let conversation = Array(messages[retainedStart ..< summaryIndex])
            + Array(messages[(summaryIndex + 1)...])
        return (messages[summaryIndex].content, conversation)
    }

    /// Builds API messages for normal-context chat turns.
    ///
    /// Assembles `[static system] → [synthetic summary pair]? → [repaired
    /// conversation]` and then appends the ``Gatekeeper``'s `<system_hint>`
    /// block (if any) to the last real user message. Input messages are
    /// never mutated — the helper creates a new ``ChatMessage`` for the
    /// modified entry.
    static func buildAPIMessages(
        agent: Agent,
        conversationMessages: [ChatMessage],
        compactionSummary: String? = nil,
        systemHint: String? = nil
    ) -> [ChatMessage] {
        let systemContent = SystemPrompt.build(for: agent)
        return assembleAPIMessages(
            systemContent: systemContent,
            conversationMessages: conversationMessages,
            compactionSummary: compactionSummary,
            systemHint: systemHint
        )
    }

    /// Builds API messages for small-context models using a minimal system prompt.
    static func buildSmallAPIMessages(
        agent: Agent,
        conversationMessages: [ChatMessage],
        compactionSummary: String? = nil,
        systemHint: String? = nil
    ) -> [ChatMessage] {
        let systemContent = SystemPrompt.buildSmall(for: agent)
        return assembleAPIMessages(
            systemContent: systemContent,
            conversationMessages: conversationMessages,
            compactionSummary: compactionSummary,
            systemHint: systemHint
        )
    }

    /// Shared assembly used by both full and compact paths.
    private static func assembleAPIMessages(
        systemContent: String,
        conversationMessages: [ChatMessage],
        compactionSummary: String?,
        systemHint: String?
    ) -> [ChatMessage] {
        let repairedMessages = repairSequence(conversationMessages)

        var apiMessages: [ChatMessage] = []
        apiMessages.append(ChatMessage(role: "system", content: systemContent))

        if let summary = compactionSummary, !summary.isEmpty {
            apiMessages.append(ChatMessage(
                role: "user",
                content: "<conversation_summary>\n\(summary)\n</conversation_summary>"
            ))
            apiMessages.append(ChatMessage(role: "assistant", content: compactionAck))
        }

        apiMessages.append(contentsOf: repairedMessages)

        if let hint = systemHint, !hint.isEmpty {
            apiMessages = appendSystemHint(hint, to: apiMessages)
        }

        return apiMessages
    }

    /// Appends the given `<system_hint>` block to the latest real user message
    /// in the outgoing array, separated by a blank line.
    ///
    /// Walks back from the end of the array to find the most recent
    /// `role == "user"` message that is not the synthetic compaction-summary
    /// carrier — if no real user message exists post-compaction, falls back
    /// to the synthetic one. Mutates only the `content` of a copy of the
    /// array (value semantics keep the caller's input untouched), preserving
    /// every other field on the matched message, including attachments.
    private static func appendSystemHint(
        _ hint: String,
        to messages: [ChatMessage]
    ) -> [ChatMessage] {
        guard let idx = messages.lastIndex(where: { $0.role == "user" }) else {
            AppLogger.warning(
                "Gatekeeper: no user message to append system_hint to",
                category: .chat
            )
            var extended = messages
            extended.append(ChatMessage(role: "user", content: hint))
            return extended
        }
        var copy = messages
        let existing = copy[idx].content ?? ""
        let merged = existing.isEmpty ? hint : existing + "\n\n" + hint
        copy[idx].content = merged
        return copy
    }

    // MARK: - Image Stripping

    /// Maximum number of image-bearing user turns whose image content is kept live
    /// in the outgoing request. Older image turns are reduced to a text placeholder.
    static let maxLiveImageTurns = 2

    /// Stands in for an image the current model has no way to look at.
    static let visionUnsupportedPlaceholder =
        "[an image was attached here, but this model cannot view images]"

    /// Applies image stripping to `messages` before they are sent to an inference provider.
    ///
    /// - When `supportsVision` is `false`, **all** image attachments are stripped to a
    ///   placeholder so the request works with text-only models (e.g. after a model switch).
    /// - When `supportsVision` is `true`, only the most recent ``maxLiveImageTurns``
    ///   image-bearing user messages keep their attachments; older ones are stripped.
    ///
    /// Stripping replaces the `attachments` array with `nil` and appends a short
    /// placeholder string to the message text so the model can see that an image was
    /// present. Bytes on disk are never touched — this only affects the outgoing request.
    static func applyImageStripping(
        _ messages: [ChatMessage],
        supportsVision: Bool
    ) -> [ChatMessage] {
        guard messages.contains(where: { $0.attachments?.isEmpty == false }) else {
            return messages
        }

        if !supportsVision {
            // Say why, not just that: a model told it cannot see can tell the user so,
            // instead of ignoring the image they just sent.
            return messages.map { msg in
                msg.attachments?.isEmpty == false
                    ? msg.withStrippedAttachments(placeholder: visionUnsupportedPlaceholder) : msg
            }
        }

        // Keep only the most recent `maxLiveImageTurns` image-bearing turns.
        // Walk from newest to oldest, tracking how many image turns we've kept.
        var result = messages
        var liveImageTurnsRemaining = maxLiveImageTurns

        for i in stride(from: result.count - 1, through: 0, by: -1) {
            guard result[i].attachments?.isEmpty == false else { continue }
            if liveImageTurnsRemaining > 0 {
                liveImageTurnsRemaining -= 1
            } else {
                result[i] = result[i].withStrippedAttachments()
            }
        }

        return result
    }

    // MARK: - Sequence Repair

    /// Removes broken tool-call groups and stray tool results from a message sequence.
    ///
    /// A valid tool-call round is an assistant message with `toolCalls` followed by
    /// one `role: "tool"` message for each call ID. A group is dropped when:
    /// - Any tool results are missing (orphaned / partial round).
    /// - The group follows a `system` message (e.g. a compaction summary). Providers
    ///   like Gemini require function calls after a user or tool-response turn.
    ///
    /// Stray `role: "tool"` messages without a preceding assistant are also dropped.
    static func repairSequence(_ messages: [ChatMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        var i = 0
        while i < messages.count {
            let msg = messages[i]
            if msg.role == "assistant", let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                let expectedIDs = Set(toolCalls.map(\.id))
                var foundIDs: Set<String> = []
                var j = i + 1
                while j < messages.count, messages[j].role == "tool" {
                    if let id = messages[j].toolCallID { foundIDs.insert(id) }
                    j += 1
                }
                let afterSystem = result.last?.role == "system"
                if foundIDs == expectedIDs, !afterSystem {
                    result.append(contentsOf: messages[i ..< j])
                }
                i = j
            } else if msg.role == "tool" {
                // Stray tool result without a preceding assistant — drop it.
                i += 1
            } else {
                result.append(msg)
                i += 1
            }
        }
        return result
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
            let conversationMessages = Array(apiMessages.dropFirst())
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
                apiMessages: [systemPrompt] + truncated,
                summary: nil,
                needsCompaction: false
            )
        }

        let threshold = Int(Double(contextWindow) * Compaction.threshold)
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
        var retained = CompactionService.retainedTail(
            messages: conversationMessages,
            tokenBudget: retainedBudget,
            minimumTurns: Compaction.minimumRetainedTurns
        )
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
                messages: [apiMessages[0]] + retained,
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
        // The triggering user message is persisted before the summary row (see
        // ``ChatViewModel.send``), so the payload's retained tail is the same
        // rows in the store and this count marks the retention boundary in both.
        summaryMessage.compactionRetainedMessageCount = retained.count

        AppLogger.info("Summary stored (\(public: summary.count) chars)", category: .chat)

        return CompactionResult(
            apiMessages: [apiMessages[0], summaryMessage] + retained,
            summary: summaryMessage, needsCompaction: false
        )
    }
}
