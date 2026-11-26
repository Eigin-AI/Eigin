import Foundation
import SwiftData

extension AgenticChatLoop {
    /// Refreshes host inventory while the SDK retains dispatch and replacement ownership.
    func catalogRefresh(agent: Agent) -> @MainActor @Sendable (UUID) async -> RoutingProvider? {
        { [modelRefresher] hostID in
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
    }
}
