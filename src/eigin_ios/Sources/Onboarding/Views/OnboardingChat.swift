import Factory
import SwiftData
import SwiftUI

/// The guided onboarding conversation.
///
/// Drives ``OnboardingOrchestrator`` through all stages, displays the conversation,
/// and creates the agent once all stages complete. Works with any provider — local or cloud.
struct OnboardingChat: View {
    @Environment(\.colors) private var colors
    @Environment(\.modelContext) private var modelContext
    @Injected(\.chatService) private var chatService
    @Injected(\.languageManager) private var languageManager

    let provider: Provider
    let model: String
    let onReveal: (Agent, String, OnboardingPriority?) -> Void

    @State private var orchestrator = OnboardingOrchestrator(
        greeting: LocalOnboardingScript.greeting,
        stages: LocalOnboardingScript
            .stages(language: Container.shared.languageManager().currentLanguage)
    )

    @State private var chatLoop = AgenticChatLoop(isBootstrap: true)

    /// We create a transient agent to satisfy AgenticChatLoop's requirements.
    /// It is only inserted into the modelContext upon successful completion.
    @State private var agent: Agent

    @State private var displayedMessages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var streamTask: Task<Void, Never>?
    @State private var didAppear = false
    @State private var isGenerating = false

    init(
        provider: Provider,
        model: String,
        onReveal: @escaping (Agent, String, OnboardingPriority?) -> Void
    ) {
        self.provider = provider
        self.model = model
        self.onReveal = onReveal

        let initialAgent = Agent(name: "Agent", providerID: provider.id, model: model)
        _agent = State(initialValue: initialAgent)
    }

    private var isStreaming: Bool {
        chatLoop.phase == .waiting || chatLoop.phase == .streaming || isGenerating
    }

    private var chatItems: [ChatItem] {
        ChatItem.buildItems(
            from: displayedMessages + chatLoop.committedMessages,
            chatLoop: chatLoop,
            chatError: nil
        )
    }

    private var isInputDisabled: Bool {
        isStreaming
    }

    var body: some View {
        ChatFeed(
            items: chatItems,
            throttler: chatLoop.throttler,
            splitter: chatLoop.splitter,
            messageText: $messageText,
            isInputDisabled: isInputDisabled,
            onSend: { _ in handleSend() },
            onStop: nil,
            lastStreamedItemID: chatLoop.lastStreamedItemID
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let options = orchestrator.options, !isStreaming {
                VStack(spacing: 0) {
                    Divider()
                    optionsRow(options)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0), value: orchestrator.options != nil)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .task {
            guard !didAppear else { return }
            didAppear = true
            let scriptedService = ScriptedChatService(
                text: orchestrator.greeting,
                thinkingDelay: .milliseconds(Int.random(in: 500 ... 1000))
            )
            do {
                _ = try await chatLoop.run(
                    messages: [],
                    tools: nil,
                    agent: agent,
                    provider: provider,
                    chatService: scriptedService,
                    toolExecutor: ToolRegistry(tools: [])
                )
                let completed = chatLoop.completeRound()
                displayedMessages.append(contentsOf: completed)
            } catch {
                chatLoop.abort()
            }
        }
    }

    // MARK: - Subviews

    private func optionsRow(_ options: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.n8) {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        handleSelect(option)
                    }
                    .buttonStyle(.bordered)
                    .tint(colors.accent)
                }
            }
            .padding(.horizontal, Spacing.n16)
        }
        .padding(.vertical, Spacing.n8)
        .background(colors.surface.standard.base)
    }

    // MARK: - Actions

    private func handleSend() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        displayedMessages.append(ChatMessage(role: "user", content: text))
        messageText = ""

        // Force the typing indicator to show immediately, even during extraction
        chatLoop.throttler.start()

        streamTask = Task {
            do {
                let output = try await orchestrator.send(
                    text,
                    chatService: chatService,
                    baseURL: provider.baseURL,
                    providerID: provider.id,
                    model: model,
                    conversationHistory: displayedMessages
                )
                await handleOutput(output)
            } catch {
                chatLoop.abort()
            }
        }
    }

    private func handleSelect(_ option: String) {
        displayedMessages.append(ChatMessage(role: "user", content: option))

        // Force the typing indicator to show immediately
        chatLoop.throttler.start()

        streamTask = Task {
            do {
                let output = try await orchestrator.select(
                    option,
                    chatService: chatService,
                    baseURL: provider.baseURL,
                    providerID: provider.id,
                    model: model,
                    conversationHistory: displayedMessages
                )
                await handleOutput(output)
            } catch {
                chatLoop.abort()
            }
        }
    }

    private func handleOutput(_ output: OrchestratorOutput) async {
        switch output {
        case .directive(let systemHint):
            do {
                let systemPrompt = """
                You are a new AI agent in the Eigin app.
                You're interviewing the user to get to know them and set up their personal AI.
                Keep answers brief and natural.
                Always follow instructions in the <system_hint> block.
                """

                var apiMessages: [ChatMessage] = [
                    ChatMessage(role: "system", content: systemPrompt),
                ]
                apiMessages.append(contentsOf: displayedMessages)

                var combinedHint = "Speak in \(languageManager.currentLanguage.displayName)."
                if let hint = systemHint, !hint.isEmpty {
                    combinedHint += "\n" + hint
                }
                apiMessages = appendSystemHint(combinedHint, to: apiMessages)

                apiMessages = applySlidingWindowIfNeeded(apiMessages: apiMessages)

                _ = try await chatLoop.run(
                    messages: apiMessages,
                    tools: nil,
                    agent: agent,
                    provider: provider,
                    chatService: chatService,
                    toolExecutor: ToolRegistry(tools: [])
                )

                let completed = chatLoop.completeRound()
                displayedMessages.append(contentsOf: completed)
            } catch {
                chatLoop.abort()
            }

        case .scripted(let text):
            let scriptedService = ScriptedChatService(
                text: text,
                thinkingDelay: .milliseconds(Int.random(in: 500 ... 1000))
            )
            do {
                _ = try await chatLoop.run(
                    messages: displayedMessages,
                    tools: nil,
                    agent: agent,
                    provider: provider,
                    chatService: scriptedService,
                    toolExecutor: ToolRegistry(tools: [])
                )
                let completed = chatLoop.completeRound()
                displayedMessages.append(contentsOf: completed)
            } catch {
                chatLoop.abort()
            }

        case .finished:
            await finishOnboarding()
        }
    }

    @MainActor
    private func finishOnboarding() async {
        agent.name = orchestrator.data.agentName ?? "Agent"
        agent.emoji = orchestrator.data.agentEmoji ?? "🤖"
        modelContext.insert(agent)

        let statusText = Localized.Onboarding.Chat.settingUpMessage
        let scriptedService = ScriptedChatService(
            text: statusText,
            thinkingDelay: .milliseconds(Int.random(in: 500 ... 1000))
        )
        do {
            _ = try await chatLoop.run(
                messages: displayedMessages,
                tools: nil,
                agent: agent,
                provider: provider,
                chatService: scriptedService,
                toolExecutor: ToolRegistry(tools: [])
            )
            let completed = chatLoop.completeRound()
            displayedMessages.append(contentsOf: completed)
        } catch {
            chatLoop.abort()
        }

        isGenerating = true
        defer { isGenerating = false }

        let generationCall = CoreTextGenerationCall(chatService: chatService)
        let heroCall = HeroTextGenerationCall(chatService: chatService)
        let language = languageManager.currentLanguage

        let identityCore = try? await generationCall.run(
            type: .identity,
            data: orchestrator.data,
            language: language,
            baseURL: provider.baseURL,
            providerID: provider.id,
            model: model
        )

        let userCore = try? await generationCall.run(
            type: .user,
            data: orchestrator.data,
            language: language,
            baseURL: provider.baseURL,
            providerID: provider.id,
            model: model
        )

        if let identity = identityCore, let user = userCore {
            agent.identityCore = identity
            agent.userCore = user
            AppLogger.debug(
                "Generated core texts — identity: \(private: identity.prefix(50))..., user: \(private: user.prefix(50))...",
                category: .onboarding
            )
        } else {
            OnboardingAgentFactory.configure(agent: agent, from: orchestrator.data)
            AppLogger.debug(
                "Core text generation failed or returned empty — falling back to OnboardingAgentFactory",
                category: .onboarding
            )
        }

        if agent.soulCore.isEmpty {
            agent.soulCore = AgentBootstrapPrompt.soulTemplate
        }

        let heroText = try? await heroCall.run(
            identityCore: agent.identityCore,
            userCore: agent.userCore,
            soulCore: agent.soulCore,
            language: language,
            baseURL: provider.baseURL,
            providerID: provider.id,
            model: model
        )

        let finalHeroText = heroText ?? defaultHeroText()
        AppLogger.debug(
            "Hero text: \(private: finalHeroText.prefix(60))...",
            category: .onboarding
        )

        agent.bootstrapComplete = true
        onReveal(agent, finalHeroText, orchestrator.data.priority)
    }

    private func defaultHeroText() -> String {
        Localized.Onboarding.Welcome.description
    }

    private func appendSystemHint(_ hint: String, to messages: [ChatMessage]) -> [ChatMessage] {
        guard let idx = messages.lastIndex(where: { $0.role == "user" }) else {
            var extended = messages
            extended.append(ChatMessage(role: "user", content: hint))
            return extended
        }
        var copy = messages
        let existing = copy[idx].content ?? ""
        let hintBlock = "<system_hint>\n\(hint)\n</system_hint>"
        let merged = existing.isEmpty ? hintBlock : existing + "\n\n" + hintBlock
        copy[idx] = ChatMessage(role: "user", content: merged)
        return copy
    }

    /// Applies sliding window truncation for small-context local models.
    ///
    /// Keeps the system prompt and truncates the oldest conversation messages
    /// so the request fits within the model's input budget.
    private func applySlidingWindowIfNeeded(apiMessages: [ChatMessage]) -> [ChatMessage] {
        let contextWindow = KnownModelCatalog.lookup(model)?.contextWindow ?? 128_000

        guard contextWindow <= MessagePipeline.smallContextThreshold else {
            return apiMessages
        }

        let estimatedTokens = TokenEstimator.estimate(messages: apiMessages)
        let maxOutput = KnownModelCatalog.lookup(model)?.maxOutput ?? 256
        let inputBudget = contextWindow - maxOutput

        guard estimatedTokens > inputBudget else {
            return apiMessages
        }

        let systemPrompt = apiMessages[0]
        let systemTokens = TokenEstimator.estimate(systemPrompt.content ?? "") + 4
        let conversationBudget = max(inputBudget - systemTokens, 0)
        let conversationMessages = Array(apiMessages.dropFirst())
        let truncated = CompactionService.truncateForBudget(
            messages: conversationMessages,
            tokenBudget: conversationBudget
        )

        AppLogger.debug(
            "Sliding window: kept \(public: truncated.count)/\(public: conversationMessages.count) messages for budget \(public: conversationBudget)",
            category: .onboarding
        )

        return [systemPrompt] + truncated
    }
}
