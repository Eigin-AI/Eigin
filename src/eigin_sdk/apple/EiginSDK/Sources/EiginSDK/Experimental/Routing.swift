import EiginSDKBindings

public extension EiginSDK.Experimental {
    /// Stateful cloud and offline routing, independent of discovery, persistence, and stream dispatch.
    enum Routing {
        /// Retain one handle across turns; separate handles have isolated health and affinity.
        public typealias Router = EiginSDKBindings.ModelRouter
        public typealias OfflineInput = RoutingOfflineInput
        public typealias OfflineRoute = RoutingOfflineRoute
        public typealias Request = RoutingRequest
        public typealias Inventory = RoutingInventory
        public typealias Model = RoutingModel
        public typealias Requirements = RoutingRequirements
        public typealias Decision = RoutingDecision
        public typealias Change = RoutingChange
        public typealias Degradation = RoutingDegradation
        public typealias Failure = RoutingFailure
        public typealias Outcome = RoutingOutcome
        public typealias Result = RoutingResult
        public typealias HealthSample = RoutingHealthSample
        public typealias RemoteHealth = RoutingRemoteHealth

        /// Resolves supplied IDs through the SDK catalog and verified endpoint policy.
        public static func modelFacts(_ ids: [String], baseURL: String) -> [Model] {
            routingModelFacts(modelIds: ids, baseUrl: baseURL)
        }
    }
}
