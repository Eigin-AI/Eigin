@testable import Eigin
import EiginSDK
import Foundation

/// Exercises the app's request capabilities independently of complete-turn progression.
@MainActor
struct InferenceAttemptCoordinator {
    let modelRouter: any ModelRouter

    func open(
        chatService: ChatService, host: String, hostID: UUID, model: String,
        messages: [ChatMessage], tools: [ToolDefinition]?, cacheKey: String?,
        inlineToolRunner: InlineToolRunner? = nil,
        routing: (RouteRequirements) -> RouteRequest?,
        refreshCatalog: @escaping @MainActor @Sendable (UUID) async -> RoutingProvider? = { _ in
            nil
        }
    ) async throws -> InferenceAttempt {
        let startedAt = ContinuousClock.now
        let context = await modelRouter.inferenceContext()
        let errors = RequestHostErrors()
        let prepared = InferenceRequestFactory(context: context, errors: errors).prepare(
            chatService: chatService, host: host, hostID: hostID, messages: messages,
            tools: tools, cacheKey: cacheKey, inlineToolRunner: inlineToolRunner,
            routing: routing, refreshCatalog: refreshCatalog
        )
        do {
            let request = try await EiginSDK.Experimental.Inference.Request.start(
                router: context.policy, providerID: prepared.providerID, model: model,
                local: prepared.local, routing: prepared.routing, services: prepared.services
            )
            return InferenceAttempt(request: request, errors: errors, dispatchedAt: startedAt)
        } catch { throw errors.restore(error) }
    }
}
