import Factory
import Foundation

/// Commits onboarding in one call: the agent's name and emoji, its core texts,
/// its actor entries in the knowledge graph, and the line it introduces itself
/// with. The onboarding turn ends here; the real chat answers the result once
/// the user has seen the reveal.
struct FinishOnboardingTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "finish_onboarding",
        displayName: Localized.Tools.System.finishOnboarding,
        description: Localized.Tools.Description.finishOnboarding,
        defaultPermissionLevel: .always, category: .agent, isUserConfigurable: false
    )

    let name = "finish_onboarding"
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    /// The user's name, for their actor entry.
    let userName: String
    let knowledgeService: (any KnowledgeService)?
    /// Receives the commit once it is written.
    let onCommit: (@MainActor @Sendable (OnboardingCommit) -> Void)?

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: Prompt.Onboarding.finish,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "name": .init(type: "string", description: "Your name."),
                    "emoji": .init(
                        type: "string",
                        description: "A single emoji that represents you."
                    ),
                    "identity": .init(
                        type: "string",
                        description: Prompt.Onboarding.Partials.identityShape
                    ),
                    "user": .init(
                        type: "string",
                        description: Prompt.Onboarding.Partials.userShape
                    ),
                    "soul": .init(
                        type: "string",
                        description: Prompt.Onboarding.Partials.soulShape
                    ),
                    "introduction": .init(
                        type: "string",
                        description: Prompt.Onboarding.Partials.introductionShape
                    ),
                ],
                required: ["name", "emoji", "identity", "user", "soul", "introduction"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id
        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }
        let commit: OnboardingCommit
        switch OnboardingCommit.parse(args) {
        case .success(let parsed): commit = parsed
        case .failure(let errors):
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(errors: errors.messages + ["Fix these and call again."]),
                isError: true
            )
        }

        await write(commit, to: agent)
        onCommit?(commit)

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "status": "committed",
                "next": Prompt.Onboarding.committed,
            ]),
            isError: false
        )
    }

    /// Writes a commit onto the agent and into the knowledge graph.
    @MainActor func write(_ commit: OnboardingCommit, to agent: Agent) async {
        agent.name = commit.name
        agent.emoji = commit.emoji
        agent.identityCore = commit.identity
        agent.userCore = commit.user
        agent.soulCore = commit.composedSoul
        agent.updatedAt = .now
        seedVocabulary(userName: userName)
        await seedActors(agentName: commit.name)
    }

    /// Seeds the user's name — said often, misrecognized often. The agent's
    /// own name is always included by ``VocabularyStore/entries(agentName:)``.
    private func seedVocabulary(userName: String) {
        let trimmed = userName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Container.shared.vocabularyStore().addWords([trimmed])
    }

    /// The user and the agent as actors, so knowledge has someone to be about.
    private func seedActors(agentName: String) async {
        guard let knowledgeService else { return }
        let now = LocalDateFormatter.iso8601String(from: Date())
        let user = FirmEntity(
            id: BundledKnowledge.userActorID,
            entityType: "actor",
            fields: [
                FirmField(name: "name", value: .string(value: userName)),
                FirmField(name: "type", value: .enum(value: "human")),
                FirmField(name: "created_at", value: .dateTime(value: now)),
            ]
        )
        let agent = FirmEntity(
            id: BundledKnowledge.agentActorID,
            entityType: "actor",
            fields: [
                FirmField(name: "name", value: .string(value: agentName)),
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
            try await knowledgeService.addEntity(user, spaceID: nil, agentID: nil, chatID: nil)
            try await knowledgeService.addEntity(agent, spaceID: nil, agentID: nil, chatID: nil)
        } catch {
            AppLogger.error(
                "Failed to seed actor entries: \(private: error.localizedDescription)",
                category: .onboarding
            )
        }
    }
}

extension FinishOnboardingTool {
    /// Whether a conversation ends on a commit the agent hasn't answered yet:
    /// the cue for the real chat to open with the agent speaking first. No user
    /// or agent message has come after the commit's tool result.
    static func isUnansweredCommit(_ messages: [ChatMessage]) -> Bool {
        guard let last = messages.last, last.role == "tool", let callID = last.toolCallID,
              let call = messages.last(where: { $0.role == "assistant" })?.toolCalls?
              .first(where: { $0.id == callID }),
              call.function.name == FinishOnboardingTool.capability.key,
              let content = last.content,
              let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any]
        else { return false }
        // Only a written commit carries a result; failures come back as errors.
        return result["status"] as? String == "committed"
    }
}
