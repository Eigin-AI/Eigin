import EiginSDK
import Foundation

/// Opens a prepared request and coordinates its provider attempts until useful output wins.
@MainActor
struct InferenceAttemptCoordinator {
    let modelRouter: any ModelRouter
    private typealias EventStream = AsyncThrowingStream<ChatStreamEvent, Error>

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
        let router = modelRouter
        let local = ProviderPreset.isLocal(host)
        let request = local ? nil : routing(retryRequirements(messages: messages, tools: tools))
        let state = EiginSDK.Experimental.Inference.Attempts(
            local: local,
            routed: request != nil,
            maxBufferedBytes: 1_048_576,
            startingModel: model
        )
        let dispatch: @Sendable (String, @Sendable () -> Bool) async throws
            -> EventStream = { candidate, authorize in
                try await dispatchPreparedCandidate(authorize: authorize) {
                    try await MainActor.run {
                        try ContextPagingSession.validate(
                            messages,
                            tools: tools,
                            model: candidate,
                            origin: ReasoningOrigin.destination(
                                providerID: hostID,
                                baseURL: host,
                                model: candidate
                            )
                        )
                    }
                    guard let request else { return nil }
                    return await router.reasoningEffort(for: candidate, request: request)
                } open: { (effort: ReasoningEffort?) in
                    try await chatService.chatCompletionEventStream(
                        baseURL: host,
                        providerID: hostID,
                        messages: messages,
                        model: candidate,
                        tools: tools,
                        cacheKey: cacheKey,
                        inlineToolRunner: inlineToolRunner, reasoningEffort: effort
                    )
                }
            }
        func attempt(_ stream: EventStream) -> InferenceAttempt {
            InferenceAttempt(
                stream: stream,
                selection: state,
                providerID: hostID,
                dispatchedAt: startedAt,
                router: router
            )
        }
        if state.opensDirectly() { return try await attempt(dispatch(model) { true }) }
        let plan: HedgePlan? = if let request { await hedgePlan(for: request, primary: model) }
        else { nil }
        let retry = PreOutputRetry(request: request)
        let raced = withHedgedFirstToken(
            primaryModel: model,
            plan: plan,
            ceiling: DefaultModelRouter.firstTokenCeiling,
            attempts: state,
            classify: { InferenceSDKConversion.attemptEvent($0) },
            bufferedEventBytes: { $0.bufferedByteCount },
            emptyStreamError: { Self.unusableStreamError($0) },
            openPrimary: { try await dispatch($0) { true } },
            openFallback: {
                guard let fallback = plan?.fallbackModel
                else { return nil }
                return try await dispatch(fallback) { true }
            },
            onOpenFailure: { model, error in
                await router.record(AttemptOutcome(
                    providerID: hostID,
                    model: model,
                    timeToFirstToken: nil,
                    tokensPerSecond: nil,
                    duration: startedAt.duration(to: .now),
                    result: .failed(RoutingFailure(from: error))
                ))
            },
            primaryFailed: { chase, failedModel, error in
                await retry.replacement(
                    chase: chase, after: error,
                    model: failedModel,
                    router: router,
                    hostID: hostID,
                    startedAt: startedAt,
                    state: state,
                    refreshCatalog: refreshCatalog,
                    dispatch: dispatch
                )
            },
            onLoser: { model, silentFor in
                await router.recordHedgeLoss(model, silentFor: silentFor)
            }
        )
        return attempt(raced)
    }

    /// Retains chat recovery semantics without letting empty completions win a race.
    private nonisolated static func unusableStreamError(_ events: [ChatStreamEvent]) -> Error {
        if events.contains(.finished(.toolCalls)),
           events.contains(where: { if case .toolCall = $0 { return true }; return false })
        {
            return StreamCompletionError.invalidToolCall
        }
        if events.contains(.finished(.stop)) { return TurnCompletionError.missingReply }
        return StreamCompletionError.interrupted
    }

    /// The hedge plan for a turn: the next ranked same-provider candidate, with
    /// a shortened delay when the primary has recently been slow to speak.
    @MainActor
    private func hedgePlan(for request: RouteRequest, primary: String) async -> HedgePlan? {
        guard let fallback = await modelRouter.hedgeCandidate(after: primary, request: request)
        else { return nil }
        let delay = await modelRouter.hedgeDelay(for: primary)
        AppLogger.info(
            "Hedge armed on \(public: primary): runner-up \(public: fallback.model) if silent past \(public: "\(delay.components.seconds)")s",
            category: .routing
        )
        return HedgePlan(delay: delay, fallbackModel: fallback.model)
    }

    /// What a replacement model has to handle to take over mid-turn.
    ///
    /// The prompt's measured size, not the outgoing model's window: a million-token model
    /// could otherwise never be replaced by anything, however short the conversation
    /// actually is. Candidates use the SDK's input budget and output reservation.
    private func retryRequirements(
        messages: [ChatMessage], tools: [ToolDefinition]?
    ) -> RouteRequirements {
        RouteRequirements(
            needsVision: messages.contains { $0.attachments?.isEmpty == false },
            promptTokens: TokenEstimator.estimateRequest(
                messages: messages, toolDefinitions: tools
            )
        )
    }
}

/// A race shares one refresh and two switches across all pre-output failures.
private actor PreOutputRetry {
    private let request: RouteRequest?
    private var providers: [RoutingProvider]

    init(request: RouteRequest?) {
        self.request = request
        providers = request?.providers ?? []
    }

    func replacement(
        chase: UInt64, after error: Error,
        model: String,
        router: any ModelRouter,
        hostID: UUID,
        startedAt: ContinuousClock.Instant,
        state: EiginSDK.Experimental.Inference.Attempts,
        refreshCatalog: @MainActor @Sendable (UUID) async -> RoutingProvider?,
        dispatch: @Sendable (String, @Sendable () -> Bool) async throws -> AsyncThrowingStream<
            ChatStreamEvent,
            Error
        >
    ) async -> (model: String, stream: AsyncThrowingStream<ChatStreamEvent, Error>)? {
        let failure = RoutingFailure(from: error)
        while !Task.isCancelled {
            let work = state.replacementWork(
                failedModel: model,
                missingModel: failure == .modelNotFound,
                cancelled: error is CancellationError
            )
            guard let failedModel = work.recordModel else { return nil }
            await router.record(AttemptOutcome(
                providerID: hostID,
                model: failedModel,
                timeToFirstToken: nil,
                tokensPerSecond: nil,
                duration: startedAt.duration(to: .now),
                result: .failed(failure)
            ))
            if work.refresh {
                if let updated = await refreshCatalog(hostID) {
                    providers = providers.map { provider in
                        guard provider.id == hostID else { return provider }
                        return RoutingProvider(
                            id: hostID,
                            name: updated.name,
                            baseURL: provider.baseURL,
                            availableModels: updated.availableModels,
                            enabledModels: updated.enabledModels
                        )
                    }
                }
            }
            guard work.rank, let request else { break }
            let retryRequest = RouteRequest(
                currentProviderID: request.currentProviderID,
                currentModel: model,
                isAuto: request.isAuto,
                requirements: request.requirements,
                providers: providers,
                conversationID: request.conversationID,
                lastUserMessage: request.lastUserMessage,
                turnContext: request.turnContext
            )
            guard let next = await router.retry(after: error, request: retryRequest) else { break }
            do {
                let stream = try await dispatch(next.model) { state.claimSwitch(
                    chase: chase,
                    from: model,
                    to: next.model
                ) }
                state.replacementOpened(model: next.model)
                return (next.model, stream)
            } catch is DispatchDenied { break } catch {
                if error is CancellationError || Task.isCancelled { return nil }
            }
        }
        if !Task.isCancelled { state.exhausted() }
        return nil
    }
}

private struct DispatchDenied: Error {}

/// Checks the live grant after preparation, including failed validation which spends a switch.
private func dispatchPreparedCandidate<Input: Sendable, Output: Sendable>(
    authorize: @Sendable () -> Bool,
    prepare: @Sendable () async throws -> Input,
    open: @Sendable (Input) async throws -> Output
) async throws -> Output {
    let prepared: Result<Input, Error>
    do { prepared = try await .success(prepare()) } catch { prepared = .failure(error) }
    guard authorize() else { throw DispatchDenied() }
    return try await open(prepared.get())
}
