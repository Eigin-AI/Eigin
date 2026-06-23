import Factory
import SwiftUI

struct SpaceBootstrapView: View {
    @Environment(\.colors) private var colors
    @Injected(\.chatService) private var chatService
    @Injected(\.voiceService) private var voiceService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Injected(\.languageManager) private var languageManager

    let agent: Agent
    let provider: Provider

    @State private var messageText = ""
    @State private var displayMessages: [ChatMessage] = []
    @State private var chatLoop = AgenticChatLoop(isBootstrap: true)
    @State private var streamTask: Task<Void, Never>?
    @State private var chatError: ConnectionError?
    @State private var didAppear = false
    @State private var showFinishButton = false
    @State private var backgroundGuard: BackgroundTaskGuard?

    private var isStreaming: Bool {
        chatLoop.phase == .waiting || chatLoop.phase == .streaming
    }

    @State private var doneCalled = false

    private var exchangeCount: Int {
        displayMessages.count(where: { $0.role == "user" })
    }

    private var canFinish: Bool {
        !isStreaming && (doneCalled || exchangeCount >= 8)
    }

    private var chatItems: [ChatItem] {
        ChatItem.buildItems(
            from: displayMessages + chatLoop.committedMessages, chatLoop: chatLoop,
            chatError: chatError
        )
    }

    private var stopHandler: (() -> Void)? {
        isStreaming ? { handleStop() } : nil
    }

    var body: some View {
        ChatFeed(
            items: chatItems,
            throttler: chatLoop.throttler,
            splitter: chatLoop.splitter,
            messageText: $messageText,
            isInputDisabled: isStreaming,
            onSend: { _ in send() },
            onStop: stopHandler,
            lastStreamedItemID: chatLoop.lastStreamedItemID
        )
        .safeAreaInset(edge: .bottom, spacing: Spacing.n8) {
            if showFinishButton {
                Button {
                    finishSetup()
                } label: {
                    Text(Localized.Space.Bootstrap.finishSetup)
                        .typography(Typography.titleXS)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
                .padding(.horizontal)
                .padding(.bottom, Spacing.n8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0), value: showFinishButton)
        .navigationTitle(Localized.Space.Bootstrap.title, style: Typography.titleXl)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            sendInitialGreeting()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, isStreaming {
                beginBackgroundGrace()
            }
            if newPhase == .active {
                endBackgroundGrace()
            }
        }
        .onChange(of: canFinish) { _, newValue in
            if newValue, !showFinishButton {
                showFinishButton = true
            }
        }
    }

    private func handleStop() {
        endBackgroundGrace()
        let checkpoint = chatLoop.stop()
        displayMessages.append(contentsOf: checkpoint)
        chatLoop.settle()
        chatError = nil
        streamTask?.cancel()
    }

    private func beginBackgroundGrace() {
        guard isStreaming, backgroundGuard == nil else { return }
        backgroundGuard = BackgroundTaskGuard { [self] in
            handleStop()
        }
        backgroundGuard?.begin()
    }

    private func endBackgroundGrace() {
        backgroundGuard?.end()
        backgroundGuard = nil
    }

    private func sendInitialGreeting() {
        chatError = nil
        let messages = [
            ChatMessage(
                role: "system",
                content: Prompt.Space.interview(
                    name: agent.name,
                    emoji: agent.emoji,
                    identity: agent.identityCore,
                    soul: agent.soulCore,
                    user: agent.userCore,
                    language: languageManager.currentLanguage.displayName
                )
            ),
            ChatMessage(role: "user", content: "I'd like to create a new space."),
        ]

        let voiceNames = voiceService.recommendedVoices.map(\.name)
        let registry = ToolRegistry.spaceBootstrap(
            voiceNames: voiceNames,
            onDone: { Task { @MainActor in doneCalled = true } }
        )

        streamTask = Task {
            defer { self.endBackgroundGrace() }
            do {
                _ = try await chatLoop.run(
                    messages: messages,
                    tools: registry.definitions,
                    agent: agent,
                    provider: provider,
                    chatService: chatService,
                    toolExecutor: registry
                )
                let completed = chatLoop.completeRound()
                displayMessages.append(contentsOf: completed)
            } catch {
                chatError = ConnectionError(from: error)
                chatLoop.abort()
            }
        }
    }

    private func send() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: "user", content: text)
        displayMessages.append(userMessage)
        messageText = ""
        chatError = nil

        let apiMessages = buildAPIMessages()
        let voiceNames = voiceService.recommendedVoices.map(\.name)
        let registry = ToolRegistry.spaceBootstrap(
            voiceNames: voiceNames,
            onDone: { Task { @MainActor in doneCalled = true } }
        )

        streamTask = Task {
            defer { self.endBackgroundGrace() }
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
                displayMessages.append(contentsOf: completed)
            } catch {
                chatError = ConnectionError(from: error)
                chatLoop.abort()
            }
        }
    }

    private func buildAPIMessages() -> [ChatMessage] {
        var messages: [ChatMessage] = [
            ChatMessage(
                role: "system",
                content: Prompt.Space.interview(
                    name: agent.name,
                    emoji: agent.emoji,
                    identity: agent.identityCore,
                    soul: agent.soulCore,
                    user: agent.userCore,
                    language: languageManager.currentLanguage.displayName
                )
            ),
            ChatMessage(role: "user", content: "I'd like to create a new space."),
        ]
        messages.append(contentsOf: displayMessages)
        return messages
    }

    private func finishSetup() {
        Haptics.light()
        dismiss()
    }
}
