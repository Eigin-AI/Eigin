#if DEBUG || EIGIN_DEV
import Foundation

/// A ``ModelRouter`` with scripted answers that records what it was told.
actor FakeModelRouter: ModelRouter {
    var routeToReturn: ResolvedRoute?
    var retryModels: [String] = []
    private let hedgeModel: String?
    private(set) var hedgeLosses: [String] = []
    private(set) var retryRequests: [RouteRequest] = []
    var canSatisfyAnswer = true

    private(set) var recorded: [AttemptOutcome] = []
    private(set) var resolveCount = 0

    private let effortLookup: @Sendable (String) async -> ReasoningEffort?
    private var onRecord: (@Sendable () async -> Void)?

    init(
        retryModels: [String] = [],
        canSatisfyAnswer: Bool = true,
        hedgeModel: String? = nil,
        effortLookup: @escaping @Sendable (String) async -> ReasoningEffort? = { _ in nil }
    ) {
        self.effortLookup = effortLookup
        self.hedgeModel = hedgeModel
        self.retryModels = retryModels
        self.canSatisfyAnswer = canSatisfyAnswer
    }

    func setRecordHook(_ hook: @escaping @Sendable () async -> Void) {
        onRecord = hook
    }

    func resolve(_ request: RouteRequest) async -> ResolvedRoute {
        resolveCount += 1
        return routeToReturn
            ?? ResolvedRoute(
                providerID: request.currentProviderID,
                baseURL: request.currentProvider?.baseURL ?? "",
                model: request.currentModel,
                change: nil
            )
    }

    func record(_ attempt: AttemptOutcome) async {
        recorded.append(attempt)
        await onRecord?()
    }

    func retry(after _: Error, request: RouteRequest) async -> ResolvedRoute? {
        retryRequests.append(request)
        guard !retryModels.isEmpty else { return nil }
        let model = retryModels.removeFirst()
        return ResolvedRoute(
            providerID: request.currentProviderID,
            baseURL: request.currentProvider?.baseURL ?? "",
            model: model,
            change: .modelDegraded(previous: request.currentModel, reason: .errors)
        )
    }

    func hedgeCandidate(after _: String, request: RouteRequest) async -> ResolvedRoute? {
        hedgeModel.map { ResolvedRoute(
            providerID: request.currentProviderID,
            baseURL: request.currentProvider?.baseURL ?? "",
            model: $0,
            change: nil
        ) }
    }

    func reasoningEffort(
        for model: String,
        request _: RouteRequest
    ) async -> ReasoningEffort? {
        await effortLookup(model)
    }

    func hedgeDelay(for _: String) async -> Duration {
        .zero
    }

    func recordHedgeLoss(_ model: String, silentFor _: Duration) async {
        hedgeLosses.append(model)
    }

    func canSatisfy(_: RouteRequest) async -> Bool {
        canSatisfyAnswer
    }

    /// Outcomes seen so far, for assertions from a synchronous context.
    func outcomes() -> [AttemptOutcome] {
        recorded
    }
}
#endif
