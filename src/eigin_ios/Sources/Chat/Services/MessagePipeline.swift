import Factory
import Foundation
import SwiftData

/// Shared turn-preparation and post-turn logic used by both chat and live calls.
///
/// Consolidates MCP tool discovery, tool registry construction, system prompt
/// building, ``Gatekeeper`` hydration, API message assembly, token estimation,
/// and compaction into a single pipeline so chat and live calls stay in sync.
enum MessagePipeline {
    /// Context usage ratio at which automatic compaction triggers.
    static let compactionThreshold: Double = 0.25

    /// Models at or below this context window size are "small" — they get
    /// sliding window compaction, a minimal system prompt, and reduced tools.
    static let smallContextThreshold: Int = 16000

    /// Low-water mark for the small-context sliding window, as a fraction of the
    /// budget. When kept history exceeds the budget (high-water mark) it is
    /// trimmed back to this fraction in one step, so the kept prefix stays stable
    /// for many turns between trims (preserving the on-device KV cache) instead of
    /// shifting every turn.
    static let slidingWindowLowWaterFraction: Double = 0.5

    /// Fraction of the context window kept as the usable input budget for
    /// small-context models. The character-based token estimator can undercount
    /// by up to 2x for multilingual SentencePiece models (e.g. Gemma / Danish),
    /// so we truncate well before the real limit to leave the engine headroom.
    static let smallContextSafetyFactor: Double = 0.75

    /// Fraction of the context window the emergency compaction pass is allowed to
    /// fill when truncating oldest messages so the compaction API call itself
    /// fits within the window.
    static let emergencyCompactionBudgetFraction: Double = 0.75

    /// Synthetic assistant acknowledgement inserted after a compaction summary
    /// so the outgoing conversation starts with a valid user→assistant turn.
    private static let compactionAck = "Understood — continuing from there."

    struct TurnInputs {
        let apiMessages: [ChatMessage]
        let registry: ToolRegistry
        let mcpTools: [any Tool]
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
        // 1. Per-turn MCP tool discovery
        let mcpServerManager = Container.shared.mcpServerManager()
        nonisolated(unsafe) let servers = mcpServers
        let mcpTools = await mcpServerManager.prepareTools(servers: servers)

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

        // 5. Determine context tier + build voice name list
        let contextWindow = KnownModelCatalog.lookup(agent.model)?.contextWindow ?? 128_000
        let isSmallContext = contextWindow <= smallContextThreshold

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
                additionalTools: mcpTools,
                integrationToolsByCapability: integrationToolsByCapability,
                onBrowse: onBrowse,
                onPresentOptions: onPresentOptions
            )
        }

        let registry = builtRegistry

        // 7. Extract the compaction summary (if any) and the real post-summary
        //    conversation slice. The summary will be rendered as a synthetic
        //    user+assistant pair inside ``buildAPIMessages``; the hint block is
        //    appended to the last *real* user message, not the synthetic one.
        let compactionSummary: String?
        let conversationMessages: [ChatMessage]
        if let idx = messages.lastIndex(where: { $0.isCompactionSummary }) {
            compactionSummary = messages[idx].content
            conversationMessages = Array(messages[(idx + 1)...])
        } else {
            compactionSummary = nil
            conversationMessages = messages
        }

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
            availableSkills: BundledSkill.all,
            connectedCapabilities: integrationManager
                .connectedCapabilities(integrations: integrations),
            activeFlow: activeFlow,
            provider: provider,
            modelID: agent.model,
            isSmallContext: isSmallContext
        )
        let systemHint = await gatekeeper.beforeTurn(hintInput)

        // 9. Build API messages
        // Apply image stripping before assembly: keep only the most recent
        // `maxLiveImageTurns` image-bearing user turns; strip all images
        // unconditionally when the model does not support vision.
        let supportsVision = KnownModelCatalog.lookup(agent.model)?.supportsVision ?? false
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
            mcpTools: mcpTools,
            integrationToolsByCapability: integrationToolsByCapability,
            estimatedTokens: estimatedTokens,
            contextWindow: contextWindow,
            isSmallContext: isSmallContext
        )
    }

    // MARK: - API Message Assembly

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
            // Strip all images.
            return messages.map { msg in
                msg.attachments?.isEmpty == false ? msg.withStrippedAttachments() : msg
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

    /// Decides whether compaction is needed and runs it if so.
    ///
    /// Compacts the entire conversation history into a summary, keeping only the
    /// user's latest message verbatim. In an emergency (tokens exceed the full
    /// context window), older messages are truncated so the compaction API call fits.
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
        onProgress: (@Sendable (CompactionPhase) -> Void)? = nil
    ) async -> CompactionResult {
        // Small-context models: use sliding window (drop oldest messages) instead
        // of expensive LLM-based summarisation.
        if contextWindow <= smallContextThreshold {
            // Reserve space for generation output so the KV cache doesn't
            // evict the system prompt during generation.
            let maxOutput = KnownModelCatalog.lookup(model)?.maxOutput ?? 256
            let inputBudget = Int(Double(contextWindow - maxOutput) * smallContextSafetyFactor)
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
            let lowMark = Int(Double(highMark) * slidingWindowLowWaterFraction)
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

        let threshold = Int(Double(contextWindow) * compactionThreshold)
        let isEmergency = estimatedTokens > contextWindow

        // Stale flag: conversation has been shortened well below the threshold
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

        // Compact everything except the user's latest message.
        let conversationMessages = Array(apiMessages.dropFirst()) // drop system prompt
        guard conversationMessages.count > 1 else {
            return CompactionResult(apiMessages: apiMessages, summary: nil, needsCompaction: false)
        }
        let lastMessage = conversationMessages.last!
        var toCompact = Array(conversationMessages.dropLast())

        // Emergency: truncate oldest messages so the compaction API call fits.
        if isEmergency {
            let compactionBudget = Int(Double(contextWindow) * emergencyCompactionBudgetFraction)
            let truncated = CompactionService.truncateForBudget(
                messages: toCompact,
                tokenBudget: compactionBudget
            )

            if truncated.count < toCompact.count {
                AppLogger.warning(
                    "Emergency: dropping \(public: toCompact.count - truncated.count) oldest messages to fit budget",
                    category: .chat
                )
                toCompact = truncated
            }

            if toCompact.isEmpty {
                AppLogger.warning(
                    "Emergency fallback: returning system prompt + latest message",
                    category: .chat
                )
                return CompactionResult(
                    apiMessages: [apiMessages[0], lastMessage],
                    summary: nil, needsCompaction: false
                )
            }
        }

        AppLogger.info("Compacting \(public: toCompact.count) messages", category: .chat)

        guard let summary = await CompactionService.compact(
            messages: toCompact,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            chatService: chatService,
            onProgress: onProgress
        ) else {
            return CompactionResult(apiMessages: apiMessages, summary: nil, needsCompaction: true)
        }

        var summaryMessage = ChatMessage(
            role: "system",
            content: "Summary of earlier conversation:\n\n\(summary)"
        )
        summaryMessage.isCompactionSummary = true

        AppLogger.info("Summary stored (\(public: summary.count) chars)", category: .chat)

        return CompactionResult(
            apiMessages: [apiMessages[0], summaryMessage, lastMessage],
            summary: summaryMessage, needsCompaction: false
        )
    }
}
