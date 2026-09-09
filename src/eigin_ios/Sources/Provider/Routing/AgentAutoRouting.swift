import Factory
import SwiftData

/// Force-resolves an auto agent's model when its *config* changes, not only when the
/// next turn asks for a route.
///
/// Routing normally runs once per turn, during ``ChatViewModel/applyRoute``. But the
/// agent's model is also read the moment the user opens the picker or glances at the
/// profile — and config can change between turns: the user switches provider, or
/// toggles a model off (sometimes the very model the router is currently on). Without
/// a forced resolve, the Auto row advertises — and the next turn starts on — a model
/// the user just switched off, or one that no longer belongs to the new provider.
///
/// This runs the same ``DefaultModelRouter/resolve(_:)`` path as a turn, with default
/// requirements (no pending messages), and writes the result back the same way:
/// only routes that stay on the agent's own provider persist, so an offline detour
/// never overwrites the user's choice.
@MainActor
enum AgentAutoRouting {
    /// Force-resolves `agent`'s model against its current provider and config.
    static func forceResolve(agent: Agent) async {
        guard agent.autoModel,
              let context = agent.modelContext,
              let providers = try? context.fetch(FetchDescriptor<Provider>()),
              let provider = providers.first(where: { $0.id == agent.providerID }),
              let request = RouteRequest(
                  agent: agent, provider: provider, requirements: RouteRequirements()
              )
        else { return }
        let route = await Container.shared.modelRouter().resolve(request)
        // Persist only routes that stay on the user's provider; an offline detour is
        // transient and must not overwrite the chosen model, matching applyRoute.
        guard route.staysOn(providerID: provider.id) else { return }
        agent.model = route.model
    }

    /// Force-resolves every auto agent on `provider`. Used by the enablement toggles,
    /// which edit a provider and may affect several agents that run on it.
    static func forceResolveAgents(on provider: Provider) async {
        guard let context = provider.modelContext else { return }
        let providerID = provider.id
        let agents = (try? context.fetch(
            FetchDescriptor<Agent>(predicate: #Predicate { $0.providerID == providerID })
        )) ?? []
        for agent in agents where agent.autoModel {
            await forceResolve(agent: agent)
        }
    }
}
