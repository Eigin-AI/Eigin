@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("Mistral reasoning routing", .serialized)
@MainActor
struct MistralReasoningRoutingTests {
    @Test func retryToOriginModelReplaysHistoryKeptThroughPreparation() async throws {
        let store = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let provider = Provider(name: "Mistral", baseURL: "https://api.mistral.ai/v1")
        let originModel = "mistral-large-4-0"
        let initialModel = "mistral-medium-3-5"
        provider.availableModels = [initialModel, originModel]
        let agent = Agent(name: "Test", providerID: provider.id, model: initialModel)
        agent.bootstrapComplete = true
        store.mainContext.insert(provider)
        store.mainContext.insert(agent)
        let knowledge = FakeKnowledgeService()
        Container.shared.modelContainer.register { store }
        Container.shared.knowledgeService.register { knowledge }
        Container.shared.intentService.register { PreviewIntentService() }
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(),
            localModelReadiness: { false }
        )
        Container.shared.modelRouter.register { router }
        defer {
            Container.shared.modelRouter.reset()
            Container.shared.intentService.reset()
            Container.shared.knowledgeService.reset()
            Container.shared.modelContainer.reset()
        }
        let history = try MistralReasoningHistory(
            origin: ReasoningOrigin(
                providerID: provider.id,
                endpoint: provider.baseURL,
                model: originModel
            ),
            parts: [
                MistralContentPart(
                    type: "thinking",
                    thinking: [.text("retained private reasoning")]
                ),
                .text("Prior answer"),
            ]
        ).stored()
        let prepared = try await MessagePipeline.prepareTurn(
            messages: [
                ChatMessage(role: "user", content: "First"),
                ChatMessage(
                    role: "assistant",
                    content: "Prior answer",
                    reasoningHistory: history
                ),
                ChatMessage(role: "user", content: "Continue"),
            ],
            agent: agent, model: initialModel, space: nil,
            permissionPolicy: AgentPermissionPolicy(
                builtInGrants: [:],
                discoveredGrants: [:],
                chatGrants: [],
                canPromptUser: false
            ),
            spaceID: nil, gatekeeper: Gatekeeper(
                proactivity: .reactive,
                knowledgeService: knowledge
            ),
            mode: .text, hasSpaces: false, needsCompaction: false
        )
        #expect(prepared.estimatedTokens == TokenEstimator.estimateRequest(
            messages: prepared.apiMessages.map { $0.reasoningScoped(to: nil) },
            toolDefinitions: prepared.registry.definitions
        ))
        let url = provider.baseURL + "/chat/completions"
        FakeURLProtocol.enqueueResponse(for: url, data: Data("unavailable".utf8), statusCode: 503)
        FakeURLProtocol.enqueueResponse(
            for: url,
            data: Data(
                "data: {\"choices\":[{\"delta\":{\"content\":\"Answer\"},\"finish_reason\":\"stop\"}]}\n\n"
                    .utf8
            ),
            statusCode: 200
        )
        let loop = AgenticChatLoop(isBootstrap: false)
        loop.activeModel = initialModel
        let routing = RouteRequest(
            currentProviderID: provider.id, currentModel: initialModel, isAuto: true,
            requirements: RouteRequirements(),
            providers: [RoutingProvider(
                id: provider.id,
                name: provider.name,
                baseURL: provider.baseURL,
                availableModels: provider.availableModels
            )]
        )
        let turn = try await loop.openStream(
            chatService: ReasoningHTTPChatService(), provider: provider, agent: agent,
            messages: prepared.apiMessages, tools: nil, cacheKey: nil, routing: routing
        )
        for try await _ in turn.stream {}
        let body = try #require(FakeURLProtocol.lastRequestBody(for: url))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == originModel)
        let messages = try #require(json["messages"] as? [[String: Any]])
        let assistant = try #require(messages.first { $0["role"] as? String == "assistant" })
        let parts = try #require(assistant["content"] as? [[String: Any]])
        #expect((parts.first?["thinking"] as? [[String: String]])?
            .first?["text"] == "retained private reasoning")
    }
}

/// Runs real HTTP serialization and decoding against the URLSession test boundary.
private struct ReasoningHTTPChatService: ChatService {
    func chatCompletionStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await OpenAICompatibleClient(
            baseURL: baseURL,
            apiToken: "test",
            session: FakeURLProtocol.fakeSession(),
            providerID: providerID
        )
        .chatCompletionStream(messages: messages, model: model)
    }

    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey: String?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        try await OpenAICompatibleClient(
            baseURL: baseURL,
            apiToken: "test",
            session: FakeURLProtocol.fakeSession(),
            providerID: providerID
        )
        .chatCompletionEventStream(
            messages: messages,
            model: model,
            tools: tools,
            cacheKey: cacheKey
        )
    }
}
