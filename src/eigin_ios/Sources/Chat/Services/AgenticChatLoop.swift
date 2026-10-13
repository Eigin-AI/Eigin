import Factory
import Foundation
import os
import SwiftData
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
    let disclosure: ToolDisclosure?
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
    private(set) var pendingConnection: CapabilityRequest?

    /// True while an interactive tool is executing (e.g. presenting options to the user).
    /// When true the view layer re-enables the input bar and hides the stop button.
    private(set) var isAwaitingUserInteraction = false

    let isBootstrap: Bool
    /// Optional callback fired on each content delta (used by live call for streaming TTS).
    var onContentDelta: ((String) -> Void)?
    /// Fired when a round ends with a tool call and prose was buffered for it
    /// (used by live call to flush TTS so pre-tool prose speaks while the tool
    /// executes). Not fired when the round had no prose.
    var onSegmentEnd: (() -> Void)?
    /// Awaited before executing each model-requested tool call — lets the
    /// caller sequence action after speech (e.g. live call letting the agent
    /// finish saying what it's about to do before the tool runs). Receives the
    /// tool name. Not awaited for gatekeeper-supplied initial calls or
    /// local-model inline tools.
    var beforeToolCall: ((String) async -> Void)?
    /// Fired after each model-requested tool call completes — lets the caller
    /// restore its waiting feedback once tool work is over.
    var afterToolCall: (() -> Void)?
    /// Callback fired when the user grants "allow for chat" — caller persists the grants.
    var onChatGrant: (([ToolCapability]) -> Void)?
    private(set) var throttler: any StreamThrottling
    var permissionPolicy: ToolPermissionPolicy
    private var permissionContinuation: CheckedContinuation<PermissionResponse, Never>?
    private var browsingContinuation: CheckedContinuation<BrowsingResult, Never>?
    private var optionsContinuation: CheckedContinuation<OptionSelection, Never>?
    private var connectionContinuation: CheckedContinuation<CapabilityConnectResult, Never>?

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

    var chatPhase: ChatPhase = .idle
    var contentBuffer = ""
    var pendingToolCalls: [ToolCall] = []
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

    /// Internal: shared with the loop's stream-opening and reporting extensions.
    @ObservationIgnored
    @Injected(\.modelRouter) var modelRouter

    @ObservationIgnored
    @Injected(\.providerModelRefresher) var modelRefresher

    /// Guards the catalog refresh so a turn re-fetches at most once.
    private var didRefreshCatalog = false

    /// The model this turn is running on. Usually the agent's, but an offline turn runs
    /// on-device without disturbing the provider and model the user chose.
    var activeModel = ""

    /// Message ID for the current streaming turn (used for block ID stability).
    var currentMessageID: String = ""

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

    /// When the user sent the message, for perceived-latency reporting. Nil for
    /// callers that don't have a user-visible send moment (tests, tools).
    var turnSentAt: ContinuousClock.Instant?

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
        model: String? = nil,
        sentAt: ContinuousClock.Instant? = nil,
        routing: RouteRequest? = nil,
        conversationID: UUID? = nil
    ) async throws -> [ChatMessage] {
        reset()
        turnSentAt = sentAt
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

            let turn = try await openStream(
                chatService: chatService,
                provider: provider,
                agent: agent,
                messages: allMessages,
                tools: currentTools,
                cacheKey: cacheKey,
                inlineToolRunner: inlineRunner,
                routing: routing,
                conversationID: conversationID
            )

            contentBuffer = ""
            pendingToolCalls = []
            var finishReason: ChatStreamEvent.FinishReason = .stop
            var capturedProviderMetadata: [String: String]?

            let stream = turn.stream
            let streamStart = turn.dispatchedAt
            let raceWinner = turn.raceWinner

            // Adopted once, before any reporting: the race winner becomes the
            // turn's model; see adoptTurnModel(_:).
            var turnModelAdopted = false

            chatPhase = .streamingProse

            // Measured from request dispatch: the first-token wait is spent inside openStream.
            var firstTokenAt: ContinuousClock.Instant?

            do {
                // `shouldStop` exits inside this loop return without a drain:
                // `handleStop()` commits `buildCheckpoint()` — including partial
                // prose — and replaces the streaming row in the same UI update.
                for try await event in stream {
                    if shouldStop { return [] }

                    if !turnModelAdopted {
                        turnModelAdopted = true
                        adoptTurnModel(turn, providerID: provider.id, agent: agent)
                    }

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
                // Either handleStop already committed partial prose via its
                // checkpoint, or the whole turn is being torn down — nothing
                // to preserve here.
                await reportAttempt(
                    provider: provider, start: streamStart,
                    firstTokenAt: firstTokenAt, result: .cancelled
                )
                return []
            } catch {
                logTurnTiming(
                    prep: turnSentAt.map { $0.duration(to: streamStart) },
                    modelTTFT: firstTokenAt.map { streamStart.duration(to: $0) },
                    result: .failed(RoutingFailure(from: error))
                )
                // The race's retry hook records everything it chases before
                // resurfacing an error; skip only that case. A failure after a
                // first token (mid-stream, the winner dying) is still unrecorded
                // and must count - it blames the model that carried the turn.
                if firstTokenAt == nil, turn.failureReported.withLock({ $0 }) {
                    // The race's retry hook already recorded this failure; only
                    // the timing is new information here.
                    logTurnTiming(
                        prep: turnSentAt.map { $0.duration(to: streamStart) },
                        modelTTFT: nil,
                        result: .failed(RoutingFailure(from: error))
                    )
                } else {
                    await reportAttempt(
                        provider: provider, start: streamStart,
                        firstTokenAt: firstTokenAt,
                        result: .failed(RoutingFailure(from: error))
                    )
                }
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
                    // Speak the pre-tool prose while the tool executes (live call).
                    onSegmentEnd?()
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

                    // Seed the live event before awaiting `beforeToolCall` —
                    // the TTS handoff can take seconds, and without an event
                    // the just-committed row would read as done.
                    seedToolEvent(
                        id: call.id,
                        toolName: call.function.name,
                        arguments: call.function.arguments
                    )

                    await beforeToolCall?(call.function.name)

                    let result = await executeToolCall(
                        call, agent: agent, executor: currentExecutor
                    )

                    afterToolCall?()

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
                // No drain needed: the round's prose was already drained and
                // committed before tool execution, and the throttler is parked
                // in .waiting with empty buffers.
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
        pendingConnection = nil
        isAwaitingUserInteraction = false
        currentMessageID = ""
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

    /// Asks the user to connect what a skill needs and suspends until the UI
    /// resolves it.
    func requestConnection(_ request: CapabilityRequest) async -> CapabilityConnectResult {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<CapabilityConnectResult, Never>) in
            self.connectionContinuation = continuation
            self.pendingConnection = request
        }
    }

    /// Resolves a pending connection request from the UI.
    func resolveConnection(_ result: CapabilityConnectResult) {
        connectionContinuation?.resume(returning: result)
        connectionContinuation = nil
        pendingConnection = nil
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
        // Cancel any pending connection: stopping isn't an answer
        connectionContinuation?.resume(returning: .cancelled)
        connectionContinuation = nil
        pendingConnection = nil
        // Cancel any pending interactive tool
        optionsContinuation?.resume(returning: .dismissed)
        optionsContinuation = nil
        pendingOptions = nil
        isAwaitingUserInteraction = false
        return buildCheckpoint()
    }

    // MARK: - Private

    private func updateToolEvent(id: String, status: ToolEventStatus) {
        if let index = toolEvents.firstIndex(where: { $0.id == id }) {
            toolEvents[index].status = status
        }
    }

    /// Appends an `.executing` event, or resets an existing one (both callers
    /// may seed before `executeToolCall`).
    private func seedToolEvent(id: String, toolName: String, arguments: String?) {
        if let index = toolEvents.firstIndex(where: { $0.id == id }) {
            toolEvents[index].status = .executing
        } else {
            toolEvents.append(
                ToolEvent(id: id, toolName: toolName, status: .executing, arguments: arguments)
            )
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
        seedToolEvent(
            id: eventID,
            toolName: toolName,
            arguments: call.function.arguments
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
                    toolDisplayName: ToolRegistry.displayName(for: toolName),
                    disclosure: executor.disclosure(for: call)
                )
                updateToolEvent(id: eventID, status: .awaitingPermission)

                let response = await withCheckedContinuation {
                    (continuation: CheckedContinuation<PermissionResponse, Never>) in
                    self.permissionContinuation = continuation
                }
                pendingPermission = nil

                switch response {
                case .allowOnce:
                    // Granted — resume the live executing state.
                    seedToolEvent(
                        id: eventID,
                        toolName: toolName,
                        arguments: call.function.arguments
                    )
                    result = await executeWithTimeout(call, agent: agent, executor: executor)
                case .allowForChat:
                    onChatGrant?(capabilities)
                    if var agentPolicy = permissionPolicy as? AgentPermissionPolicy {
                        agentPolicy.grantForChat(capabilities)
                        permissionPolicy = agentPolicy
                    }
                    seedToolEvent(
                        id: eventID,
                        toolName: toolName,
                        arguments: call.function.arguments
                    )
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

        // Recover prose buffered by an uncommitted round, whether stopped
        // mid-stream (.streamingProse) or after the stream ended with tool
        // calls pending (.readyToExecute). Committing prose alone is safe:
        // the round's tool calls are still pending, so leaving them out can't
        // orphan anything, and the round would otherwise commit nothing.
        if !contentBuffer.isEmpty, chatPhase == .streamingProse || chatPhase == .readyToExecute {
            result.append(ChatMessage(role: "assistant", content: contentBuffer))
        }

        return result
    }
}
