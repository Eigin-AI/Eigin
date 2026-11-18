import Factory
import Foundation

/// Runs a single agent turn for a question dictated into the watch.
///
/// The phone is woken in the background by WatchConnectivity, answers once,
/// and delivers the reply as a notification. Unlike the live call this never
/// touches audio on the phone — the watch owns the microphone.
///
/// The question is persisted before the turn runs, so a failed turn leaves
/// the spoken question in the chat unanswered; the next turn carries it as
/// context. Only the agent's side persists on success.
@MainActor
enum WatchTurnRunner {
    /// Answers `question`, returning the agent's reply.
    ///
    /// An abandoned turn (`isAbandoned`, set when the background budget runs
    /// out) keeps its messages in the chat but yields no reply — the wrist
    /// already heard the give-up notice.
    static func run(
        question: String, isAbandoned: @escaping () -> Bool = { false }
    ) async throws -> String {
        let context = try WatchAgentContext.resolve()

        let userMessage = ChatMessage(role: "user", content: question)
        context.persist([userMessage])

        let gatekeeper = Gatekeeper(
            proactivity: context.agent.proactivity,
            knowledgeService: Container.shared.knowledgeService()
        )

        // Resolve the chat's active skills with the shared capability gate,
        // so a skill whose provider is gone doesn't claim tools the turn
        // can't supply.
        let connected = Container.shared.integrationManager()
            .connectedCapabilities(integrations: context.integrations)
        let activeSkills = SkillCatalog.activeSkills(
            for: context.chat,
            mcpServers: context.mcpServers,
            connectedCapabilities: connected
        )

        let turn = try await MessagePipeline.prepareTurn(
            messages: context.messages,
            agent: context.agent,
            space: nil,
            permissionPolicy: context.permissionPolicy,
            spaceID: nil,
            chatID: context.chat.id,
            integrations: context.integrations,
            activeSkills: activeSkills,
            gatekeeper: gatekeeper,
            // Headless mode tells the model it is answering a wrist-sized,
            // voice-transcribed question: one or two plain sentences.
            mode: .headless,
            hasSpaces: false
        )

        // PassthroughThrottler: CADisplayLink stops in the background, so the
        // turn must not depend on display ticks to drain its stream.
        let loop = AgenticChatLoop(isBootstrap: false, throttler: PassthroughThrottler())
        let produced: [ChatMessage]
        do {
            produced = try await loop.run(
                messages: turn.apiMessages,
                tools: turn.registry.definitions,
                agent: context.agent,
                provider: context.provider,
                chatService: Container.shared.chatService(),
                toolExecutor: turn.registry,
                cacheKey: context.chat.id.uuidString,
                conversationID: context.chat.id
            )
        } catch {
            context.persist(loop.buildCheckpoint())
            loop.settle()
            throw error
        }
        loop.settle()

        context.persist(produced)

        // Persists even when abandoned — the conversation keeps the context.
        // The wrist hears nothing more; the give-up notice covers the turn.
        guard !isAbandoned() else { throw CancellationError() }

        // The last assistant message is the answer; earlier rounds narrate
        // tool use and would only make a wrist notification ramble.
        let answer = produced
            .reversed()
            .first { $0.role == "assistant" && !($0.content ?? "").isEmpty }?
            .content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reply = try await WatchReplyFormatter.format(
            answer, attributionService: Container.shared.weatherAttributionService()
        )
        try Task.checkCancellation()
        guard !isAbandoned() else { throw CancellationError() }
        return reply
    }
}
