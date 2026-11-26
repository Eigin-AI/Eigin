import EiginSDK
import Foundation

/// Supplies platform capabilities without owning request or turn progression.
@MainActor
struct InferenceRequestFactory {
    let context: InferenceRoutingContext
    let errors: RequestHostErrors

    func prepare(
        chatService: ChatService, host: String, hostID: UUID,
        messages: [ChatMessage], tools: [ToolDefinition]?, cacheKey: String?,
        inlineToolRunner: InlineToolRunner?,
        reported: @escaping @Sendable (
            EiginSDK.Experimental.Inference.RequestReport?,
            EiginSDK.Experimental.Routing.Result
        ) -> Void = { _, _ in },
        routing: (RouteRequirements) -> RouteRequest?,
        refreshCatalog: @escaping @MainActor @Sendable (UUID) async -> RoutingProvider? = { _ in
            nil
        }
    ) -> EiginSDK.Experimental.Agent.PreparedRequest {
        let errors = errors
        let context = context
        let local = ProviderPreset.isLocal(host)
        let input = local ? nil : routing(RouteRequirements(
            needsVision: messages.contains { $0.attachments?.isEmpty == false },
            promptTokens: TokenEstimator.estimateRequest(messages: messages, toolDefinitions: tools)
        ))
        let provider = RequestProviderContext(provider: input?.currentProvider)
        return .init(
            providerID: hostID.uuidString,
            local: local,
            routing: input.map(RoutingSDKConversion.request),
            services: .init(
                validate: { candidate in
                    do {
                        try await MainActor.run {
                            try ContextPagingSession.validate(
                                messages, tools: tools, model: candidate,
                                origin: ReasoningOrigin.destination(
                                    providerID: hostID,
                                    baseURL: host,
                                    model: candidate
                                )
                            )
                        }
                    } catch { throw errors.encode(error) }
                },
                open: { candidate, effort in
                    do {
                        let session = try await chatService.inferenceSession(
                            baseURL: host, providerID: hostID, messages: messages,
                            model: candidate,
                            tools: tools, cacheKey: cacheKey,
                            inlineToolRunner: inlineToolRunner,
                            reasoningEffort: effort.map(ReasoningEffort.init)
                        )
                        return .init(
                            next: {
                                do { return try await session.next() }
                                catch { throw errors.encode(error) }
                            },
                            cancel: { session.cancel() }
                        )
                    } catch { throw errors.encode(error) }
                },
                refreshCatalog: { _ in
                    guard let updated = await refreshCatalog(hostID) else { return nil }
                    return await provider.update(updated)
                },
                refreshHealth: { _ in
                    guard let current = await provider.current else { return [] }
                    return await context.health(current)
                },
                reported: reported,
                now: context.now
            )
        )
    }
}

@MainActor
private final class RequestProviderContext {
    private(set) var current: RoutingProvider?

    init(provider: RoutingProvider?) {
        current = provider
    }

    func update(_ updated: RoutingProvider) -> EiginSDK.Experimental.Routing.Inventory? {
        guard let previous = current else { return nil }
        let provider = RoutingProvider(
            id: previous.id, name: updated.name, baseURL: previous.baseURL,
            availableModels: updated.availableModels, enabledModels: updated.enabledModels
        )
        current = provider
        return RoutingSDKConversion.inventory(provider)
    }
}
