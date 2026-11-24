import EiginSDK
import Foundation

extension DefaultModelRouter {
    /// Supplies local availability while the SDK chooses the transient route.
    func offlineRoute(for request: RouteRequest, at timestamp: Date) -> ResolvedRoute? {
        let current = request.currentProvider
        let local = request.providers.first(where: \.isLocal)
        let input = EiginSDK.Experimental.Routing.OfflineInput(
            automatic: request.isAuto,
            currentProviderIsCloud: current.map { !$0.isLocal } ?? false,
            localReady: localModelReadiness(),
            localInventory: local.map {
                EiginSDK.Experimental.Routing.Inventory(
                    providerId: $0.id.uuidString, baseUrl: $0.baseURL,
                    available: $0.availableModels, enabled: $0.enabledModels, models: []
                )
            }
        )
        guard let route = policy.offlineRoute(input: input, now: timestamp.timeIntervalSince1970),
              let providerID = UUID(uuidString: route.providerId)
        else { return nil }
        return ResolvedRoute(
            providerID: providerID, baseURL: route.baseUrl, model: route.model,
            change: .offlineFallback(previousProvider: current?.name ?? "")
        )
    }
}
