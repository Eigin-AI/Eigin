import Foundation
import SwiftData

extension RouteRequest {
    /// Describes a turn to the router, flattening the live SwiftData models.
    ///
    /// Returns nil when the agent has no context to read providers from, which leaves the
    /// caller on whatever it already had.
    ///
    /// The requirements-only flow (out-of-band routing, retry/hedge request rebuilds):
    /// no conversation and no message by default, so the router scores the turn as
    /// simple and anchors stickiness on the agent.
    @MainActor
    init?(
        agent: Agent,
        provider: Provider,
        model: String? = nil,
        requirements: RouteRequirements,
        conversationID: UUID? = nil,
        lastUserMessage: String? = nil
    ) {
        guard let context = agent.modelContext,
              let providers = try? context.fetch(FetchDescriptor<Provider>())
        else {
            return nil
        }
        self.init(
            currentProviderID: provider.id,
            currentModel: model ?? agent.model,
            isAuto: agent.autoModel,
            requirements: requirements,
            providers: providers.map(RoutingProvider.init),
            conversationID: conversationID,
            lastUserMessage: lastUserMessage
        )
    }

    /// Derives requirements from the turn's messages and hands the router the
    /// conversation ID and latest user message for complexity routing.
    ///
    /// Out-of-band routing (`AgentAutoRouting`) uses the requirements init instead.
    @MainActor
    init?(
        agent: Agent,
        provider: Provider,
        model: String? = nil,
        messages: [ChatMessage],
        conversationID: UUID?,
        lastUserMessage: String?
    ) {
        guard let context = agent.modelContext,
              let providers = try? context.fetch(FetchDescriptor<Provider>())
        else {
            return nil
        }
        self.init(
            currentProviderID: provider.id,
            currentModel: model ?? agent.model,
            isAuto: agent.autoModel,
            requirements: RouteRequirements(
                needsVision: messages.contains { $0.attachments?.isEmpty == false }
            ),
            providers: providers.map(RoutingProvider.init),
            conversationID: conversationID,
            lastUserMessage: lastUserMessage
        )
    }
}

extension RoutingProvider {
    @MainActor
    init(_ provider: Provider) {
        self.init(
            id: provider.id,
            name: provider.name,
            baseURL: provider.baseURL,
            availableModels: provider.availableModels,
            enabledModels: provider.enabledModels
        )
    }
}
