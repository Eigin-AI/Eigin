import Factory
import Foundation
import SwiftData

/// Thread-safe holder for the background tool signal.
final class BackgroundSignalBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: BackgroundToolSignal?

    var value: BackgroundToolSignal? {
        lock.withLock { _value }
    }

    func set(_ signal: BackgroundToolSignal) {
        lock.withLock {
            // Once a .notify is recorded, don't overwrite it.
            if case .notify = _value { return }
            _value = signal
        }
    }
}

/// Orchestrates a background agent review turn.
/// Keeps per-activity contexts on the main actor while model requests overlap.
@MainActor
enum BackgroundPromptService {
    enum Status: Sendable { case completed, failed, cancelled, skipped }

    struct Result: Sendable {
        var status: Status = .completed
        var reason: String?
        var mode: BackgroundRunMode?
        var didNotify = false
        var agentID: UUID?
        var notificationTitle: String?
        var notificationBody: String?
        var summary: String?
        var deliverAt: Date?
        var agentName: String?
        var agentEmoji: String?
    }

    static func execute(
        container: ModelContainer, agentID: UUID, providerID: UUID,
        mode: BackgroundRunMode, model: (any ChatService)?,
        transcriptSink: any BackgroundPromptTranscriptSink
    ) async -> Result {
        guard !Task.isCancelled else {
            return Result(status: .cancelled)
        }
        let context = ModelContext(container)

        // Fetch the primary agent.
        guard let agents = try? context.fetch(FetchDescriptor<Agent>(
            predicate: #Predicate { $0.id == agentID }
        )), let agent = agents.first
        else {
            AppLogger.warning("No active agent found", category: .backgroundPrompt)
            return Result(status: .skipped, reason: "Agent unavailable")
        }

        let proactivity = agent.proactivity
        guard proactivity.isBackgroundEnabled else {
            AppLogger.info("Proactivity is reactive, skipping", category: .backgroundPrompt)
            return Result(status: .skipped, reason: "Proactivity is reactive")
        }

        // Fetch the provider.
        let providerDescriptor = FetchDescriptor<Provider>(
            predicate: #Predicate { $0.id == providerID }
        )
        guard let providers = try? context.fetch(providerDescriptor),
              let provider = providers.first
        else {
            AppLogger.warning("Provider not found for agent", category: .backgroundPrompt)
            return Result(status: .skipped, reason: "Provider unavailable")
        }

        guard !ProviderPreset.isLocal(provider.baseURL) else {
            return Result(
                status: .skipped,
                reason: "Background activities require a cloud provider"
            )
        }

        // DefaultChatService resolves credentials again at dispatch; relay uses credits.
        let keychain = DefaultKeychainService(serviceKey: AppKeys.keychainServiceName)
        if model == nil, await ProviderCredentials.apiToken(
            baseURL: provider.baseURL,
            providerID: provider.id,
            keychain: keychain,
            credentialStores: Container.shared.providerCredentialResolver()
        ) == nil {
            AppLogger.warning("Provider credentials not available", category: .backgroundPrompt)
            return Result(status: .skipped, reason: "Provider credentials unavailable")
        }

        // Build access policy — background has no current space but can see global + public space
        // data.
        let publicSpaces = (try? context.fetch(FetchDescriptor<Space>(
            predicate: #Predicate { $0.isPrivate == false }
        ))) ?? []
        let accessPolicy = SpaceAccessPolicy(
            currentSpaceID: nil,
            publicSpaceIDs: Set(publicSpaces.map(\.id))
        )

        // Build system prompt with active intents.
        let intentService = DefaultIntentService(modelContainer: container)
        let promptIntents = mode == .reflection ? [] : await (try? intentService.activeIntents(
            agentID: agent.id, limit: mode == .preparation ? Int.max : 5, accessPolicy: accessPolicy
        )) ?? []
        let upcomingInitiatives: [String]
        if mode == .preparation {
            let intents = (try? context.fetch(FetchDescriptor<Intent>())) ?? []
            let agreements = (try? context.fetch(FetchDescriptor<IntentInitiative>())) ?? []
            let upcoming = agreements.compactMap { agreement -> (Date, String)? in
                guard agreement.enabled,
                      let intent = intents.first(where: { $0.id == agreement.intentID }),
                      intent.agentID == agent.id, intent.intentStatus == .active,
                      accessPolicy.canAccess(itemSpaceID: intent.spaceID),
                      let schedule = intent.schedules
                      .first(where: { $0.id == agreement.scheduleID }),
                      let date = schedule.nextOccurrence(onOrAfter: .now),
                      date < Date.now.addingTimeInterval(7 * 86400) else { return nil }
                return (
                    date,
                    "\(date.ISO8601Format()) intent \(intent.id): \(String(agreement.instructions.prefix(400)))"
                )
            }.sorted { $0.0 < $1.0 }
            upcomingInitiatives = upcoming.map(\.1)
        } else { upcomingInitiatives = [] }

        // Fetch recent notifications so the agent doesn't repeat itself.
        let recentRequestDescriptor = FetchDescriptor<AgentInitiativeRequest>(
            predicate: #Predicate { $0.agentID == agentID },
            sortBy: [SortDescriptor(\AgentInitiativeRequest.createdAt, order: .reverse)]
        )
        let recentNotifications: [NotificationSnapshot] =
            ((try? context.fetch(recentRequestDescriptor)) ?? [])
                .prefix(3)
                .map { NotificationSnapshot(
                    title: $0.title ?? "",
                    message: $0.message,
                    createdAt: $0.createdAt
                ) }

        AppLogger.info(
            "Selected background mode: \(public: mode.rawValue)",
            category: .backgroundPrompt
        )

        // Load the agent's permission policy so user-granted tools are available.
        let permissionPolicy = PermissionPolicyLoader.load(
            for: agent,
            chatID: nil,
            modelContext: context
        )

        let knowledgeService = DefaultKnowledgeService(
            modelContainer: container,
            initialAccessPolicy: mode == .reflection ? accessPolicy : nil
        )
        let additionalContext: String
        if mode == .reflection {
            do {
                additionalContext = try ReflectionContext.load(
                    container: container, agentID: agentID, accessPolicy: accessPolicy,
                    permissionPolicy: permissionPolicy
                )
            } catch {
                AppLogger.warning("Reflection history unavailable", category: .backgroundPrompt)
                return Result(status: .failed, reason: error.localizedDescription)
            }
        } else {
            additionalContext = await knowledgeConsolidationSection(
                mode: mode, knowledgeService: knowledgeService
            )
        }

        let systemPrompt = BackgroundPrompt.build(
            agent: agent,
            proactivity: proactivity,
            activeIntents: promptIntents,
            recentNotifications: mode == .reflection ? [] : recentNotifications,
            mode: mode,
            upcomingInitiatives: upcomingInitiatives,
            additionalContext: additionalContext
        )

        // Build tool registry - includes tools the agent has .always permission for.
        let signalBox = BackgroundSignalBox()
        let skillSession = mode == .preparation ? SkillSession(
            toolAccess: .preparation,
            permissionPolicy: permissionPolicy, accessPolicy: accessPolicy,
            agentID: agent.id
        ) : nil
        let registry = ToolRegistry.background(
            accessPolicy: accessPolicy,
            permissionPolicy: permissionPolicy,
            agentID: mode == .maintenance ? nil : agent.id,
            preparationOnly: mode == .preparation,
            knowledgeService: knowledgeService,
            modelContainer: container,
            skillSession: skillSession,
            onSignal: { signalBox.set($0) }
        )

        // Build initial messages. A user message is required because some
        // providers (e.g. Gemini) reject requests with only a system message.
        let apiMessages: [ChatMessage] = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: "You can start now."),
        ]

        // Use AgenticChatLoop for full provider compatibility (thought signatures, etc.).
        let chatService: ChatService = model ?? DefaultChatService(
            keychainService: keychain,
            providerCredentialResolver: Container.shared.providerCredentialResolver(),
            consentStore: Container.shared.aiConsentStore()
        )

        let produced: [ChatMessage]
        let rounds: Int
        do {
            (produced, rounds) = try await runChatLoop(
                apiMessages: apiMessages,
                registry: registry,
                agent: agent,
                provider: provider,
                chatService: chatService,
                signalBox: signalBox,
                skillSession: skillSession,
                accessPolicy: accessPolicy,
                permissionPolicy: permissionPolicy,
                knowledgeService: knowledgeService,
                modelContainer: container,
                onFailure: { checkpoint, rounds, error in
                    transcriptSink.store(
                        systemPrompt: systemPrompt, apiMessages: apiMessages,
                        producedMessages: checkpoint, rounds: rounds,
                        signal: "interrupted (\(mode.rawValue))", reason: error.localizedDescription
                    )
                }
            )
        } catch {
            let result = Result(
                status: Task.isCancelled || error is CancellationError ? .cancelled : .failed,
                reason: error.localizedDescription
            )
            AppLogger.warning(
                "Background \(public: mode.rawValue) ended: \(private: error.localizedDescription)",
                category: .backgroundPrompt
            )
            return result
        }

        AppLogger.info(
            "Loop produced \(public: produced.count) messages, rounds: \(public: rounds), mode: \(public: mode.rawValue)",
            category: .backgroundPrompt
        )

        // Process the signal.
        let signal = signalBox.value
        guard case .notify(let title, let message, let summary, let deliverAt) = signal else {
            let reason = if rounds >= 30 {
                "Reached max rounds without decision"
            } else if rounds == 0 {
                "Agent returned without using any tools"
            } else {
                "Agent stayed silent (rounds: \(rounds))"
            }
            AppLogger.info("\(public: reason)", category: .backgroundPrompt)

            transcriptSink.store(
                systemPrompt: systemPrompt,
                apiMessages: apiMessages,
                producedMessages: produced,
                rounds: rounds,
                signal: "silent (\(mode.rawValue))",
                reason: reason
            )

            return Result()
        }

        AppLogger.info(
            "Agent wants to notify: \(private: title)\(public: deliverAt != nil ? " (scheduled)" : "")",
            category: .backgroundPrompt
        )

        transcriptSink.store(
            systemPrompt: systemPrompt,
            apiMessages: apiMessages,
            producedMessages: produced,
            rounds: rounds,
            signal: "notify (\(mode.rawValue)): \(title)",
            reason: "Agent chose to notify"
        )

        return Result(
            didNotify: true, agentID: agent.id, notificationTitle: title, notificationBody: message,
            summary: summary, deliverAt: deliverAt, agentName: agent.name, agentEmoji: agent.emoji
        )
    }

    /// Deterministic consolidation candidates for the maintenance run, rendered
    /// for prompt injection. Uses the shared knowledge service so it sees the
    /// same graph the background tools will act on (global scope). Empty for
    /// other modes or when nothing is flagged.
    static func knowledgeConsolidationSection(
        mode: BackgroundRunMode, knowledgeService: any KnowledgeService
    ) async -> String {
        guard mode == .maintenance else { return "" }
        return await (try? KnowledgeOperationCoordinator.shared.perform {
            let candidates = await MemoryConsolidation.candidates(
                knowledgeService: knowledgeService, spaceID: nil, agentID: nil
            )
            // Stamp everything surfaced this run so the next run rotates to different
            // work, even if the agent decided some items needed no action.
            try? await knowledgeService.markReviewed(
                candidates.reviewedIDs, spaceID: nil, agentID: nil
            )
            let section = candidates.promptSection()
            // Empty list still needs an explicit stop, so the agent doesn't wander
            // off and start browsing the base (e.g. read-only bundled knowledge).
            return section.isEmpty
                ? "Nothing stood out in your knowledge this time — there's nothing to consolidate. Stop."
                : section
        }) ?? ""
    }

    /// `UserDefaults` key for a given agent's initiative focus-rotation history.
    private static func initiativeFocusHistoryKey(agentID: UUID) -> String {
        "initiativeFocusHistory_\(agentID.uuidString)"
    }

    /// Runs a background tool loop, refreshing initiative tools after each round.
    @MainActor
    static func runChatLoop(
        apiMessages: [ChatMessage],
        registry: ToolRegistry,
        agent: Agent,
        provider: Provider,
        chatService: ChatService,
        signalBox: BackgroundSignalBox,
        skillSession: SkillSession?,
        accessPolicy: SpaceAccessPolicy,
        permissionPolicy: any ToolPermissionPolicy,
        knowledgeService: (any KnowledgeService)? = nil,
        modelContainer: ModelContainer? = nil,
        onFailure: ([ChatMessage], Int, any Error) -> Void = { _, _, _ in }
    ) async throws -> ([ChatMessage], Int) {
        let chatLoop = AgenticChatLoop(
            isBootstrap: false,
            throttler: PassthroughThrottler(),
            permissionPolicy: AlwaysAllowPolicy()
        )
        chatLoop.propagatesStreamCancellation = true
        chatLoop.shouldTerminate = { signalBox.value != nil }
        if let skillSession {
            chatLoop.onToolsChanged = {
                await skillSession.prepareActiveSkills(agent: agent)
                let tools = skillSession.tools()
                let updated = ToolRegistry.background(
                    accessPolicy: accessPolicy,
                    permissionPolicy: permissionPolicy,
                    agentID: agent.id,
                    additionalTools: tools,
                    preparationOnly: skillSession.toolAccess == .preparation,
                    knowledgeService: knowledgeService,
                    modelContainer: modelContainer,
                    skillSession: skillSession,
                    onSignal: { signalBox.set($0) }
                )
                return (updated.definitions, updated)
            }
        }
        defer { chatLoop.settle() }
        do {
            let produced = try await chatLoop.run(
                messages: apiMessages,
                tools: registry.definitions,
                agent: agent,
                provider: provider,
                chatService: chatService,
                toolExecutor: registry
            )
            try Task.checkCancellation()
            return (produced, chatLoop.roundsExecuted)
        } catch {
            onFailure(chatLoop.buildCheckpoint(), chatLoop.roundsExecuted, error)
            throw error
        }
    }
}
