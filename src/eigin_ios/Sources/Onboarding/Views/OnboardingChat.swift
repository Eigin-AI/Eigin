import Factory
import SwiftData
import SwiftUI

/// The onboarding conversation: a restricted, real agent chat.
///
/// The agent opens already knowing the user's name and priority, gets to know
/// them, and records what it learns into its core documents via tools. A
/// side-channel ``OnboardingAssessment`` runs in parallel each turn to drive the
/// avatar's fill and pace the agent through ``OnboardingPacing`` hints. When the
/// agent has proposed its own identity and called `done` — or the turn budget is
/// spent — onboarding finishes and the reveal begins.
struct OnboardingChat: View {
    @Environment(\.colors) private var colors
    @Environment(\.modelContext) private var modelContext
    @Injected(\.chatService) private var chatService
    @Injected(\.languageManager) private var languageManager
    @Injected(\.knowledgeService) private var knowledgeService
    @Injected(\.intentService) private var intentService

    let provider: Provider
    let model: String
    let name: String
    let priority: OnboardingPriority?
    let proactivity: ProactivityLevel
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
    @State private var fillProgress = OnboardingStep.initiative.avatarProgress
    @State private var lastAssessment = OnboardingAssessment.Result.empty
    @State private var revealDigest: String?
    @AppStorage(StorageKey.pendingOnboardingChat) private var pendingOnboardingChat: String?

    private let pacing = OnboardingPacing()

    init(
        provider: Provider,
        model: String,
        name: String,
        priority: OnboardingPriority?,
        proactivity: ProactivityLevel,
        onComplete: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.provider = provider
        self.model = model
        self.name = name
        self.priority = priority
        self.proactivity = proactivity
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

                ChatFeed(
                    items: chatItems,
                    throttler: chatLoop.throttler,
                    splitter: chatLoop.splitter,
                    messageText: $messageText,
                    isInputDisabled: isStreaming,
                    onSend: { _ in handleSend() },
                    onStop: nil,
                    showsInputActions: false,
                    allowsIcebreakers: false,
                    lastStreamedItemID: chatLoop.lastStreamedItemID
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: Spacing.n16)
                }
            }
            .background(colors.surface.standard.base.ignoresSafeArea())

            if let digest = revealDigest {
                OnboardingRevealOverlay(
                    agent: agent,
                    digest: digest,
                    onContinue: handoff
                )
                .transition(.opacity)
            }
        }
        .animation(Animations.gentle, value: revealDigest != nil)
        .task {
            guard !didAppear else { return }
            didAppear = true
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

        // Assess the conversation so far in parallel — drives the avatar and the
        // next turn's pacing hint. Never blocks the reply.
        if !displayedMessages.isEmpty {
            assessInBackground()
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
        apiMessages = appendSystemHint(hint, to: apiMessages)

        let registry = ToolRegistry.onboarding(agentID: agent.id)
        do {
            _ = try await chatLoop.run(
                messages: apiMessages,
                tools: registry.definitions,
                agent: agent,
                provider: provider,
                chatService: chatService,
                toolExecutor: registry
            )
            let completed = chatLoop.completeRound()
            displayedMessages.append(contentsOf: completed)

            if calledDone(in: completed) || pacing.shouldForceFinish(turnsTaken: userTurns) {
                await finishOnboarding()
            }
        } catch {
            chatError = ConnectionError(from: error)
            chatLoop.abort()
        }
    }

    private func assessInBackground() {
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
            withAnimation(Animations.gentle) { fillProgress = result.fillTarget }
        }
    }

    /// Persists the onboarding conversation as the agent's first real chat, so it
    /// carries over into the app instead of being discarded.
    private func persistConversation() {
        let chat = Chat(
            agentID: agent.id,
            spaceID: nil,
            title: Localized.Onboarding.Chat.firstChatTitle
        )
        chat.titleOrigin = .seeded
        modelContext.insert(chat)
        for message in displayedMessages {
            let persisted = Message.from(message)
            persisted.chat = chat
            modelContext.insert(persisted)
        }
        // The chat list opens this once when the app first loads.
        pendingOnboardingChat = chat.id.uuidString
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
                    content: "Introduce the idea of skills — specialized capabilities I can activate, like scheduling, web, health, food tracking, and location awareness"
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
            content: "Get to know \(name) from scratch — be curious, ask questions, and build a real picture of who they are. Update knowledge as I learn. Resolve this once I have a solid foundation.",
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

    private func calledDone(in messages: [ChatMessage]) -> Bool {
        messages.contains { message in
            message.toolCalls?.contains { $0.function.name == DoneTool().name } ?? false
        }
    }

    // MARK: - Completion

    @MainActor
    private func finishOnboarding() async {
        guard !isFinishing else { return }
        isFinishing = true

        if agent.soulCore.isEmpty {
            agent.soulCore = Prompt.Onboarding.Partials.soulTemplate
        }
        // Carry over the initiative choice the user made during setup; the
        // agent is created reactive by default.
        agent.proactivity = proactivity
        agent.bootstrapComplete = true
        modelContext.insert(agent)

        await seedActorEntries()

        let heroCall = HeroTextGenerationCall(chatService: chatService)
        let heroText = try? await heroCall.run(
            identityCore: agent.identityCore,
            userCore: agent.userCore,
            soulCore: agent.soulCore,
            language: languageManager.currentLanguage,
            baseURL: provider.baseURL,
            providerID: provider.id,
            model: model
        )

        revealDigest = heroText ?? Localized.Onboarding.Welcome.description
    }

    /// The user tapped Continue on the reveal: persist the conversation and hand
    /// off, so it opens as the normal chat — same history, all the usual tools.
    private func handoff() {
        persistConversation()
        onComplete()
    }

    private func seedActorEntries() async {
        let now = LocalDateFormatter.iso8601String(from: Date())

        let userActor = FirmEntity(
            id: BundledKnowledge.userActorID,
            entityType: "actor",
            fields: [
                FirmField(name: "name", value: .string(value: seedName)),
                FirmField(name: "type", value: .enum(value: "human")),
                FirmField(name: "created_at", value: .dateTime(value: now)),
            ]
        )

        let agentActor = FirmEntity(
            id: BundledKnowledge.agentActorID,
            entityType: "actor",
            fields: [
                FirmField(name: "name", value: .string(value: agent.name)),
                FirmField(name: "type", value: .enum(value: "ai")),
                FirmField(name: "created_at", value: .dateTime(value: now)),
                FirmField(name: "relates_to", value: .list(items: [
                    .entityReference(entityId: BundledKnowledge.userActorID),
                ])),
                FirmField(name: "uses", value: .list(items: [
                    .entityReference(entityId: BundledKnowledge.eiginThingID),
                ])),
            ]
        )

        do {
            try await knowledgeService.addEntity(userActor, spaceID: nil, agentID: nil, chatID: nil)
            try await knowledgeService.addEntity(
                agentActor,
                spaceID: nil,
                agentID: nil,
                chatID: nil
            )
        } catch {
            AppLogger.error(
                "Failed to seed actor entries: \(private: error.localizedDescription)",
                category: .onboarding
            )
        }
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
