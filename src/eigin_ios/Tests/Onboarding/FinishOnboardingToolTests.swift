@testable import Eigin
import Factory
import Foundation
import Testing

@Suite("FinishOnboardingTool")
struct FinishOnboardingToolTests {
    private static let goodArguments: [String: String] = [
        "name": "Ford",
        "emoji": "🛰️",
        "identity": "I'm Ford, named for the long view. I keep things calm and short.",
        "user": "Who: Sam, in Copenhagen.\nHow to help: short morning rundowns.",
        "soul": "I keep mornings short — they start early.",
        "introduction": "I'm here to keep your days in order without a fuss.",
    ]

    private func call(_ arguments: [String: String]) throws -> ToolCall {
        let json = try String(decoding: JSONEncoder().encode(arguments), as: UTF8.self)
        return ToolCall(
            id: "commit",
            type: "function",
            function: .init(name: "finish_onboarding", arguments: json)
        )
    }

    @MainActor
    private func run(_ arguments: [String: String]) async throws
        -> (Agent, ToolResult, OnboardingCommit?)
    {
        let agent = Agent(name: "Eigin", providerID: UUID(), model: "test")
        let committed = Committed()
        let tool = FinishOnboardingTool(userName: "Sam", knowledgeService: nil) {
            committed.value = $0
        }
        let result = try await tool.execute(call(arguments), agent: agent)
        return (agent, result, committed.value)
    }

    @Test("a good commit writes the agent and hands over the introduction")
    @MainActor
    func commitWritesAgent() async throws {
        let (agent, result, commit) = try await run(Self.goodArguments)

        #expect(!result.isError)
        #expect(agent.name == "Ford")
        #expect(agent.emoji == "🛰️")
        #expect(agent.identityCore.hasPrefix("I'm Ford"))
        #expect(agent.userCore.contains("Copenhagen"))
        #expect(commit?.introduction == Self.goodArguments["introduction"])
    }

    @Test("the soul keeps the base values and adds the agent's own")
    @MainActor
    func soulIsComposed() async throws {
        let (agent, _, _) = try await run(Self.goodArguments)

        #expect(agent.soulCore.hasPrefix(Prompt.Onboarding.Partials.soulTemplate))
        #expect(agent.soulCore.hasSuffix("I keep mornings short — they start early."))
    }

    @Test("a commit with a missing field, an overlong core or a bad emoji writes nothing")
    @MainActor
    func badCommitIsRefused() async throws {
        var arguments = Self.goodArguments
        arguments["introduction"] = ""
        arguments["user"] = String(repeating: "a", count: 5000)
        arguments["emoji"] = "satellite"

        let (agent, result, commit) = try await run(arguments)

        #expect(result.isError)
        #expect(result.content.contains("introduction is required"))
        #expect(result.content.contains("user is 5000 characters"))
        #expect(result.content.contains("single emoji"))
        #expect(agent.name == "Eigin")
        #expect(agent.userCore.isEmpty)
        #expect(commit == nil)
    }

    @Test("the onboarding turn ends on the commit, with nothing said after it")
    @MainActor
    func turnEndsOnCommit() async throws {
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        let agent = Agent(name: "Eigin", providerID: UUID(), model: "test")
        let provider = Provider(name: "Test", baseURL: "https://fake.local")
        let service = FakeChatService()
        try service.enqueueEventStreams([
            [.toolCall(call(Self.goodArguments)), .finished(.toolCalls)],
            [.contentDelta("All set, I'm Ford!"), .finished(.stop)],
        ])
        let committed = Committed()
        let registry = ToolRegistry
            .onboarding(agentID: agent.id, userName: "Sam") { committed.value = $0 }
        let loop = AgenticChatLoop(isBootstrap: true)
        loop.shouldTerminate = { committed.value != nil }

        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Ford it is")],
            tools: registry.definitions,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: registry
        )

        #expect(produced.map(\.role) == ["assistant", "tool"])
        #expect(!produced.contains { $0.content?.contains("All set") == true })
        #expect(committed.value?.name == "Ford")
    }

    @Test("a conversation ending on a commit awaits the agent's reply")
    func commitAwaitsReply() throws {
        let commitCall = try call(Self.goodArguments)
        let messages = [
            ChatMessage(role: "user", content: "Ford sounds great"),
            ChatMessage(role: "assistant", content: nil, toolCalls: [commitCall]),
            ChatMessage(
                role: "tool",
                content: "{\"result\":{\"status\":\"committed\"}}",
                toolCallID: "commit"
            ),
        ]

        #expect(FinishOnboardingTool.isUnansweredCommit(messages))
        #expect(!FinishOnboardingTool.isUnansweredCommit(messages + [ChatMessage(
            role: "assistant",
            content: "Hi"
        )]))
        #expect(!FinishOnboardingTool.isUnansweredCommit([ChatMessage(
            role: "user",
            content: "Hi"
        )]))
    }

    @Test("a failed commit is not answered either")
    func failedCommitIsNotUnanswered() {
        let messages = [
            ChatMessage(role: "user", content: "Ford sounds great"),
            ChatMessage(
                role: "assistant",
                content: nil,
                toolCalls: [ToolCall(
                    id: "commit",
                    type: "function",
                    function: .init(name: "finish_onboarding", arguments: "{\"name\":\"Ford\"")
                )]
            ),
            ChatMessage(
                role: "tool",
                content: "{\"errors\":[\"This field is required: emoji.\"]}",
                toolCallID: "commit"
            ),
        ]

        #expect(!FinishOnboardingTool.isUnansweredCommit(messages))
    }
}

/// Holds what the tool hands over, so a test can read it back.
@MainActor
private final class Committed {
    var value: OnboardingCommit?
}
