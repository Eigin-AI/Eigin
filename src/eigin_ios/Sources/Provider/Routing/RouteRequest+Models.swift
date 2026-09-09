import Foundation
import SwiftData

extension RouteRequest {
    /// Describes a turn to the router, flattening the live SwiftData models.
    ///
    /// Returns nil when the agent has no context to read providers from, which leaves the
    /// caller on whatever it already had.
    @MainActor
    init?(
        agent: Agent,
        provider: Provider,
        model: String? = nil,
        requirements: RouteRequirements
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
            providers: providers.map(RoutingProvider.init)
        )
    }

    /// Derives the requirements from the turn's messages.
    @MainActor
    init?(agent: Agent, provider: Provider, model: String? = nil, messages: [ChatMessage]) {
        self.init(
            agent: agent,
            provider: provider,
            model: model,
            requirements: RouteRequirements(
                needsVision: messages.contains { $0.attachments?.isEmpty == false }
            )
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
