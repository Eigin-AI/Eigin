import EiginSDK
import Factory
import Foundation
import os
import SwiftData
import SwiftUI

/// A completed request that left the user without a final reply.
enum TurnCompletionError: Error {
    case missingReply
}

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

/// Supplies app capabilities and presentation for an SDK-owned chat turn.
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
    var propagatesStreamCancellation = false
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
    private var permissionWaits: [(
        request: PermissionRequest,
        continuation: CheckedContinuation<PermissionResponse, Never>
    )] = []
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

    private var activeOperation: EiginSDK.Experimental.Agent.ChatTurn?
    private var operationID = UUID()
    private var messageMapping = TurnMessageMapping()
    private var producedMessages: [ChatMessage] = []
    private(set) var roundsExecuted = 0
    private(set) var contentBuffer = ""
    private(set) var committedMessages: [ChatMessage] = []
    var chatPhase: ChatPhase = .idle

    private var hasToolCalls = false
    private var shouldStop = false
    private var pagingSession: ContextPagingSession?
    private var pagingHistory: Set<String> = []
    private var pagingAgentID: UUID?

    @ObservationIgnored
    @Injected(\.modelRouter) var modelRouter

    @ObservationIgnored
    @Injected(\.providerModelRefresher) var modelRefresher

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

    /// Runs an SDK turn with app context and presentation.
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
        conversationID: UUID? = nil,
        continuationInstruction: String? = nil
    ) async throws -> [ChatMessage] {
        reset()
        activeModel = model ?? agent.model
        throttler.start()
        let token = operationID
        let paging: ContextPagingSession
        if conversationID == nil {
            let historyIDs = Set(messages.filter { $0.role == "user" }.map(\.localID))
            if pagingAgentID != agent.id || pagingHistory
                .isDisjoint(with: historyIDs)
            {
                pagingSession = ContextPagingSession()
            }
            paging = pagingSession ?? ContextPagingSession()
            pagingSession = paging
            pagingHistory = historyIDs
            pagingAgentID = agent.id
        } else {
            paging = try ContextPagingSession(agent: agent, chatID: conversationID)
        }
        let context = await modelRouter.inferenceContext()
        guard operationID == token else { return [] }
        let host = ChatTurnHost(
            request: .init(
                messages: messages,
                tools: tools,
                agent: agent,
                provider: provider,
                model: activeModel,
                cacheKey: cacheKey,
                sentAt: sentAt,
                routing: routing,
                conversationID: conversationID,
                initialInstruction: continuationInstruction,
                propagatesStreamCancellation: propagatesStreamCancellation
            ),
            environment: .init(
                paging: paging,
                routing: context,
                chatService: chatService,
                executor: toolExecutor,
                refreshCatalog: catalogRefresh(agent: agent)
            )
        )
        let operation = host.makeTurn(presentation: self, token: token)
        messageMapping = host.mapping
        activeOperation = operation
        do {
            let entries = try await operation.run()
            guard operationID == token else { return [] }
            roundsExecuted = Int(operation.roundsExecuted)
            guard !shouldStop else { return [] }
            producedMessages = host.messages(entries)
            return producedMessages
        } catch {
            guard operationID == token, !shouldStop else { return [] }
            roundsExecuted = Int(operation.roundsExecuted)
            throw ChatTurnErrorConversion.restore(error, errors: host.errors)
        }
    }

    func isCurrentOperation(_ token: UUID) -> Bool {
        operationID == token
    }

    var acceptsTurnWork: Bool {
        !shouldStop
    }

    func preparingRequest() {
        roundsExecuted = Int(activeOperation?.roundsExecuted ?? 0)
    }

    func receive(_ event: EiginSDK.Experimental.Agent.ChatEvent, host: ChatTurnHost) async {
        roundsExecuted = Int(activeOperation?.roundsExecuted ?? 0)
        switch event {
        case .draft(let id):
            throttler.resetKeepingPhase(.waiting)
            contentBuffer = ""
            hasToolCalls = false
            currentMessageID = "msg-\(UUID().uuidString)"
            messageMapping.draft(id, localID: currentMessageID)
            if roundsExecuted > 0 { chatPhase = .streamingProse }
        case .requestOpened:
            chatPhase = .streamingProse
        case .modelSelected(let model, let retry):
            if model != activeModel {
                activeModel = model
                if retry,
                   host.request.agent.providerID == host.request.provider
                   .id { host.request.agent.model = model }
            }
        case .inference(let event):
            contentBuffer = activeOperation?.partialContent ?? ""
            switch event {
            case .contentDelta(let delta):
                chatPhase = .streamingProse
                throttler.feed(delta)
                onContentDelta?(delta)
            case .toolCall:
                hasToolCalls = true
                chatPhase = .streamingTools
            case .finished(let reason):
                chatPhase = reason == .toolCalls && hasToolCalls ? .readyToExecute : .streamingProse
            default: break
            }
        case .requestReported: break
        case .output:
            committedMessages = messageMapping.messages(activeOperation?.retainedOutput() ?? [])
            if chatPhase == .executingTools,
               !contentBuffer.isEmpty { throttler.resetKeepingPhase(.waiting) }
        case .finished:
            chatPhase = .done
        }
    }

    func finishToolProse(hasProse: Bool) async {
        chatPhase = .executingTools
        if hasProse {
            onSegmentEnd?()
            throttler.finish()
            await waitForThrottlerDrain()
        } else { throttler.resetKeepingPhase(.waiting) }
    }

    func beforeTool(_ call: EiginSDK.Experimental.Inference.ToolCall) async {
        seedToolEvent(id: call.id, toolName: call.name, arguments: call.arguments)
        await beforeToolCall?(call.name)
    }

    func drain() async {
        throttler.finish()
        await waitForThrottlerDrain()
    }

    /// Commits the current round: captures produced messages and settles streaming
    /// state. Call synchronously before appending to the display message list so
    /// SwiftUI batches both changes in one update cycle.
    func completeRound() -> [ChatMessage] {
        let messages = producedMessages
        settle()
        return messages
    }

    /// Clears streaming state after the caller has committed produced messages.
    /// Call this synchronously after appending to `displayMessages` so SwiftUI
    /// batches both changes (committed messages appear + streaming item disappears).
    func settle() {
        throttler.reset()
        activeOperation?.cancel()
        activeOperation = nil
        contentBuffer = ""
        toolEvents = []
        operationID = UUID()
        messageMapping = TurnMessageMapping()
        producedMessages = []
        committedMessages = []
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
        activeOperation?.cancel()
        activeOperation = nil
        contentBuffer = ""
        operationID = UUID()
        messageMapping = TurnMessageMapping()
        producedMessages = []
        committedMessages = []
        shouldStop = false
        pendingBrowsing = nil
        pendingOptions = nil
        pendingConnection = nil
        isAwaitingUserInteraction = false
        currentMessageID = ""
    }

    /// Resolves only the displayed request; late and duplicate responses are ignored.
    func resolvePermission(_ response: PermissionResponse, requestID: String) {
        guard let first = permissionWaits.first, first.request.id == requestID else { return }
        permissionWaits.removeFirst()
        pendingPermission = permissionWaits.first?.request
        first.continuation.resume(returning: response)
    }

    /// Queues a permission request until its own response arrives.
    func requestPermission(_ request: PermissionRequest) async -> PermissionResponse {
        guard !shouldStop else { return .deny }
        return await withCheckedContinuation { continuation in
            permissionWaits.append((request, continuation))
            pendingPermission = permissionWaits.first?.request
        }
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
        guard chatPhase != .idle else { return [] }
        shouldStop = true
        let checkpoint = activeOperation?.stop() ?? []
        throttler.abort()
        // Cancel any pending permission prompt
        let waits = permissionWaits
        permissionWaits.removeAll()
        pendingPermission = nil
        for wait in waits {
            wait.continuation.resume(returning: .deny)
        }
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
        return messageMapping.messages(checkpoint)
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
    /// updates the chat-feed ``ToolEvent``. SDK turns record accepted results.
    /// Gatekeeper callers retain their separate initial-call persistence path.
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

        var requestedCapabilities: [ToolCapability] = []
        let outcome = await EiginSDK.Experimental.Agent.runTool(
            permission: ToolRunnerSDKConversion.permission(permission),
            canPrompt: (permissionPolicy as? AgentPermissionPolicy)?.canPromptUser ?? true,
            interactive: executor.executionMode(for: toolName) == .interactive,
            prompt: {
                requestedCapabilities = ToolRegistry.capabilities(for: toolName)
                let request = PermissionRequest(
                    id: call.id, toolName: toolName,
                    toolDisplayName: ToolRegistry.displayName(for: toolName),
                    disclosure: executor.disclosure(for: call)
                )
                updateToolEvent(id: eventID, status: .awaitingPermission)
                return await ToolRunnerSDKConversion.grant(requestPermission(request))
            },
            granted: { forChat in
                if forChat {
                    onChatGrant?(requestedCapabilities)
                    if var policy = permissionPolicy as? AgentPermissionPolicy {
                        policy.grantForChat(requestedCapabilities)
                        permissionPolicy = policy
                    }
                }
                seedToolEvent(id: eventID, toolName: toolName, arguments: call.function.arguments)
            },
            interactionChanged: { awaiting in
                guard awaiting || (!Task.isCancelled && !shouldStop) else { return }
                isAwaitingUserInteraction = awaiting
            },
            execute: { await executor.execute(call, agent: agent) }
        )
        let result: ToolResult
        switch outcome {
        case .executed(let value): result = value
        case .denied(let reason):
            result = ToolResult(
                toolCallID: eventID,
                content: ToolHelpers.output(errors: [ToolRunnerSDKConversion.error(reason)]),
                isError: true
            )
            updateToolEvent(id: eventID, status: .denied)
        case .timedOut(let seconds):
            result = ToolResult(
                toolCallID: eventID,
                content: ToolHelpers.output(errors: ["Tool timed out after \(seconds)s"]),
                isError: true
            )
        }

        guard !Task.isCancelled, !shouldStop else { return result }
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

    /// Captures completed work and partial prose for persistence after a failure.
    func buildCheckpoint() -> [ChatMessage] {
        messageMapping.messages(activeOperation?.checkpoint() ?? [])
    }
}
