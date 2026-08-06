@testable import Eigin
import Foundation

/// A ``ModelRouter`` with scripted answers that records what it was told.
actor FakeModelRouter: ModelRouter {
    var routeToReturn: ResolvedRoute?
    var retryModels: [String] = []
    var canSatisfyAnswer = true

    private(set) var recorded: [AttemptOutcome] = []
    private(set) var resolveCount = 0

    init(retryModels: [String] = [], canSatisfyAnswer: Bool = true) {
        self.retryModels = retryModels
        self.canSatisfyAnswer = canSatisfyAnswer
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
    }

    func retry(after _: Error, request: RouteRequest) async -> ResolvedRoute? {
        guard !retryModels.isEmpty else { return nil }
        let model = retryModels.removeFirst()
        return ResolvedRoute(
            providerID: request.currentProviderID,
            baseURL: request.currentProvider?.baseURL ?? "",
            model: model,
            change: .modelDegraded(previous: request.currentModel, reason: .errors)
        )
    }

    func canSatisfy(_: RouteRequest) async -> Bool {
        canSatisfyAnswer
    }

    /// Outcomes seen so far, for assertions from a synchronous context.
    func outcomes() -> [AttemptOutcome] {
        recorded
    }
}
