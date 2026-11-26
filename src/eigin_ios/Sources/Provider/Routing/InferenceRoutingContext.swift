import EiginSDK
import Foundation

/// Shared SDK policy and host observations for one prepared inference request.
struct InferenceRoutingContext: Sendable {
    let policy: EiginSDK.Experimental.Routing.Router
    let now: @Sendable () -> Date
    let health: @Sendable (RoutingProvider) async -> [EiginSDK.Experimental.Routing.RemoteHealth]
}

extension DefaultModelRouter {
    func inferenceContext() -> InferenceRoutingContext {
        InferenceRoutingContext(policy: policy, now: now, health: { [remoteHealthSource] provider in
            await RoutingSDKConversion.remote(remoteHealthSource?.health(for: provider) ?? [:])
        })
    }
}
