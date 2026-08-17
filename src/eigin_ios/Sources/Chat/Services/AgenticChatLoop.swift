import Factory
import Foundation
import os
import SwiftUI

/// Status of a tool event shown in the chat feed.
enum ToolEventStatus: Equatable {
    case executing
    case awaitingPermission
    case completed
    case denied
    case error(String)
}

/// A permission request presented to the user in the chat feed.
struct PermissionRequest: Identifiable, Equatable {
    let id: String // tool call ID
    let toolName: String
    let toolDisplayName: String
}

/// The user's response to a permission request.
enum PermissionResponse {
    case allowOnce
    case allowForChat
    case deny
}

/// A tool event tracked during an agentic chat turn.
struct ToolEvent: Identifiable, Equatable {
    let id: String
    let toolName: String
    var status: ToolEventStatus
    let arguments: String?
}

/// Phase of the chat execution loop.
enum ChatPhase: Equatable {
    case idle
    case streamingProse
    case streamingTools
    case readyToExecute
    case executingTools
    case done
}

/// Orchestrates the recursive tool-calling loop for a single chat turn.
///
/// Streams assistant content, detects tool calls, executes them, sends results back,
/// and repeats until the model finishes with a stop reason.
@Observable
@MainActor
final class AgenticChatLoop {
    // MARK: - Published State

    /// Computed properties that read directly from the throttler so that
    /// the 60fps timer updates propagate to the view automatically.
    var phase: StreamThrottler.Phase {
        throttler.phase
    }

    var displayedText: String {
        throttler.displayedText
    }

    var fullText: String {
        throttler.fullText
    }

    var scrollTrigger: Int {
        throttler.scrollTrigger
    }

    private(set) var toolEvents: [ToolEvent] = []
    private(set) var pendingPermission: PermissionRequest?
    private(set) var pendingBrowsing: BrowsingRequest?

    /// True while an interactive tool is executing (e.g. presenting options to the user).
    /// When true the view layer re-enables the input bar and hides the stop button.
    private(set) var isAwaitingUserInteraction = false

    let isBootstrap: Bool
    /// Optional callback fired on each content delta (used by live call for streaming TTS).
    var onContentDelta: ((String) -> Void)?
    /// Callback fired when the user grants "allow for chat" — caller persists the grants.
    var onChatGrant: (([ToolCapability]) -> Void)?
    private(set) var throttler: any StreamThrottling
    var permissionPolicy: ToolPermissionPolicy
    private var permissionContinuation: CheckedContinuation<PermissionResponse, Never>?
    private var browsingContinuation: CheckedContinuation<BrowsingResult, Never>?
    private var optionsContinuation: CheckedContinuation<OptionSelection, Never>?

    /// Active option set presented to the user while a tool is suspended.
    private(set) var pendingOptions: OptionSet?

    /// Optional callback checked after each tool execution round.
    /// Return `true` to stop the loop early (e.g. background decision tool fired).
    var shouldTerminate: (() -> Bool)?

    /// Optional callback invoked after each tool execution round to rebuild the tool
    /// registry (e.g. when a skill is activated mid-turn). Returns updated definitions
    /// and executor for subsequent rounds.
    var onToolsChanged: (() async -> (tools: [ToolDefinition], executor: ToolExecutor))?

    /// Maximum number of tool-calling rounds before forcing a stop.
    private let maxRounds = 40

    /// Timeout for individual tool executions.
    private let toolExecutionTimeout: Duration = .seconds(30)

    private(set) var roundsExecuted: Int = 0

    private var chatPhase: ChatPhase = .idle
    private var contentBuffer = ""
    private var pendingToolCalls: [ToolCall] = []
    private var produced: [ChatMessage] = []
    /// Index in `produced` after the last complete round (all tool results present).
    /// Used by `buildCheckpoint()` to avoid returning orphaned tool calls.
    private var safeProducedCount = 0

    /// Messages from completed rounds that the UI can display while the loop
    /// is still running. Only includes full rounds (assistant + all tool results).
    var committedMessages: [ChatMessage] {
        Array(produced.prefix(safeProducedCount))
    }

    private var shouldStop = false

    @ObservationIgnored
    @Injected(\.modelRouter) private var modelRouter

    @ObservationIgnored
    @Injected(\.providerModelRefresher) private var modelRefresher

    /// Guards the catalog refresh so a turn re-fetches at most once.
    private var didRefreshCatalog = false

    /// The model this turn is running on. Usually the agent's, but an offline turn runs
    /// on-device without disturbing the provider and model the user chose.
    private var activeModel = ""

    /// Model switches spent on this turn, capped by ``maxModelSwitches``.
    private var modelSwitches = 0

    /// Bounds how far one turn will chase a working model, in both cost and latency.
    private let maxModelSwitches = 2

    /// Message ID for the current streaming turn (used for block ID stability).
    private var currentMessageID: String = ""

    /// Feed item ID of the streaming message, matching the ID it carries once committed,
    /// so the feed can render the live turn as the row it becomes.
    var streamingItemID: String? {
        currentMessageID.isEmpty ? nil : "msg-\(currentMessageID)"
    }

    init(
        isBootstrap: Bool, throttler: any StreamThrottling = StreamThrottler(),
        permissionPolicy: ToolPermissionPolicy = AlwaysAllowPolicy()
    ) {
        self.isBootstrap = isBootstrap
        self.throttler = throttler
        self.permissionPolicy = permissionPolicy
    }

    // MARK: - API

    /// Runs a complete chat turn, handling tool calls recursively.
    /// Returns all messages produced during the turn (assistant + tool results + final assistant).
    func run(
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        agent: Agent,
        provider: Provider,
        chatService: ChatService,
        toolExecutor: ToolExecutor,
        cacheKey: String? = nil,
        model: String? = nil
    ) async throws -> [ChatMessage] {
        reset()
        activeModel = model ?? agent.model
        shouldStop = false
        currentMessageID = "msg-\(UUID().uuidString)"
        throttler.start()

        var allMessages = messages
        var currentTools = tools
        var currentExecutor: ToolExecutor = toolExecutor

        // Build an inline runner for local models. The runner executes each tool
        // call mid-stream (inside LiteRT's loop), records the round into
        // `produced` so history is persisted, and returns the result to LiteRT
        // so it can continue generating. For cloud providers the runner is never
        // invoked — the stream surfaces .toolCall events and the loop below
        // drives execution after each round.
        let inlineRunner = InlineToolRunner { [weak self] call in
            guard let self else {
                return ToolResult(toolCallID: call.id, content: "{}", isError: true)
            }
            let result = await executeToolCall(call, agent: agent, executor: currentExecutor)
            // Record the assistant turn (with tool calls) and the tool result so
            // history matches the cloud path and the turn persists on completion.
            //
            // Known fidelity tradeoff: the recorded assistant message has
            // content: nil, while any prose the model emitted *before* this tool
            // call is accumulated by the throttler into the turn's final
            // assistant message. So pre-call prose lands after the tool result in
            // replayed history. This is valid and replayable; we accept it rather
            // than splitting the throttled prose stream at tool-call boundaries
            // we can't cleanly observe from inside LiteRT's loop.
            let assistantMsg = ChatMessage(role: "assistant", content: nil, toolCalls: [call])
            let toolMsg = ChatMessage(
                role: "tool",
                content: result.content,
                toolCallID: result.toolCallID,
                name: call.function.name
            )
            produced.append(assistantMsg)
            produced.append(toolMsg)
            safeProducedCount = produced.count
            return result
        }

        for round in 0 ..< maxRounds {
            roundsExecuted = round + 1
            if shouldStop { return [] }
            AppLogger.debug(
                "Round \(public: round): sending \(public: allMessages.count) messages",
                category: .chat
            )

            let (stream, streamStart) = try await openStream(
                chatService: chatService,
                provider: provider,
                agent: agent,
                messages: allMessages,
                tools: currentTools,
                cacheKey: cacheKey,
                inlineToolRunner: inlineRunner
            )

            contentBuffer = ""
            pendingToolCalls = []
            var finishReason: ChatStreamEvent.FinishReason = .stop
            var capturedProviderMetadata: [String: String]?

            chatPhase = .streamingProse

            // Measured from request dispatch: the first-token wait is spent inside openStream.
            var firstTokenAt: ContinuousClock.Instant?

            do {
                for try await event in stream {
                    if shouldStop { return [] }

                    switch event {
                    case .contentDelta(let delta):
                        if firstTokenAt == nil { firstTokenAt = .now }
                        contentBuffer += delta
                        chatPhase = .streamingProse
                        throttler.feed(delta)
                        onContentDelta?(delta)

                    case .toolCall(let call):
                        AppLogger.debug(
                            "Tool call received: \(public: call.function.name)(id: \(public: call.id))",
                            category: .chat
                        )
                        chatPhase = .streamingTools
                        pendingToolCalls.append(call)

                    case .providerMetadata(let meta):
                        AppLogger.debug(
                            "Captured provider metadata: \(public: meta.keys.joined(separator: ", "))",
                            category: .chat
                        )
                        capturedProviderMetadata = meta

                    case .finished(let reason):
                        AppLogger.debug(
                            "Finished with reason: \(public: String(describing: reason))",
                            category: .chat
                        )
                        finishReason = reason
                        if reason == .toolCalls, !pendingToolCalls.isEmpty {
                            chatPhase = .readyToExecute
                        } else {
                            chatPhase = .done
                        }
                    }
                }
            } catch is CancellationError {
                await reportAttempt(
                    provider: provider, start: streamStart,
                    firstTokenAt: firstTokenAt, result: .cancelled
                )
                return []
            } catch {
                await reportAttempt(
                    provider: provider, start: streamStart,
                    firstTokenAt: firstTokenAt,
                    result: .failed(RoutingFailure(from: error))
                )
                throw error
            }

            await reportAttempt(
                provider: provider, start: streamStart,
                firstTokenAt: firstTokenAt, result: .succeeded
            )

            AppLogger.debug(
                "Stream ended. Content length: \(public: contentBuffer.count), tool calls: \(public: pendingToolCalls.count), reason: \(public: String(describing: finishReason))",
                category: .chat
            )

            if finishReason == .toolCalls, !pendingToolCalls.isEmpty {
                if shouldStop { return [] }

                chatPhase = .executingTools

                if contentBuffer.isEmpty {
                    // No prose to drain — stay in .waiting to keep
                    // typing indicator visible throughout tool execution.
                    throttler.resetKeepingPhase(.waiting)
                } else {
                    // Drain streaming text before committing the message.
                    throttler.finish()
                    await waitForThrottlerDrain()
                }

                // Build the assistant message with tool calls (include provider metadata
                // if present). Reuse currentMessageID as the localID when there's prose, so
                // the committed row keeps the live streaming row's feed identity.
                let assistantMessage = ChatMessage(
                    role: "assistant",
                    content: contentBuffer.isEmpty ? nil : contentBuffer,
                    toolCalls: pendingToolCalls,
                    providerMetadata: capturedProviderMetadata,
                    localID: contentBuffer.isEmpty ? UUID().uuidString : currentMessageID
                )
                allMessages.append(assistantMessage)
                produced.append(assistantMessage)
                safeProducedCount = produced.count

                // Now that the committed message is in the items list,
                // clear streaming view so the typing indicator appears.
                if !contentBuffer.isEmpty {
                    throttler.resetKeepingPhase(.waiting)
                }

                // Execute each tool call
                for call in pendingToolCalls {
                    if shouldStop { return [] }

                    let result = await executeToolCall(
                        call, agent: agent, executor: currentExecutor
                    )

                    let toolMessage = ChatMessage(
                        role: "tool",
                        content: result.content,
                        toolCallID: result.toolCallID,
                        name: call.function.name
                    )
                    allMessages.append(toolMessage)
                    produced.append(toolMessage)
                    safeProducedCount = produced.count
                }

                // All tool results appended — mark this as a safe checkpoint.
                safeProducedCount = produced.count

                // Check if the caller wants to stop early (e.g. background decision tool fired).
                if shouldTerminate?() == true {
                    break
                }

                // Rebuild tools if a skill was activated (or any other tool changed the registry).
                if let onToolsChanged {
                    let updated = await onToolsChanged()
                    currentTools = updated.tools
                    currentExecutor = updated.executor
                }

                // Prepare for the next round (already in .waiting from resetKeepingPhase).
                // Regenerate the message id so the next prose segment gets its own feed identity.
                chatPhase = .streamingProse
                contentBuffer = ""
                pendingToolCalls = []
                currentMessageID = "msg-\(UUID().uuidString)"
                continue
            }

            chatPhase = .done

            // finish_reason == stop: we're done
            throttler.finish()
            await waitForThrottlerDrain()

            let finalContent = throttler.fullText

            AppLogger.debug("Final content length: \(public: finalContent.count)", category: .chat)

            if !finalContent.isEmpty {
                let finalMessage = ChatMessage(
                    role: "assistant",
                    content: finalContent,
                    localID: currentMessageID
                )
                produced.append(finalMessage)
                // Don't update safeProducedCount here — the final message
                // is still visible via the streaming view. Including it in
                // committedMessages would show a duplicate until settle().
            }

            // Don't reset the throttler here — the caller should append
            // produced messages and then call settle() so both state changes
            // are batched in the same SwiftUI update cycle.
            break
        }

        AppLogger.debug("Done. Produced \(public: produced.count) messages", category: .chat)
        if shouldStop { return [] }
        return produced
    }

    /// Commits the current round: captures produced messages and settles streaming
    /// state. Call synchronously before appending to the display message list so
    /// SwiftUI batches both changes in one update cycle.
    func completeRound() -> [ChatMessage] {
        let messages = produced
        settle()
        return messages
    }

    /// Clears streaming state after the caller has committed produced messages.
    /// Call this synchronously after appending to `displayMessages` so SwiftUI
    /// batches both changes (committed messages appear + streaming item disappears).
    func settle() {
        throttler.reset()
        toolEvents = []
        produced = []
        safeProducedCount = 0
    }

    /// Aborts a running stream.
    func abort() {
        throttler.abort()
    }

    /// Resets all state for a new turn.
    func reset() {
        throttler.reset()
        toolEvents = []
        chatPhase = .idle
        contentBuffer = ""
        pendingToolCalls = []
        produced = []
        safeProducedCount = 0
        shouldStop = false
        pendingBrowsing = nil
        pendingOptions = nil
        isAwaitingUserInteraction = false
        currentMessageID = ""
        modelSwitches = 0
        didRefreshCatalog = false
    }

    /// Resolves a pending permission request from the UI.
    func resolvePermission(_ response: PermissionResponse) {
        permissionContinuation?.resume(returning: response)
        permissionContinuation = nil
        pendingPermission = nil
    }

    /// Presents a browsing request and suspends until the UI resolves it.
    func requestBrowsing(_ request: BrowsingRequest) async -> BrowsingResult {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<BrowsingResult, Never>) in
            self.browsingContinuation = continuation
            self.pendingBrowsing = request
        }
    }

    /// Resolves a pending browsing request from the UI.
    func resolveBrowsing(_ result: BrowsingResult) {
        browsingContinuation?.resume(returning: result)
        browsingContinuation = nil
        pendingBrowsing = nil
    }

    /// Presents options to the user and suspends until the UI resolves it.
    func presentOptions(_ set: OptionSet) async -> OptionSelection {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<OptionSelection, Never>) in
            self.optionsContinuation = continuation
            self.pendingOptions = set
        }
    }

    /// Resolves a pending options request from the UI.
    func resolveOptions(_ selection: OptionSelection) {
        optionsContinuation?.resume(returning: selection)
        optionsContinuation = nil
        pendingOptions = nil
    }

    /// Force-dismiss any pending options (e.g. when user sends a text message).
    func dismissPendingOptions() {
        if pendingOptions != nil {
            resolveOptions(.dismissed)
        }
    }

    /// Stops the stream and returns a checkpoint of safe messages.
    /// Returns only messages that were safely committed before the stop point.
    func stop() -> [ChatMessage] {
        guard chatPhase != .idle, chatPhase != .done else { return [] }
        shouldStop = true
        throttler.abort()
        // Cancel any pending permission prompt
        permissionContinuation?.resume(returning: .deny)
        permissionContinuation = nil
        pendingPermission = nil
        // Cancel any pending browsing request
        browsingContinuation?.resume(returning: .cancelled)
        browsingContinuation = nil
        pendingBrowsing = nil
        // Cancel any pending interactive tool
        optionsContinuation?.resume(returning: .dismissed)
        optionsContinuation = nil
        pendingOptions = nil
        isAwaitingUserInteraction = false
        return buildCheckpoint()
    }

    // MARK: - Private

    /// Opens a chat stream, asking ``ModelRouter`` for another model when one fails.
    ///
    /// A stream that never opens has produced nothing, so switching models here is
    /// invisible to the user. The router decides whether a failure is worth chasing at
    /// all: a bad key or an empty wallet surfaces instead of burning more attempts.
    ///
    /// `inlineToolRunner` is forwarded to local model clients so they can execute
    /// tools mid-stream. Cloud clients ignore it via the default implementation
    /// on `ChatService`.
    ///
    /// Returns the stream with its request-dispatch instant, the origin for time-to-first-token.
    private func openStream(
        chatService: ChatService,
        provider: Provider,
        agent: Agent,
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        cacheKey: String?,
        inlineToolRunner: InlineToolRunner? = nil
    ) async throws
        -> (
            stream: AsyncThrowingStream<ChatStreamEvent, Error>,
            dispatchedAt: ContinuousClock.Instant
        )
    {
        while true {
            let attemptStart = ContinuousClock.now
            do {
                let stream = try await chatService.chatCompletionEventStream(
                    baseURL: provider.baseURL,
                    providerID: provider.id,
                    messages: messages,
                    model: activeModel,
                    tools: tools,
                    cacheKey: cacheKey,
                    inlineToolRunner: inlineToolRunner
                )
                // On-device prefill is legitimately slow, and there is nothing past it to
                // fall back to.
                guard !ProviderPreset.isLocal(provider.baseURL) else {
                    return (stream, attemptStart)
                }
                return (withFirstEventDeadline(
                    stream, deadline: DefaultModelRouter.firstTokenCeiling
                ), attemptStart)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                let failure = RoutingFailure(from: error)
                await modelRouter.record(
                    AttemptOutcome(
                        providerID: provider.id,
                        model: activeModel,
                        timeToFirstToken: nil,
                        tokensPerSecond: nil,
                        duration: attemptStart.duration(to: .now),
                        result: .failed(failure)
                    )
                )
                // A retired model often means a stale catalog, and the cached list may not
                // hold anything to move to. Re-fetch before asking for an alternative.
                if failure == .modelNotFound, !didRefreshCatalog {
                    didRefreshCatalog = true
                    _ = try? await modelRefresher.refresh(provider, apiKeyOverride: nil)
                }
                guard modelSwitches < maxModelSwitches,
                      let request = RouteRequest(
                          agent: agent,
                          provider: provider,
                          model: activeModel,
                          requirements: retryRequirements(messages: messages, tools: tools)
                      ),
                      let next = await modelRouter.retry(after: error, request: request),
                      next.model != activeModel
                else {
                    throw error
                }
                modelSwitches += 1
                activeModel = next.model
                // Persist only while on the user's own provider, so an offline turn never
                // overwrites the model they chose for their cloud provider.
                if provider.id == agent.providerID { agent.model = next.model }
            }
        }
    }

    /// What a replacement model has to handle to take over mid-turn.
    ///
    /// The prompt's measured size, not the outgoing model's window: a million-token model
    /// could otherwise never be replaced by anything, however short the conversation
    /// actually is. The router adds each candidate's own output reservation on top.
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

    /// Reports one stream's timings to the router.
    ///
    /// Throughput is estimated from the prose actually streamed, at the usual four
    /// characters per token. Tool-call arguments are excluded, so a tool-heavy round
    /// under-reports rather than inventing precision the stream cannot give us.
    private func reportAttempt(
        provider: Provider,
        start: ContinuousClock.Instant,
        firstTokenAt: ContinuousClock.Instant?,
        result: AttemptOutcome.Result
    ) async {
        let duration = start.duration(to: .now)
        let tokensPerSecond: Double? = {
            guard let firstTokenAt, contentBuffer.count >= 40 else { return nil }
            let generating = firstTokenAt.duration(to: .now).seconds
            guard generating > 0 else { return nil }
            return (Double(contentBuffer.count) / 4) / generating
        }()
        await modelRouter.record(
            AttemptOutcome(
                providerID: provider.id,
                model: activeModel,
                timeToFirstToken: firstTokenAt.map { start.duration(to: $0) },
                tokensPerSecond: tokensPerSecond,
                duration: duration,
                result: result
            )
        )
    }

    private func updateToolEvent(id: String, status: ToolEventStatus) {
        if let index = toolEvents.firstIndex(where: { $0.id == id }) {
            toolEvents[index].status = status
        }
    }

    private func waitForThrottlerDrain() async {
        while throttler.phase == .streaming {
            // CADisplayLink stops in background — force-complete if stalled.
            if UIApplication.shared.applicationState != .active {
                throttler.flushIfStalled()
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Executes a single tool call: resolves permission (prompting the user when
    /// the policy says `.ask` and prompting is allowed), runs the tool, and
    /// updates the chat-feed ``ToolEvent``. Returns the result; the caller is
    /// responsible for appending the resulting tool ``ChatMessage`` to history.
    ///
    /// Used by the cloud loop (after each tool-call round) and by the
    /// ``InlineToolRunner`` closure (for local models, mid-stream).
    func executeToolCall(
        _ call: ToolCall, agent: Agent, executor: ToolExecutor
    ) async -> ToolResult {
        let permission = permissionPolicy.permissionLevel(for: call.function.name)
        let eventID = call.id
        let toolName = call.function.name
        toolEvents.append(
            ToolEvent(
                id: eventID, toolName: toolName, status: .executing,
                arguments: call.function.arguments
            )
        )

        let executionMode = executor.executionMode(for: call.function.name)
        let result: ToolResult
        switch permission {
        case .always:
            switch executionMode {
            case .interactive:
                isAwaitingUserInteraction = true
                result = await executor.execute(call, agent: agent)
                isAwaitingUserInteraction = false
            case .background:
                result = await executeWithTimeout(call, agent: agent, executor: executor)
            }
        case .never:
            result = ToolResult(
                toolCallID: call.id,
                content: ToolHelpers
                    .output(errors: [Localized.Permission.toolDeniedByPolicy]),
                isError: true
            )
            updateToolEvent(id: eventID, status: .denied)
        case .ask:
            if let agentPolicy = permissionPolicy as? AgentPermissionPolicy,
               !agentPolicy.canPromptUser
            {
                result = ToolResult(
                    toolCallID: call.id,
                    content: ToolHelpers.output(errors: [
                        "Permission required. Ask the user to open the app to grant permission for this action.",
                    ]),
                    isError: true
                )
                updateToolEvent(id: eventID, status: .denied)
            } else {
                let capabilities = ToolRegistry.capabilities(for: toolName)
                pendingPermission = PermissionRequest(
                    id: call.id,
                    toolName: toolName,
                    toolDisplayName: ToolRegistry.displayName(for: toolName)
                )
                updateToolEvent(id: eventID, status: .awaitingPermission)

                let response = await withCheckedContinuation {
                    (continuation: CheckedContinuation<PermissionResponse, Never>) in
                    self.permissionContinuation = continuation
                }
                pendingPermission = nil

                switch response {
                case .allowOnce:
                    result = await executeWithTimeout(call, agent: agent, executor: executor)
                case .allowForChat:
                    onChatGrant?(capabilities)
                    if var agentPolicy = permissionPolicy as? AgentPermissionPolicy {
                        agentPolicy.grantForChat(capabilities)
                        permissionPolicy = agentPolicy
                    }
                    result = await executeWithTimeout(call, agent: agent, executor: executor)
                case .deny:
                    result = ToolResult(
                        toolCallID: call.id,
                        content: ToolHelpers.output(errors: ["User denied this action."]),
                        isError: true
                    )
                    updateToolEvent(id: eventID, status: .denied)
                }
            }
        }

        AppLogger.debug(
            "Tool \(public: toolName) result: isError=\(public: result.isError), content=\(private: result.content.prefix(100))",
            category: .chat
        )

        if result.isError {
            updateToolEvent(id: eventID, status: .error(result.content))
        } else {
            updateToolEvent(id: eventID, status: .completed)
        }

        return result
    }

    private func executeWithTimeout(
        _ call: ToolCall, agent: Agent, executor: ToolExecutor
    ) async -> ToolResult {
        let timeout = toolExecutionTimeout
        // Race the tool execution against a sleep timer.
        // We use a continuation + atomic flag to ensure exactly one resume.
        let resumed = OSAllocatedUnfairLock(initialState: false)
        return await withCheckedContinuation {
            (continuation: CheckedContinuation<ToolResult, Never>) in
            let cont = continuation
            let workTask = Task { @MainActor in
                let r = await executor.execute(call, agent: agent)
                let shouldResume = resumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if shouldResume { cont.resume(returning: r) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                let shouldResume = resumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if shouldResume {
                    workTask.cancel()
                    cont.resume(
                        returning: ToolResult(
                            toolCallID: call.id,
                            content: ToolHelpers.output(errors: [
                                "Tool timed out after \(Int(timeout.components.seconds))s",
                            ]),
                            isError: true
                        )
                    )
                }
            }
        }
    }

    private func buildCheckpoint() -> [ChatMessage] {
        // Only return messages up to the last complete round to avoid
        // orphaned tool calls (assistant with tool_calls but missing results).
        var result = Array(produced.prefix(safeProducedCount))

        // Append partial prose if we're streaming content without pending tool calls.
        if chatPhase == .streamingProse, !contentBuffer.isEmpty, pendingToolCalls.isEmpty {
            result.append(ChatMessage(role: "assistant", content: contentBuffer))
        }

        return result
    }
}
