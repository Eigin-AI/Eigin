import Foundation
import os
import SwiftData

/// Stream opening: the hedged race, the primary-only and local fallbacks, and
/// the routing request the retry hook races against. Split from the turn loop's
/// core file to keep each readable.
extension AgenticChatLoop {
    /// Opens the turn's hedged stream: a runner-up races a silent primary, and
    /// the failure hook chases pre-first-token failures (switch budget capped).
    /// A stream that already shipped tokens never switches — see the round loop.
    /// `inlineToolRunner` reaches local model clients only.
    func openStream(
        chatService: ChatService,
        provider: Provider,
        agent: Agent,
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        cacheKey: String?,
        inlineToolRunner: InlineToolRunner? = nil,
        routing: RouteRequest? = nil,
        conversationID: UUID? = nil
    ) async throws -> TurnStream {
        let dispatchedAt = ContinuousClock.now

        // A local model is the only option on its provider: no runner-up to race.
        if ProviderPreset.isLocal(provider.baseURL) {
            return try await unhedgedStream(
                chatService: chatService, provider: provider,
                messages: messages, tools: tools, cacheKey: cacheKey,
                inlineToolRunner: inlineToolRunner, model: activeModel,
                dispatchedAt: dispatchedAt
            )
        }

        // Flattened once onto Sendable values: the retry hook runs off the main
        // actor and cannot read SwiftData. Onboarding surfaces pass their
        // routing in pre-built; with neither source, the turn runs unhedged.
        let request = routing
            ?? RouteRequest(
                agent: agent,
                provider: provider,
                model: activeModel,
                requirements: retryRequirements(messages: messages, tools: tools),
                conversationID: conversationID,
                lastUserMessage: messages.last(where: { $0.role == "user" })?.content
            )
        guard let request else {
            return primaryOnlyStream(
                chatService: chatService, provider: provider,
                messages: messages, tools: tools, cacheKey: cacheKey,
                inlineToolRunner: inlineToolRunner, model: activeModel,
                dispatchedAt: dispatchedAt
            )
        }

        let plan: HedgePlan? = await hedgePlan(for: request, primary: activeModel)
        let raceWinner = RaceWinner()
        let router = modelRouter
        let host = provider.baseURL
        let hostID = provider.id
        let startedAt = dispatchedAt

        let dispatch: @Sendable (String) async throws -> AsyncThrowingStream<
            ChatStreamEvent, Error
        > = { model in
            try await chatService.chatCompletionEventStream(
                baseURL: host,
                providerID: hostID,
                messages: messages,
                model: model,
                tools: tools,
                cacheKey: cacheKey,
                inlineToolRunner: inlineToolRunner
            )
        }

        let openFallback: @Sendable () async -> AsyncThrowingStream<ChatStreamEvent, Error>? = {
            guard let fallbackModel = plan?.fallbackModel else { return nil }
            do {
                return try await dispatch(fallbackModel)
            } catch {
                // An unhedged turn beats a failed one. A failed dispatch still
                // says nothing good about the runner-up, though — let the
                // router know.
                Task {
                    await router.record(
                        AttemptOutcome(
                            providerID: hostID,
                            model: fallbackModel,
                            timeToFirstToken: nil,
                            tokensPerSecond: nil,
                            duration: startedAt.duration(to: .now),
                            result: .failed(RoutingFailure(from: error))
                        )
                    )
                }
                return nil
            }
        }

        // Models the retry hook switched to; the loop persists the winner's.
        let switchCandidate = OSAllocatedUnfairLock(initialState: String?.none)
        // Set when the hook resurfaces an error, so the consuming loop's catch
        // does not record the same failure a second time.
        let failureReported = OSAllocatedUnfairLock(initialState: false)
        // Switch budget for the whole turn, not per hook re-entry: a replacement
        // that later dies pre-token re-enters the hook, and each re-entry starts
        // from what the turn has already spent.
        let switchBudget = OSAllocatedUnfairLock(initialState: 0)

        // A retired model often means a stale catalog, and the cached list may
        // not hold anything to move to. Re-fetch before asking the router for an
        // alternative. Main-actor: the provider record is SwiftData, and this
        // closure is formed while openStream still holds that context.
        let catalogRefreshed = OSAllocatedUnfairLock(initialState: false)
        // The provider list the retry hook routes from, refreshed in place by
        // the catalog refresh so a stale catalogue at dispatch doesn't strand
        // the whole turn.
        let retryProviders = OSAllocatedUnfairLock(initialState: request.providers)
        let refreshCatalog: @MainActor @Sendable (UUID) async -> Void = { [weak self] hostID in
            guard let self, let context = agent.modelContext else { return }
            guard
                let provider = try? context.fetch(FetchDescriptor<Provider>()).first(where: {
                    $0.id == hostID
                })
            else { return }
            // Read the model's fields before the await: the refresh sends the
            // record across, so nothing of it may be read afterwards.
            let name = provider.name
            let enabled = provider.enabledModels
            guard
                let refreshed = try? await modelRefresher.refresh(
                    provider, apiKeyOverride: nil
                )
            else { return }
            retryProviders.withLock { list in
                list = list.map { model in
                    model.id == hostID
                        ? RoutingProvider(
                            id: model.id, name: name, baseURL: model.baseURL,
                            availableModels: refreshed, enabledModels: enabled
                        )
                        : model
                }
            }
        }

        // The standing pre-first-token retry, moved inside the race: record the
        // failure and ask the router for the next ranked model until the turn's
        // switch budget is gone. Nil says surface the error.
        let primaryFailed: @Sendable (String, Error) async -> (
            model: String,
            stream:
            AsyncThrowingStream<ChatStreamEvent, Error>
        )? = { failedModel, error in
            if error is CancellationError || Task.isCancelled { return nil }

            var model = failedModel

            while !Task.isCancelled {
                let failure = RoutingFailure(from: error)
                await router.record(
                    AttemptOutcome(
                        providerID: hostID,
                        model: model,
                        timeToFirstToken: nil,
                        tokensPerSecond: nil,
                        duration: startedAt.duration(to: .now),
                        result: .failed(failure)
                    )
                )
                // A retired model often means a stale catalog, and the cached list
                // may not hold anything to move to. Re-fetch once before asking
                // the router for an alternative.
                if failure == .modelNotFound,
                   !catalogRefreshed.withLock({ dirty -> Bool in
                       if dirty { return true }
                       dirty = true
                       return false
                   })
                {
                    await refreshCatalog(hostID)
                }
                guard switchBudget.withLock { $0 } < TurnStream.maxModelSwitches else {
                    // Terminal: the surfaced error is this last recorded one.
                    failureReported.withLock { $0 = true }
                    return nil
                }
                let request = RouteRequest(
                    currentProviderID: request.currentProviderID,
                    currentModel: model,
                    isAuto: request.isAuto,
                    requirements: request.requirements,
                    providers: retryProviders.withLock { $0 },
                    conversationID: request.conversationID,
                    lastUserMessage: request.lastUserMessage
                )
                guard
                    let next = await router.retry(after: error, request: request),
                    next.model != model
                else {
                    failureReported.withLock { $0 = true }
                    return nil
                }

                switchBudget.withLock { $0 += 1 }
                do {
                    let stream = try await dispatch(next.model)
                    switchCandidate.withLock { $0 = next.model }
                    return (next.model, stream)
                } catch {
                    if error is CancellationError || Task.isCancelled { return nil }
                }
            }
            return nil
        }

        let raced = withHedgedFirstToken(
            primaryModel: activeModel,
            plan: plan,
            ceiling: DefaultModelRouter.firstTokenCeiling,
            raceWinner: raceWinner,
            openPrimary: dispatch,
            openFallback: openFallback,
            primaryFailed: primaryFailed,
            onLoser: { model, silentFor in
                await router.recordHedgeLoss(model, silentFor: silentFor)
            }
        )
        return TurnStream(
            stream: raced,
            dispatchedAt: dispatchedAt,
            raceWinner: raceWinner,
            switchCandidate: switchCandidate,
            failureReported: failureReported
        )
    }

    /// The hedge plan for a turn: the next ranked same-provider candidate, with
    /// a shortened delay when the primary has recently been slow to speak.
    @MainActor
    func hedgePlan(for request: RouteRequest, primary: String) async -> HedgePlan? {
        guard let fallback = await modelRouter.hedgeCandidate(after: primary, request: request)
        else { return nil }
        let delay = await modelRouter.hedgeDelay(for: primary)
        AppLogger.info(
            "Hedge armed on \(public: primary): runner-up \(public: fallback.model) if silent past \(public: "\(delay.components.seconds)")s",
            category: .routing
        )
        return HedgePlan(delay: delay, fallbackModel: fallback.model)
    }

    /// A fallback stream when routing context went missing: no hedge, just the
    /// primary against the first-token ceiling, with failures recorded only
    /// (there is no routing context to retry against).
    /// The local-model path: one plain stream, no race, no fallback. Dispatch
    /// failures surface to the caller as before, since no alternative exists.
    @MainActor
    func unhedgedStream(
        chatService: ChatService,
        provider: Provider,
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        cacheKey: String?,
        inlineToolRunner: InlineToolRunner?,
        model: String,
        dispatchedAt: ContinuousClock.Instant
    ) async throws -> TurnStream {
        let stream = try await chatService.chatCompletionEventStream(
            baseURL: provider.baseURL,
            providerID: provider.id,
            messages: messages,
            model: model,
            tools: tools,
            cacheKey: cacheKey,
            inlineToolRunner: inlineToolRunner
        )
        return TurnStream(stream: stream, dispatchedAt: dispatchedAt, raceWinner: RaceWinner())
    }

    func primaryOnlyStream(
        chatService: ChatService,
        provider: Provider,
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        cacheKey: String?,
        inlineToolRunner: InlineToolRunner?,
        model: String,
        dispatchedAt: ContinuousClock.Instant
    ) -> TurnStream {
        let raceWinner = RaceWinner()
        let router = modelRouter
        let host = provider.baseURL
        let hostID = provider.id
        let startedAt = dispatchedAt
        // The hook records the failure itself; flag it so the consuming loop's
        // catch does not record the same failure a second time.
        let failureReported = OSAllocatedUnfairLock(initialState: false)
        let raced = withHedgedFirstToken(
            primaryModel: model,
            plan: nil,
            ceiling: DefaultModelRouter.firstTokenCeiling,
            raceWinner: raceWinner,
            openPrimary: { currentModel in
                try await chatService.chatCompletionEventStream(
                    baseURL: host,
                    providerID: hostID,
                    messages: messages,
                    model: currentModel,
                    tools: tools,
                    cacheKey: cacheKey,
                    inlineToolRunner: inlineToolRunner
                )
            },
            openFallback: { nil },
            primaryFailed: { failedModel, error in
                guard !(error is CancellationError), !Task.isCancelled else { return nil }
                failureReported.withLock { $0 = true }
                await router.record(
                    AttemptOutcome(
                        providerID: hostID,
                        model: failedModel,
                        timeToFirstToken: nil,
                        tokensPerSecond: nil,
                        duration: startedAt.duration(to: .now),
                        result: .failed(RoutingFailure(from: error))
                    )
                )
                return nil
            },
            onLoser: { _, _ in }
        )
        return TurnStream(
            stream: raced,
            dispatchedAt: dispatchedAt,
            raceWinner: raceWinner,
            failureReported: failureReported
        )
    }

    /// What a replacement model has to handle to take over mid-turn.
    ///
    /// The prompt's measured size, not the outgoing model's window: a million-token model
    /// could otherwise never be replaced by anything, however short the conversation
    /// actually is. The router adds each candidate's own output reservation on top.
    func retryRequirements(
        messages: [ChatMessage], tools: [ToolDefinition]?
    ) -> RouteRequirements {
        RouteRequirements(
            needsVision: messages.contains { $0.attachments?.isEmpty == false },
            promptTokens: TokenEstimator.estimateRequest(
                messages: messages, toolDefinitions: tools
            )
        )
    }

    // Logs the user-perceived shape of a round: prep time (send to dispatch)
    // and model time (dispatch to first token) are different problems with
    // different owners, and only the second one is the model's to answer for.
}
