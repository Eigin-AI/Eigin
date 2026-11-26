import EiginSDK
import Foundation

/// Value mapping between app routing inputs and the SDK policy.
enum RoutingSDKConversion {
    typealias SDK = EiginSDK.Experimental.Routing

    static func request(_ value: RouteRequest) -> SDK.Request {
        SDK.Request(
            providerId: value.currentProviderID.uuidString,
            currentModel: value.currentModel,
            automatic: value.isAuto,
            conversationId: value.conversationID?.uuidString,
            messageNeedsReasoning: value.messageNeedsReasoning,
            requirements: SDK.Requirements(
                needsTools: value.requirements.needsToolCalling,
                needsVision: value.requirements.needsVision,
                promptTokens: value.requirements.promptTokens.map(Int64.init)
            ),
            inventory: value.currentProvider.map(inventory)
        )
    }

    static func inventory(_ provider: RoutingProvider) -> SDK.Inventory {
        SDK.Inventory(
            providerId: provider.id.uuidString,
            baseUrl: provider.baseURL,
            available: provider.availableModels,
            enabled: provider.enabledModels,
            models: []
        )
    }

    static func route(_ value: SDK.Decision, request: RouteRequest) -> ResolvedRoute {
        ResolvedRoute(
            providerID: request.currentProviderID,
            baseURL: request.currentProvider?.baseURL ?? "",
            model: value.model,
            change: value.change.map(change)
        )
    }

    static func change(_ value: SDK.Change) -> RouteChange {
        switch value {
        case .modelRetired(let previous): .modelRetired(previous: previous)
        case .modelDegraded(let previous, let reason):
            .modelDegraded(previous: previous, reason: degradation(reason))
        case .sessionReset(let previous): .sessionReset(previous: previous)
        case .steppedUp(let previous): .steppedUp(previous: previous)
        }
    }

    static func degradation(_ value: SDK.Degradation) -> DegradationReason {
        switch value {
        case .errors: .errors
        case .slowFirstToken: .slowFirstToken
        case .slowThroughput: .slowThroughput
        }
    }

    static func failure(_ value: RoutingFailure) -> SDK.Failure {
        switch value {
        case .modelNotFound: .modelNotFound
        case .providerOverloaded: .providerOverloaded
        case .offline: .offline
        case .notTheModelsFault: .notTheModelsFault
        case .timedOut: .timedOut
        case .preAnswerBufferLimit: .preAnswerBufferLimit
        }
    }

    static func result(_ value: AttemptOutcome.Result) -> SDK.Result {
        switch value {
        case .succeeded: .succeeded
        case .cancelled: .cancelled
        case .failed(let reason): .failed(failure: failure(reason))
        }
    }

    static func outcome(_ value: AttemptOutcome) -> SDK.Outcome {
        SDK.Outcome(
            providerId: value.providerID.uuidString, model: value.model,
            firstTokenSeconds: value.timeToFirstToken.map(seconds),
            tokensPerSecond: value.tokensPerSecond, result: result(value.result)
        )
    }

    static func remote(_ values: [String: RemoteModelHealth]) -> [SDK.RemoteHealth] {
        values.map { model, health in
            SDK.RemoteHealth(
                model: model, ttft: health.ttft.map(sample), tps: health.tps.map(sample),
                failures: health.failures.map(sample)
            )
        }
    }

    private static func sample(_ value: RemoteHealthSample) -> SDK.HealthSample {
        SDK.HealthSample(
            value: value.value, observedAt: value.observedAt.timeIntervalSince1970,
            expiresAt: value.expiresAt.timeIntervalSince1970,
            count: UInt64(max(0, value.count)), probe: value.source == .probe
        )
    }

    private static func seconds(_ value: Duration) -> Double {
        Double(value.components.seconds) + Double(value.components.attoseconds) / 1e18
    }
}
