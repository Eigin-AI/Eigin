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

    /// ID of the last assistant message from the most recent completed round.
    /// Read by the view layer for footer fade-in animation. Cleared on `reset()`.
    private(set) var lastStreamedItemID: String?

    let isBootstrap: Bool
    /// Optional callback fired on each content delta (used by live call for streaming TTS).
    var onContentDelta: ((String) -> Void)?
    /// Callback fired when the user grants "allow for chat" — caller persists the grants.
    var onChatGrant: (([ToolCapability]) -> Void)?
    private(set) var throttler: any StreamThrottling
    var permissionPolicy: ToolPermissionPolicy
    private var permissionContinuation: CheckedContinuation<PermissionResponse, Never>?
    private var browsingContinuation: CheckedContinuation<BrowsingResult, Never>?

    /// Optional callback checked after each tool execution round.
    /// Return `true` to stop the loop early (e.g. background decision tool fired).
    var shouldTerminate: (() -> Bool)?

    /// Optional callback invoked after each tool execution round to rebuild the tool
    /// registry (e.g. when a skill is activated mid-turn). Returns updated definitions
    /// and executor for subsequent rounds.
    var onToolsChanged: (() -> (tools: [ToolDefinition], executor: ToolExecutor))?

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

    /// Block splitter for streaming content.
    private let blockSplitter: StreamingBlockSplitter

    /// Message ID for the current streaming turn (used for block ID stability).
    private var currentMessageID: String = ""

    var blocks: [ContentBlock] {
        blockSplitter.allBlocks
    }

    var splitter: StreamingBlockSplitter {
        blockSplitter
    }

    init(
        isBootstrap: Bool, throttler: any StreamThrottling = StreamThrottler(),
        permissionPolicy: ToolPermissionPolicy = AlwaysAllowPolicy()
    ) {
        self.isBootstrap = isBootstrap
        self.throttler = throttler
        self.permissionPolicy = permissionPolicy
        blockSplitter = StreamingBlockSplitter(throttler: throttler)
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
        toolExecutor: ToolExecutor
    ) async throws -> [ChatMessage] {
        reset()
        shouldStop = false
        currentMessageID = "msg-\(UUID().uuidString)"
        blockSplitter.setMessageID(currentMessageID)
        throttler.start()
        blockSplitter.start()

        var allMessages = messages
        var currentTools = tools
        var currentExecutor: ToolExecutor = toolExecutor

        for round in 0 ..< maxRounds {
            roundsExecuted = round + 1
            if shouldStop { return [] }
            AppLogger.debug(
                "Round \(public: round): sending \(public: allMessages.count) messages",
                category: .chat
            )

            let stream = try await chatService.chatCompletionEventStream(
                baseURL: provider.baseURL,
                providerID: provider.id,
                messages: allMessages,
                model: agent.model,
                tools: currentTools
            )

            contentBuffer = ""
            pendingToolCalls = []
            var finishReason: ChatStreamEvent.FinishReason = .stop
            var capturedProviderMetadata: [String: String]?

            chatPhase = .streamingProse

            do {
                for try await event in stream {
                    if shouldStop { return [] }

                    switch event {
                    case .contentDelta(let delta):
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
                return []
            }

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

                // Build the assistant message with tool calls (include provider metadata if
                // present)
                let assistantMessage = ChatMessage(
                    role: "assistant",
                    content: contentBuffer.isEmpty ? nil : contentBuffer,
                    toolCalls: pendingToolCalls,
                    providerMetadata: capturedProviderMetadata
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

                    let permission = permissionPolicy.permissionLevel(for: call.function.name)

                    let eventID = call.id
                    let toolName = call.function.name
                    toolEvents.append(
                        ToolEvent(
                            id: eventID, toolName: toolName, status: .executing,
                            arguments: call.function.arguments
                        )
                    )

                    let result: ToolResult
                    switch permission {
                    case .always:
                        result = await executeWithTimeout(
                            call, agent: agent, executor: currentExecutor
                        )
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
                                result = await executeWithTimeout(
                                    call, agent: agent, executor: currentExecutor
                                )
                            case .allowForChat:
                                onChatGrant?(capabilities)
                                if var agentPolicy = permissionPolicy as? AgentPermissionPolicy {
                                    agentPolicy.grantForChat(capabilities)
                                    permissionPolicy = agentPolicy
                                }
                                result = await executeWithTimeout(
                                    call, agent: agent, executor: currentExecutor
                                )
                            case .deny:
                                result = ToolResult(
                                    toolCallID: call.id,
                                    content: ToolHelpers.output(errors: ["User denied this action."]
                                    ),
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
                    let updated = onToolsChanged()
                    currentTools = updated.tools
                    currentExecutor = updated.executor
                }

                // Prepare for the next round (already in .waiting from resetKeepingPhase)
                chatPhase = .streamingProse
                contentBuffer = ""
                pendingToolCalls = []
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

    /// Commits the current round: captures produced messages, tracks the last
    /// assistant ID for animation, and settles streaming state.
    /// Call synchronously before appending to the display message list so SwiftUI
    /// batches both changes in one update cycle.
    func completeRound() -> [ChatMessage] {
        let messages = produced
        if let last = messages.last(where: { $0.role == "assistant" }) {
            lastStreamedItemID = "msg-\(last.localID)"
        }
        settle()
        return messages
    }

    /// Clears streaming state after the caller has committed produced messages.
    /// Call this synchronously after appending to `displayMessages` so SwiftUI
    /// batches both changes (committed messages appear + streaming item disappears).
    func settle() {
        blockSplitter.seal()
        throttler.reset()
        blockSplitter.reset()
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
        blockSplitter.reset()
        toolEvents = []
        chatPhase = .idle
        contentBuffer = ""
        pendingToolCalls = []
        produced = []
        safeProducedCount = 0
        shouldStop = false
        lastStreamedItemID = nil
        pendingBrowsing = nil
        currentMessageID = ""
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

    /// Stops the stream and returns a checkpoint of safe messages.
    /// Returns only messages that were safely committed before the stop point.
    func stop() -> [ChatMessage] {
        guard chatPhase != .idle, chatPhase != .done else { return [] }
        shouldStop = true
        throttler.abort()
        blockSplitter.seal()
        // Cancel any pending permission prompt
        permissionContinuation?.resume(returning: .deny)
        permissionContinuation = nil
        pendingPermission = nil
        // Cancel any pending browsing request
        browsingContinuation?.resume(returning: .cancelled)
        browsingContinuation = nil
        pendingBrowsing = nil
        return buildCheckpoint()
    }

    // MARK: - Private

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
