import Foundation
import SwiftData

extension AgenticChatLoop {
    /// Adapts host routing context and catalog storage for one prepared request.
    func openStream(
        chatService: ChatService, provider: Provider, agent: Agent,
        messages: [ChatMessage], tools: [ToolDefinition]?, cacheKey: String?,
        inlineToolRunner: InlineToolRunner?, routing: RouteRequest?, conversationID: UUID?
    ) async throws -> InferenceAttempt {
        let model = activeModel
        let coordinator = InferenceAttemptCoordinator(modelRouter: modelRouter)
        return try await coordinator.open(
            chatService: chatService, host: provider.baseURL, hostID: provider.id,
            model: model, messages: messages, tools: tools, cacheKey: cacheKey,
            inlineToolRunner: inlineToolRunner,
            routing: { requirements in
                routing?.forPreparedTurn(model: model, requirements: requirements) ?? RouteRequest(
                    agent: agent, provider: provider, model: model, requirements: requirements,
                    conversationID: conversationID,
                    lastUserMessage: messages.last(where: { $0.role == "user" })?.content
                )
            }, refreshCatalog: { [modelRefresher] hostID in
                guard let context = agent.modelContext,
                      let record = try? context.fetch(FetchDescriptor<Provider>())
                      .first(where: { $0.id == hostID }) else { return nil }
                let name = record.name
                let enabled = record.enabledModels
                let baseURL = record.baseURL
                guard let models = try? await modelRefresher.refresh(record, apiKeyOverride: nil)
                else { return nil }
                return RoutingProvider(
                    id: hostID,
                    name: name,
                    baseURL: baseURL,
                    availableModels: models,
                    enabledModels: enabled
                )
            }
        )
    }
}
