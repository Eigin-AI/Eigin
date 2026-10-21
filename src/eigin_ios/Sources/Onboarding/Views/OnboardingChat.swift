import Factory
import SwiftData
import SwiftUI

/// The onboarding conversation: a restricted, real agent chat.
///
/// The agent opens already knowing the user's name and priority, gets to know
/// them, and records what it learns into its core documents via tools. A
/// side-channel ``OnboardingAssessment`` runs in parallel each turn to drive the
/// avatar's fill and pace the agent through ``OnboardingPacing`` hints. The
/// agent commits everything in one ``FinishOnboardingTool`` call, which ends the
/// turn; then the reveal plays, and the real chat answers the commit.
struct OnboardingChat: View {
    @Environment(\.colors) private var colors
    @Environment(\.modelContext) private var modelContext
    @Injected(\.chatService) private var chatService
    @Injected(\.modelRouter) private var modelRouter
    @Injected(\.languageManager) private var languageManager
    @Injected(\.knowledgeService) private var knowledgeService
    @Injected(\.intentService) private var intentService

    let provider: Provider
    let model: String
    let name: String
    let priority: OnboardingPriority?
    let onComplete: () -> Void
    let onBack: () -> Void

    @State private var chatLoop = AgenticChatLoop(isBootstrap: true)
    @State private var agent: Agent
    @State private var displayedMessages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var didAppear = false
    @State private var isFinishing = false
    @State private var chatError: ConnectionError?

    @State private var userTurns = 0
    @State private var fillProgress = OnboardingStep.conversation.avatarProgress
    @State private var lastAssessment = OnboardingAssessment.Result.empty
    @State private var commit: OnboardingCommit?
    @State private var didReveal = false

    private let pacing = OnboardingPacing()

    init(
        provider: Provider,
        model: String,
        name: String,
        priority: OnboardingPriority?,
        onComplete: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.provider = provider
        self.model = model
        self.name = name
        self.priority = priority
        self.onComplete = onComplete
        self.onBack = onBack
        _agent = State(initialValue: Agent(name: "Eigin", providerID: provider.id, model: model))
    }

    private var isStreaming: Bool {
        chatLoop.phase == .waiting || chatLoop.phase == .streaming || isFinishing
    }

    private var chatItems: [ChatItem] {
        ChatItem.buildItems(
            from: displayedMessages + chatLoop.committedMessages,
            chatLoop: chatLoop,
            chatError: chatError
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ChatFeed(
                    items: chatItems,
                    throttler: chatLoop.throttler,
                    streamingItemID: chatLoop.streamingItemID,
                    chatPhase: chatLoop.chatPhase,
                    isPreparing: isFinishing,
                    messageText: $messageText,
                    isInputDisabled: isStreaming,
                    onSend: { _ in handleSend() },
                    onStop: nil,
                    showsInputActions: false,
                    allowsIcebreakers: false,
                    header: {
                        AppNavigationHeader(
                            leading: {
                                AppActionButton(
                                    icon: Iconography.Functional.Arrow.left,
                                    variant: .open,
                                    size: .medium,
                                    action: onBack
                                )
                            },
                            center: {
                                OnboardingAvatar(progress: fillProgress, size: 56)
                            }
                        )
                    }
                )
            }
            .background(colors.surface.standard.base.ignoresSafeArea())

            if didReveal, let commit {
                OnboardingRevealOverlay(
                    agent: agent,
                    digest: commit.introduction,
                    onContinue: handoff
                )
                .transition(.opacity)
            }
        }
        .animation(Animations.gentle, value: didReveal)
        .task {
            guard !didAppear else { return }
            didAppear = true
            HatchSimulation.prewarm()
            await generate(userText: nil)
        }
    }

    // MARK: - Turn handling

    private func handleSend() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        messageText = ""
        Task { await generate(userText: text) }
    }

    /// Runs one agent turn. `userText` is the user's message, or `nil` for the
    /// opening greeting.
    private func generate(userText: String?) async {
        chatError = nil

        if let userText {
            displayedMessages.append(ChatMessage(role: "user", content: userText))
            userTurns += 1
        }

        // Same contract as a normal chat: resolve per turn before spending anything.
        let routing = routingContext(model)
        let turnModel = await routedModel(for: routing, fallback: model)

        // Assess the conversation so far in parallel — drives the avatar and the
        // next turn's pacing hint. Never blocks the reply.
        if !displayedMessages.isEmpty {
            assessInBackground(model: turnModel)
        }

        chatLoop.throttler.start()

        let language = languageManager.currentLanguage.displayName
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let person = trimmedName.isEmpty ? "this person" : trimmedName
        let priorityLine = priority.map {
            "When you asked what they're hoping to get from a personal AI, they leaned "
                + "toward \($0.conversationSeed)."
        } ?? "They have not said yet what they're hoping to get from a personal AI."
        let systemPrompt = Prompt.Onboarding.chat(
            person: person,
            priorityLine: priorityLine,
            language: language
        )

        var apiMessages: [ChatMessage] = [ChatMessage(role: "system", content: systemPrompt)]
        if displayedMessages.isEmpty {
            apiMessages.append(ChatMessage(
                role: "user",
                content: "(You've just walked \(seedName) through setup — they "
                    + "shared their name and what they value. Now you meet them "
                    + "properly for the first time. Acknowledge that warmly as a "
                    + "natural continuation, say you'd like to get to know them a "
                    + "little so you can set yourself up just right for them, then "
                    + "ask your first question.)"
            ))
        } else {
            apiMessages.append(contentsOf: displayedMessages)
        }

        let hint = pacing.hint(result: lastAssessment, turnsTaken: userTurns, language: language)
        AppLogger.debug(
            "Onboarding turn \(public: userTurns) hint: \(public: hint)",
            category: .onboarding
        )
        apiMessages = appendSystemHint(hint, to: apiMessages)

        let registry = ToolRegistry.onboarding(
            agentID: agent.id,
            userName: seedName,
            canCommit: pacing.canCommit(turnsTaken: userTurns)
        ) { committed in
            commit = committed
        }
        // Nothing is said after the commit: the reveal speaks for the agent.
        chatLoop.shouldTerminate = { commit != nil }
        do {
            let routing = routingContext(turnModel)
            _ = try await chatLoop.run(
                messages: apiMessages,
                tools: registry.definitions,
                agent: agent,
                provider: provider,
                chatService: chatService,
                toolExecutor: registry,
                model: turnModel,
                routing: routing
            )
            let completed = chatLoop.completeRound()
            displayedMessages.append(contentsOf: completed)

            if commit != nil || pacing.shouldForceFinish(turnsTaken: userTurns) {
                await finishOnboarding()
            }
        } catch {
            chatError = ConnectionError(from: error)
            chatLoop.abort()
        }
    }

    private func assessInBackground(model: String) {
        let transcript = displayedMessages
        Task {
            let assessment = OnboardingAssessment(chatService: chatService)
            guard let result = try? await assessment.run(
                transcript: transcript,
                baseURL: provider.baseURL,
                providerID: provider.id,
                model: model
            ) else { return }
            lastAssessment = result
            AppLogger.debug(
                "Onboarding assessment: user \(public: result.knowsUser), identity \(public: result.knowsIdentity), pace \(public: result.pace.rawValue), readiness \(public: result.readiness)",
                category: .onboarding
            )
            withAnimation(Animations.gentle) { fillProgress = result.fillTarget }
        }
    }

    /// The turn's routing context: the agent has no store-backed context until
    /// onboarding finishes, so it is handed to the loop directly.
    private func routingContext(_ currentModel: String) -> RouteRequest {
        RouteRequest(
            currentProviderID: provider.id,
            currentModel: currentModel,
            isAuto: true,
            requirements: RouteRequirements(),
            providers: [
                RoutingProvider(
                    id: provider.id,
                    name: provider.name,
                    baseURL: provider.baseURL,
                    availableModels: provider.availableModels,
                    enabledModels: provider.enabledModels
                ),
            ]
        )
    }

    /// Resolves the route for any model spend inside onboarding - the turn, the
    /// background assessment, the hero text - so a model the router demoted
    /// stops being used everywhere, not just where it's visible.
    private func routedModel(for request: RouteRequest, fallback: String) async -> String {
        let route = await modelRouter.resolve(request)
        return route.staysOn(providerID: provider.id) ? route.model : fallback
    }

    /// Persists the onboarding conversation as the agent's first real chat, so it
    /// carries over into the app instead of being discarded.
    private func persistConversation() {
        let chat = Chat(
            agentID: agent.id,
            spaceID: nil,
            title: Localized.Onboarding.Chat.firstChatTitle
        )
        // A title that stands, like one the chat generated for itself — so
        // later turns never regenerate over it.
        chat.titleOrigin = .generated
        modelContext.insert(chat)
        for message in displayedMessages {
            let persisted = Message.from(message)
            persisted.chat = chat
            modelContext.insert(persisted)
        }
        // The chat list opens this once when the app first loads.
        PendingDestination.set(.chat(chat.id))
        Task { await seedIntents(chatID: chat.id) }
    }

    /// Seeds two starter intents for a fresh agent:
    /// one to introduce capabilities over time, one to overcome the cold start
    /// by actively getting to know the user.
    private func seedIntents(chatID: UUID) async {
        let agentID = agent.id

        // Intent content is agent instruction, not user-facing — kept verbatim.
        _ = try? await intentService.create(
            content: "Introduce \(name) to what I can do — not all at once, but find the right moment to surface each of these naturally.",
            agentID: agentID,
            spaceID: nil,
            chatID: chatID,
            tasks: [
                IntentTask(
                    content: "Introduce the idea of skills that aren't always on — specialized capabilities I can activate when a request needs them, like calendar, reminders, email, and health"
                ),
                IntentTask(
                    content: "Introduce spaces — a way to keep different parts of life separate"
                ),
                IntentTask(
                    content: "Introduce live call — hands-free conversation, works with the phone in your pocket"
                ),
                IntentTask(
                    content: "Introduce proactivity — how I can work in the background and reach out when something matters"
                ),
                IntentTask(
                    content: "Introduce providers and local models — cloud keys, offline use, and what that means for privacy"
                ),
                IntentTask(
                    content: "Help \(name) understand they can just ask — if there's something they want to know or change about the app, I can usually do it or explain it"
                ),
            ],
            events: [],
            schedules: []
        )

        _ = try? await intentService.create(
            content: Prompt.Onboarding.getToKnowIntent(name: name),
            agentID: agentID,
            spaceID: nil,
            chatID: chatID,
            tasks: [
                IntentTask(
                    content: "Find out what energizes \(name) — what they look forward to, what lights them up"
                ),
                IntentTask(content: "Understand who matters to them — the people in their life"),
                IntentTask(
                    content: "Learn what they're working toward — goals, dreams, something they haven't done yet"
                ),
                IntentTask(
                    content: "Get a sense of how they spend their time — routines, hobbies, the texture of daily life"
                ),
                IntentTask(
                    content: "Understand what's on their mind right now — what they're carrying, what's coming up"
                ),
                IntentTask(
                    content: "Learn how they like to be helped — what a gold star looks like for them"
                ),
            ],
            events: [],
            schedules: []
        )
    }

    // MARK: - Completion

    /// The turn budget ran out before the agent committed: commit with what it has.
    @MainActor
    private func finishOnboarding() async {
        guard !isFinishing else { return }
        isFinishing = true

        if commit == nil {
            let fallback = OnboardingCommit(
                name: agent.name,
                emoji: agent.emoji,
                identity: agent.identityCore,
                user: agent.userCore,
                soul: "",
                introduction: Localized.Onboarding.Reveal.fallbackIntroduction
            )
            await FinishOnboardingTool(
                userName: seedName,
                knowledgeService: knowledgeService,
                onCommit: nil
            )
            .write(fallback, to: agent)
            commit = fallback
        }
        // Fresh agents keep the reactive default; proactivity is offered in
        // conversation once there's a concrete reason to.
        agent.bootstrapComplete = true
        modelContext.insert(agent)

        // The reveal takes the whole screen; the keyboard must not sit over it.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        revealCommit()
    }

    /// Shows the hero reveal once the commit is in.
    private func revealCommit() {
        withAnimation(Animations.gentle) { didReveal = true }
    }

    /// The user tapped Continue on the reveal: persist the conversation and hand
    /// off, so it opens as the normal chat — same history, all the usual tools.
    private func handoff() {
        persistConversation()
        onComplete()
    }

    // MARK: - Helpers

    private var seedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "the user" : trimmed
    }

    /// Merges a hint into the latest user message as a `<system_hint>` block.
    private func appendSystemHint(_ hint: String, to messages: [ChatMessage]) -> [ChatMessage] {
        let block = "<system_hint>\n\(hint)\n</system_hint>"
        guard let index = messages.lastIndex(where: { $0.role == "user" }) else {
            return messages + [ChatMessage(role: "user", content: block)]
        }
        var copy = messages
        let existing = copy[index].content ?? ""
        let merged = existing.isEmpty ? block : existing + "\n\n" + block
        copy[index] = ChatMessage(role: "user", content: merged)
        return copy
    }
}
