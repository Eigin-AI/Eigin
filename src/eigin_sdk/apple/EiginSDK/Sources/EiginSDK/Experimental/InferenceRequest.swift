import EiginSDKBindings
import Foundation

public extension EiginSDK.Experimental.Inference {
    typealias RequestFailure = EiginSDKBindings.RequestError
    typealias RequestReport = EiginSDKBindings.RequestReport
    typealias RequestSelection = EiginSDKBindings.RequestSelection
    typealias RequestEffort = CatalogReasoningEffort

    /// An opened platform candidate. Cancellation must stop its native work.
    struct RequestSession: Sendable {
        public let next: @Sendable () async throws -> Event?
        public let cancel: @Sendable () -> Void

        public init(next: @escaping @Sendable () async throws -> Event?, cancel: @escaping @Sendable () -> Void) {
            self.next = next
            self.cancel = cancel
        }
    }

    /// Platform effects for one prepared request. Rust owns routing and continuation decisions.
    struct RequestServices: Sendable {
        public let validate: @Sendable (String) async throws -> Void
        public let open: @Sendable (String, RequestEffort?) async throws -> RequestSession
        public let refreshCatalog: @Sendable (String) async -> EiginSDK.Experimental.Routing.Inventory?
        public let refreshHealth: @Sendable (String) async -> [EiginSDK.Experimental.Routing.RemoteHealth]
        public let reported: @Sendable (RequestReport?, EiginSDK.Experimental.Routing.Result) -> Void
        public let now: @Sendable () -> Date

        public init(
            validate: @escaping @Sendable (String) async throws -> Void,
            open: @escaping @Sendable (String, RequestEffort?) async throws -> RequestSession,
            refreshCatalog: @escaping @Sendable (String) async -> EiginSDK.Experimental.Routing.Inventory? = { _ in nil },
            refreshHealth: @escaping @Sendable (String) async -> [EiginSDK.Experimental.Routing.RemoteHealth] = { _ in [] },
            reported: @escaping @Sendable (RequestReport?, EiginSDK.Experimental.Routing.Result) -> Void = { _, _ in },
            now: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.validate = validate
            self.open = open
            self.refreshCatalog = refreshCatalog
            self.refreshHealth = refreshHealth
            self.reported = reported
            self.now = now
        }
    }

    /// One prepared inference request, including SDK-owned hedging and replacement.
    final class Request: Sendable {
        private let operation: InferenceRequestOperation

        private init(_ operation: InferenceRequestOperation) {
            self.operation = operation
        }

        /// Retain the supplied router across turns; services are scoped to this request.
        public static func start(
            router: EiginSDK.Experimental.Routing.Router,
            providerID: String, model: String, local: Bool,
            routing: EiginSDK.Experimental.Routing.Request?, services: RequestServices
        ) async throws -> Request {
            let operation = InferenceRequestOperation(
                router: router, host: RequestHostAdapter(services: services),
                providerId: providerID, model: model, local: local, routing: routing
            )
            do {
                try await withCancellation(cancel: { operation.cancel() }, mapError: requestConsumerError) {
                    try await operation.open()
                }
                return Request(operation)
            } catch {
                operation.cancel()
                throw error
            }
        }

        deinit { operation.cancel() }

        public func next() async throws -> Event? {
            try await withCancellation(cancel: { self.operation.cancel() }, mapError: requestConsumerError) {
                try await self.operation.next()
            }
        }

        public func cancel() {
            operation.cancel()
        }

        /// Call after the turn accepts the event into its round.
        public func observeOutput(_ event: Event) throws {
            try operation.observeOutput(event: event)
        }

        public func selection() throws -> RequestSelection {
            try operation.selection()
        }

        public func report(_ result: EiginSDK.Experimental.Routing.Result) throws -> RequestReport? {
            try operation.report(result: result)
        }
    }
}

func requestHostError(_ error: any Error) -> RequestError {
    if error is CancellationError { return .Inference(.Cancelled) }
    if let error = error as? RequestError { return error }
    if let error = error as? InferenceError { return .Inference(error) }
    return .Inference(.InvalidData(reason: error.localizedDescription))
}

func requestConsumerError(_ error: any Error) -> any Error {
    if let error = error as? RequestError {
        switch error {
        case .Inference(.Cancelled), .Classified(.Cancelled, _): return CancellationError()
        default: break
        }
    }
    return error
}
