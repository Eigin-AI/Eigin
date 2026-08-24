import Factory
import Foundation
import SwiftData

/// Thread-safe holder for the background tool signal.
private final class SignalBox: @unchecked Sendable {
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
/// Creates its own `ModelContext` so it's safe to call from a `BGProcessingTask`.
enum BackgroundPromptService {
    struct Result {
        let didNotify: Bool
        let agentID: UUID?
        let notificationTitle: String?
        let notificationBody: String?
        let summary: String?
        let deliverAt: Date?
        let agentName: String?
        let agentEmoji: String?
    }

    private static let silentResult = Result(
        didNotify: false, agentID: nil, notificationTitle: nil, notificationBody: nil,
        summary: nil, deliverAt: nil, agentName: nil, agentEmoji: nil
    )

    /// Runs a single background agent turn. Returns the result indicating whether to notify.
    /// Pass `modeOverride` to force a specific mode (useful for debugging); otherwise the most
    /// overdue mode is
    /// selected.
    static func run(
        container: ModelContainer,
        modeOverride: BackgroundRunMode? = nil
    ) async -> Result {
        let context = ModelContext(container)

        // Fetch the primary agent.
        guard let agents = try? context.fetch(Agent.primaryDescriptor),
              let agent = agents.primary
        else {
            AppLogger.warning("No active agent found", category: .backgroundPrompt)
            return silentResult
        }

        let proactivity = agent.proactivity
        guard proactivity.isBackgroundEnabled else {
            AppLogger.info("Proactivity is reactive, skipping", category: .backgroundPrompt)
            return silentResult
        }

        let mode = modeOverride ?? selectMode()

        // Fetch the provider.
        let providerID = agent.providerID
        let providerDescriptor = FetchDescriptor<Provider>(
            predicate: #Predicate { $0.id == providerID }
        )
        guard let providers = try? context.fetch(providerDescriptor),
              let provider = providers.first
        else {
            AppLogger.warning("Provider not found for agent", category: .backgroundPrompt)
            return silentResult
        }

        // Verify the provider has usable credentials (DefaultChatService will resolve them itself).
        // Relay and on-device providers carry no keychain API key, so this resolves to an empty
        // token and the turn proceeds; relay is authorized per-request via the credit wallet.
        let keychain = DefaultKeychainService(serviceKey: AppKeys.keychainServiceName)
        guard ProviderCredentials.apiToken(
            baseURL: provider.baseURL, providerID: provider.id, keychain: keychain
        ) != nil else {
            AppLogger.warning("Provider credentials not available", category: .backgroundPrompt)
            return silentResult
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
        let promptIntents: [IntentSnapshot]
        if mode == .initiative {
            // Rotate through active intents so the same one isn't re-picked
            // every run; fetch the full pool (unbounded) so rotation can see
            // everything, not just the top 5.
            let allActiveIntents = await (try? intentService.activeIntents(
                agentID: agent.id,
                limit: Int.max,
                accessPolicy: accessPolicy
            )) ?? []
            let ranked = allActiveIntents.sorted { $0.relevance > $1.relevance }
            let historyKey = Self.initiativeFocusHistoryKey(agentID: agent.id)
            let history = UserDefaults.standard.stringArray(forKey: historyKey)?
                .compactMap(UUID.init(uuidString:)) ?? []
            let selection = InitiativeIntentRotation.select(rankedIntents: ranked, history: history)
            UserDefaults.standard.set(
                selection.history.map(\.uuidString), forKey: historyKey
            )
            promptIntents = selection.focus.map { [$0] } ?? []
        } else {
            promptIntents = await (try? intentService.activeIntents(
                agentID: agent.id,
                limit: 5,
                accessPolicy: accessPolicy
            )) ?? []
        }

        // Fetch recent notifications so the agent doesn't repeat itself.
        let agentID = agent.id
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

        nonisolated(unsafe) let agentRef = agent
        nonisolated(unsafe) let providerRef = provider
        AppLogger.info(
            "Selected background mode: \(public: mode.rawValue)",
            category: .backgroundPrompt
        )

        // For consolidation, compute the candidate list (duplicates, conflicts,
        // stale entries) fresh and inject it into the prompt.
        let knowledgeSection = await knowledgeConsolidationSection(mode: mode)

        let systemPrompt = await MainActor.run {
            BackgroundPrompt.build(
                agent: agentRef,
                proactivity: proactivity,
                activeIntents: promptIntents,
                recentNotifications: recentNotifications,
                mode: mode,
                additionalContext: knowledgeSection
            )
        }

        // Load the agent's permission policy so user-granted tools are available.
        nonisolated(unsafe) let contextRef = context
        let permissionPolicy = await MainActor.run {
            PermissionPolicyLoader.load(for: agentRef, chatID: nil, modelContext: contextRef)
        }

        // Build tool registry - includes tools the agent has .always permission for.
        let signalBox = SignalBox()
        let registry = await ToolRegistry.background(
            accessPolicy: accessPolicy,
            permissionPolicy: permissionPolicy,
            onSignal: { signalBox.set($0) }
        )

        // Build initial messages. A user message is required because some
        // providers (e.g. Gemini) reject requests with only a system message.
        let apiMessages: [ChatMessage] = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: "You can start now."),
        ]

        // Use AgenticChatLoop for full provider compatibility (thought signatures, etc.).
        let chatService: ChatService = DefaultChatService(keychainService: keychain)

        let (produced, rounds) = await runChatLoop(
            apiMessages: apiMessages,
            registry: registry,
            agent: agentRef,
            provider: providerRef,
            chatService: chatService,
            signalBox: signalBox
        )

        recordRun(mode: mode)

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

#if DEBUG
            BackgroundPromptDebug.store(
                systemPrompt: systemPrompt,
                apiMessages: apiMessages,
                producedMessages: produced,
                rounds: rounds,
                signal: "silent (\(mode.rawValue))",
                reason: reason
            )
#endif

            return silentResult
        }

        AppLogger.info(
            "Agent wants to notify: \(private: title)\(public: deliverAt != nil ? " (scheduled)" : "")",
            category: .backgroundPrompt
        )

#if DEBUG
        BackgroundPromptDebug.store(
            systemPrompt: systemPrompt,
            apiMessages: apiMessages,
            producedMessages: produced,
            rounds: rounds,
            signal: "notify (\(mode.rawValue)): \(title)",
            reason: "Agent chose to notify"
        )
#endif

        return Result(
            didNotify: true, agentID: agent.id, notificationTitle: title, notificationBody: message,
            summary: summary, deliverAt: deliverAt, agentName: agent.name, agentEmoji: agent.emoji
        )
    }

    /// Picks the most overdue background mode based on elapsed time vs preferred interval.
    private static func selectMode() -> BackgroundRunMode {
        var bestMode = BackgroundRunMode.initiative
        var bestUrgency = -1.0

        for mode in BackgroundRunMode.allCases {
            let lastRun = UserDefaults.standard.object(forKey: mode.lastRunKey) as? Date
            let elapsed = lastRun.map { Date().timeIntervalSince($0) } ?? mode.preferredInterval
            let urgency = elapsed / mode.preferredInterval
            if urgency > bestUrgency {
                bestUrgency = urgency
                bestMode = mode
            }
        }
        return bestMode
    }

    private static func recordRun(mode: BackgroundRunMode) {
        UserDefaults.standard.set(Date(), forKey: mode.lastRunKey)
    }

    /// Deterministic consolidation candidates for the maintenance run, rendered
    /// for prompt injection. Uses the shared knowledge service so it sees the
    /// same graph the background tools will act on (global scope). Empty for
    /// other modes or when nothing is flagged.
    private static func knowledgeConsolidationSection(mode: BackgroundRunMode) async -> String {
        guard mode == .maintenance else { return "" }
        let knowledgeService = await MainActor.run { Container.shared.knowledgeService() }
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
    }

    /// `UserDefaults` key for a given agent's initiative focus-rotation history.
    private static func initiativeFocusHistoryKey(agentID: UUID) -> String {
        "initiativeFocusHistory_\(agentID.uuidString)"
    }

    @MainActor
    private static func runChatLoop(
        apiMessages: [ChatMessage],
        registry: ToolRegistry,
        agent: Agent,
        provider: Provider,
        chatService: ChatService,
        signalBox: SignalBox
    ) async -> ([ChatMessage], Int) {
        let chatLoop = AgenticChatLoop(
            isBootstrap: false,
            throttler: PassthroughThrottler(),
            permissionPolicy: AlwaysAllowPolicy()
        )
        chatLoop.shouldTerminate = { signalBox.value != nil }
        do {
            let produced = try await chatLoop.run(
                messages: apiMessages,
                tools: registry.definitions,
                agent: agent,
                provider: provider,
                chatService: chatService,
                toolExecutor: registry
            )
            let rounds = chatLoop.roundsExecuted
            chatLoop.settle()
            return (produced, rounds)
        } catch is CancellationError {
            AppLogger.warning(
                "Chat loop cancelled (likely OS expiration)",
                category: .backgroundPrompt
            )
            chatLoop.settle()
            return ([], 0)
        } catch {
            AppLogger.error(
                "Chat loop error: \(private: error.localizedDescription)",
                category: .backgroundPrompt
            )
            chatLoop.settle()
            return ([], 0)
        }
    }
}
