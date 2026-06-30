import Foundation
@preconcurrency import LiteRTLM

/// On-device LLM inference for Gemma 4 E2B via Google's LiteRT-LM runtime
/// (GPU/Metal backend, QAT mobile quantization, multi-token prediction).
///
/// A single LiteRT ``Engine`` is created once at load and reused. Generation
/// runs through a persistent ``Conversation`` so that prefix caching applies
/// across turns: when a request simply appends to the conversation we already
/// hold, only the new turn is sent and the prior KV cache is reused. When the
/// history diverges (new chat, edit, or regenerate) the conversation is rebuilt.
///
/// ```swift
/// let llm = try await GemmaRuntime.load(modelPath: url, contextWindow: 8192)
/// for await token in try await llm.stream(messages) {
///     print(token, terminator: "")
/// }
/// ```
///
/// The engine wrapper itself is model-agnostic: the only Gemma-specific detail
/// is the sampler defaults in ``makeConversation(seeding:)``. Gemma's chat
/// formatting (tool markers, message conversion, stream filtering) lives outside
/// this type. This is the natural seam to extract a generic `LiteRTRuntime` from
/// if a second LiteRT model is ever added.
public final class GemmaRuntime: @unchecked Sendable {
    private let engine: Engine
    private let contextWindow: Int

    /// The live conversation and the message history it already holds (excluding
    /// the response currently being generated). `nil` until the first turn.
    private var conversation: Conversation?
    private var ingested: [Message] = []

    /// Serializes generation: LiteRT allows only one session per engine, and
    /// foreground requests preempt background ones.
    private let gate = LiteRTSessionGate()

    /// Coarse per-turn runaway bound on streamed chunks. This is *not* the
    /// model's output limit — it spans the entire turn including every tool
    /// round, because LiteRT re-streams tool rounds through one continuation we
    /// can't split. Sized well above a single response (worst case: system +
    /// several tool rounds + final answer at 8k context) so multi-tool turns
    /// still reach their answer. LiteRT's recurringToolCallLimit is the real
    /// per-round ceiling.
    private static let maxTurnChunks = 2048

    // MARK: - Public Types

    /// A message in a multi-turn conversation.
    public struct Message: Sendable, Equatable {
        public enum Role: String, Sendable {
            case user, assistant, system, tool
        }

        public let role: Role
        public let content: String

        public init(role: Role, content: String) {
            self.role = role
            self.content = content
        }
    }

    private init(engine: Engine, contextWindow: Int) {
        self.engine = engine
        self.contextWindow = contextWindow
    }

    // MARK: - Loading

    /// Create and initialize a LiteRT engine for the given `.litertlm` model.
    ///
    /// Multi-token prediction (speculative decoding) is enabled when the build
    /// supports it; if engine initialization fails with it on, we retry once
    /// without it so a model lacking MTP heads still loads.
    /// Directory where LiteRT stores its compiled engine-graph cache. The cache
    /// can grow to several GB and is never pruned by LiteRT, so callers that
    /// remove the model (see ``GemmaModelManager/delete()``) must clear this too,
    /// otherwise the cache is orphaned in `Library/Caches` indefinitely.
    static var engineCacheDirectory: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("litert-lm", isDirectory: true)
    }

    public static func load(
        modelPath: URL,
        contextWindow: Int
    ) async throws -> GemmaRuntime {
        let cacheDir = engineCacheDirectory
        try? FileManager.default.createDirectory(
            at: cacheDir, withIntermediateDirectories: true
        )

        func makeEngine(speculative: Bool) throws -> Engine {
            if speculative {
                ExperimentalFlags.optIntoExperimentalAPIs()
                ExperimentalFlags.enableSpeculativeDecoding = true
            } else {
                ExperimentalFlags.enableSpeculativeDecoding = false
            }
            let config = try EngineConfig(
                modelPath: modelPath.path,
                backend: .gpu,
                maxNumTokens: contextWindow,
                cacheDir: cacheDir.path
            )
            return Engine(engineConfig: config)
        }

        let engine: Engine
        do {
            let e = try makeEngine(speculative: true)
            try await e.initialize()
            engine = e
            AppLogger.info("Gemma: LiteRT engine ready (MTP on)", category: .chat)
        } catch {
            AppLogger.warning(
                "Gemma: LiteRT init with MTP failed (\(public: error.localizedDescription)), retrying without speculative decoding",
                category: .chat
            )
            let e = try makeEngine(speculative: false)
            try await e.initialize()
            engine = e
            AppLogger.info("Gemma: LiteRT engine ready (MTP off)", category: .chat)
        }

        return GemmaRuntime(engine: engine, contextWindow: contextWindow)
    }

    /// Display name for logging.
    public var modelName: String {
        "gemma-4-E2B-it"
    }

    /// Maximum total tokens (prompt + generation) the engine is configured for.
    public var contextLength: Int {
        contextWindow
    }

    // MARK: - Generation

    /// Stream a response to the latest turn in `messages`.
    ///
    /// `messages` is the full conversation history. We diff it against the turns
    /// already ingested to decide whether to reuse the live conversation (append)
    /// or rebuild it (divergence), then stream a response to the trailing user
    /// turn. Streamed chunks are bounded for the whole turn by ``maxTurnChunks``.
    ///
    /// Pass `tools` to register bridged LiteRT tools for this turn, and
    /// `inlineToolRunner` to route their execution to the real Eigin tools. The
    /// engine handles declaration injection and output parsing natively, and
    /// calls each tool's `run()` inline as part of this stream; the runner is
    /// published via ``GemmaToolBridgeRunner`` only while the session gate is
    /// held, so it can't be clobbered by a concurrent stream.
    ///
    /// If the history is too long to fit in the context window, the oldest
    /// non-system turns are dropped and the conversation is rebuilt until it fits
    /// or only the final user message remains.
    func stream(
        _ messages: [Message],
        tools: [any LiteRTLM.Tool] = [],
        inlineToolRunner: InlineToolRunner? = nil
    ) async throws -> AsyncStream<String> {
        let (out, continuation) = AsyncStream<String>.makeStream()

        // Generation runs one at a time against the single engine session. We
        // read the caller's priority here (task-local) and gate the worker so a
        // foreground send can preempt background work. `box` lets the gate (or a
        // torn-down consumer) cancel the worker, which stops native decoding.
        let priority = LocalGeneration.priority
        let toolBox = BridgedToolBox(tools)
        let box = CancellationBox()
        let task = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }
            let acquired = await gate.acquire(priority: priority) { box.cancel() }
            if acquired {
                // Publish the turn's runner only while we hold the gate so the
                // bridge's run() (called across LiteRT's C boundary) reaches the
                // right executor. Setting it inside the gated span is what makes
                // the single module-global safe: a concurrently-created stream
                // can't overwrite it while we own the session.
                GemmaToolBridgeRunner.current = inlineToolRunner
                if !Task.isCancelled {
                    await streamInto(
                        continuation,
                        messages: messages,
                        tools: toolBox.tools
                    )
                }
                GemmaToolBridgeRunner.current = nil
                await gate.release()
            }
            continuation.finish()
        }
        box.task = task
        continuation.onTermination = { _ in box.cancel() }

        return out
    }

    private func streamInto(
        _ continuation: AsyncStream<String>.Continuation,
        messages: [Message],
        tools: [any LiteRTLM.Tool]
    ) async {
        // The caller (`stream`) owns stream termination and session release; this
        // method only yields chunks. It returns on success, overflow exhaustion,
        // or failure.

        // Retry loop: on context overflow, drop the oldest non-system turn pair
        // and rebuild until the history fits or we're down to the bare minimum.
        //
        // Session ownership: LiteRT allows only one active session per engine.
        // We ensure the previous Conversation is fully deallocated before calling
        // makeConversation again by (a) nil-ing self.conversation and (b) keeping
        // the Conversation reference inside a nested scope so ARC releases it
        // synchronously before the next await on the engine.
        var candidates = messages
        while true {
            let plan: Plan
            do {
                plan = try await makePlan(for: candidates, tools: tools)
            } catch {
                AppLogger.error(
                    "Gemma: failed to create conversation: \(private: error.localizedDescription)",
                    category: .chat
                )
                break
            }

            // Run generation inside a separate function so the Conversation
            // reference (read from self.conversation into a local `conv`) is
            // released when generateOnce returns — before the next loop
            // iteration calls makeConversation on the engine.
            let result = await generateOnce(
                plan: plan,
                tools: tools,
                continuation: continuation,
                candidates: candidates
            )

            switch result {
            case .success(let assistant, let ingestedAfter):
                ingested = ingestedAfter + [Message(role: .assistant, content: assistant)]
                return
            case .overflow(let shorter):
                // Explicitly close the conversation so the LiteRT session slot is
                // freed synchronously before makePlan creates the next one.
                // We cannot rely on ARC/deinit across async suspension points.
                conversation?.close()
                conversation = nil
                ingested = []
                candidates = shorter
            case .failure:
                break
            }

            if case .failure = result { break }
        }
    }

    private enum GenerationResult {
        case success(assistant: String, ingestedAfter: [Message])
        case overflow([Message])
        case failure
    }

    /// Runs a single generation attempt and returns a typed result.
    /// The Conversation is captured as a local inside this function and released
    /// when the function returns — before the caller's next loop iteration.
    private func generateOnce(
        plan: Plan,
        tools: [any LiteRTLM.Tool],
        continuation: AsyncStream<String>.Continuation,
        candidates: [Message]
    ) async -> GenerationResult {
        guard let conv = conversation else {
            AppLogger.error("Gemma: no active conversation after makePlan", category: .chat)
            return .failure
        }
        var assistant = ""
        // `produced` counts chunks for the whole turn, including every tool
        // round: LiteRT re-enters sendMessageStream for each round on the *same*
        // Swift continuation, so this one loop sees them all and there is no
        // round boundary we can observe to reset on. The cap is therefore a
        // coarse per-turn runaway bound, deliberately sized well above a single
        // response so multi-tool turns can still reach their final answer. The
        // real per-tool-round ceiling is LiteRT's own recurringToolCallLimit.
        var produced = 0
        do {
            // Cancel native decoding when the consuming task is torn down (user
            // interrupt or navigation). LiteRT's stream does not stop generation
            // on Swift-task cancellation by itself.
            try await withTaskCancellationHandler {
                for try await chunk in conv.sendMessageStream(plan.prompt) {
                    let text = chunk.toString
                    if !text.isEmpty {
                        assistant += text
                        continuation.yield(text)
                    }
                    produced += 1
                    if produced >= Self.maxTurnChunks { break }
                }
            } onCancel: {
                try? conv.cancel()
            }
        } catch {
            // conv goes out of scope here (function returns) — ARC releases it.
            switch LiteRTErrorClassifier.classify(error) {
            case .contextOverflow:
                if let shorter = Self.dropOldestTurn(candidates) {
                    AppLogger.warning(
                        "Gemma: context overflow, retrying with \(public: shorter.count) messages",
                        category: .chat
                    )
                    return .overflow(shorter)
                }
            case .unknownToolCall(let badName):
                // The model called an invalid or unregistered tool name. The
                // conversation is now in an error state — close it so the next
                // round rebuilds cleanly. Yield a synthetic error token so the
                // user sees something rather than a silent empty response.
                AppLogger.warning(
                    "Gemma: unknown tool '\(public: badName)' — resetting conversation",
                    category: .chat
                )
                conversation?.close()
                conversation = nil
                ingested = []
                let known = tools.map { type(of: $0).name }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                let msg = "I tried to call '\(badName)' but that tool doesn't exist. Available: \(known). Let me try again."
                continuation.yield(msg)
                return .success(assistant: msg, ingestedAfter: plan.ingestedAfter)
            case nil:
                break
            }
            AppLogger.error(
                "Gemma: generation error: \(private: error.localizedDescription)",
                category: .chat
            )
            return .failure
        }
        return .success(assistant: assistant, ingestedAfter: plan.ingestedAfter)
    }

    /// Drop the oldest non-system turn (user + the assistant reply that follows
    /// it, if present) from `messages`. Returns nil when there is nothing left
    /// to drop (only system + one pending user turn remain).
    static func dropOldestTurn(_ messages: [Message]) -> [Message]? {
        // Find the first user turn that isn't the last message.
        guard let firstUser = messages.firstIndex(where: { $0.role == .user }),
              firstUser < messages.count - 1
        else { return nil }

        var result = messages
        // Also drop the assistant reply immediately following, if present.
        if firstUser + 1 < result.count, result[firstUser + 1].role == .assistant {
            result.remove(at: firstUser + 1)
        }
        result.remove(at: firstUser)
        return result
    }

    /// Drop conversation state so the next ``stream(_:tools:inlineToolRunner:)`` starts fresh.
    public func reset() {
        conversation?.close()
        conversation = nil
        ingested = []
    }

    // MARK: - Conversation planning

    private struct Plan {
        /// LiteRT-LM message ready to pass to `sendMessageStream`.
        let prompt: LiteRTLM.Message
        /// History that will be ingested once generation completes (everything
        /// in `messages` except the assistant turn being generated).
        let ingestedAfter: [Message]
    }

    /// Whether to reuse the live conversation or rebuild it, plus the turn split.
    struct PlanDecision: Equatable {
        enum Mode { case reuse, rebuild }
        let mode: Mode
        /// Context before the trailing user/tool run (system + prior turns).
        let priorTurns: [Message]
        /// The trailing user/tool run we generate a reply to.
        let pendingTurns: [Message]

        /// The pending turns flattened into a single prompt body.
        var promptText: String {
            pendingTurns
                .map(\.content)
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
    }

    /// Pure prefix-diff: split `messages` at the last assistant turn, then reuse
    /// the live conversation only when it already holds exactly the prior turns
    /// (LiteRT retains the assistant turns it generated). Otherwise rebuild.
    /// Extracted as a static function so the decision is unit-testable without a
    /// live engine.
    static func planDecision(
        messages: [Message],
        ingested: [Message],
        hasConversation: Bool
    ) -> PlanDecision {
        // Prior context ends after the last assistant, tool-response, or system
        // turn; the trailing user turn(s) are what we generate a reply to.
        // Keeping system in the prior turns routes it to the conversation's
        // system slot rather than the prompt body.
        let splitIndex = messages
            .lastIndex { $0.role == .assistant || $0.role == .tool || $0.role == .system }
            .map { $0 + 1 } ?? 0
        let priorTurns = Array(messages[..<splitIndex])
        let pendingTurns = Array(messages[splitIndex...])
        let mode: PlanDecision.Mode = (hasConversation && ingested == priorTurns)
            ? .reuse : .rebuild
        return PlanDecision(mode: mode, priorTurns: priorTurns, pendingTurns: pendingTurns)
    }

    /// Decide whether to reuse the live conversation or rebuild it, and produce
    /// the single ``Message`` to stream a response to.
    ///
    /// When `tools` change between turns the conversation is always rebuilt so
    /// the new declarations are injected into the chat template correctly.
    private func makePlan(
        for messages: [Message],
        tools: [any LiteRTLM.Tool]
    ) async throws -> Plan {
        let decision = Self.planDecision(
            messages: messages,
            ingested: ingested,
            hasConversation: conversation != nil
        )
        let prompt = LiteRTLM.Message(decision.promptText, role: .user)

        // Fast path: the live conversation already holds the prior turns, so we
        // only send the new pending turns and reuse the cached prefix.
        // Skip if tools are present — tool declarations must be re-injected via
        // ConversationConfig on rebuild for correct chat template placement.
        if decision.mode == .reuse, conversation != nil, tools.isEmpty {
            return Plan(prompt: prompt, ingestedAfter: messages)
        }

        // Rebuild path: divergence, tools present, or new chat.
        conversation?.close()
        conversation = nil
        ingested = []

        conversation = try await makeConversation(seeding: decision.priorTurns, tools: tools)
        return Plan(prompt: prompt, ingestedAfter: messages)
    }

    private func makeConversation(
        seeding priorTurns: [Message],
        tools: [any LiteRTLM.Tool] = []
    ) async throws -> Conversation {
        // Pass prior turns as properly-roled LiteRT messages so the engine
        // applies Gemma's real chat template internally, rather than the
        // hand-rolled "Conversation so far:" transcript we used before.
        let systemMessage: LiteRTLM.Message? = priorTurns
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n")
            .nilIfEmpty
            .map { LiteRTLM.Message($0, role: .system) }

        let initialMessages: [LiteRTLM.Message] = priorTurns
            .filter { $0.role != .system }
            .compactMap { msg in
                guard !msg.content.isEmpty else { return nil }
                let role: LiteRTLM.Role = switch msg.role {
                case .assistant: .model
                case .tool: .tool
                default: .user
                }
                return LiteRTLM.Message(msg.content, role: role)
            }

        AppLogger.debug(
            "Gemma: makeConversation with \(public: tools.count) tools: \(public: tools.map { type(of: $0).name })",
            category: .chat
        )

        // Enable constrained decoding when tools are active so LiteRT's FST
        // prevents the model generating invalid tool call syntax.
        if !tools.isEmpty {
            ExperimentalFlags.enableConversationConstrainedDecoding = true
        }
        defer {
            ExperimentalFlags.enableConversationConstrainedDecoding = false
        }

        // Sampler values are Gemma 4's official defaults from Google's model
        // card (temperature 1.0, top-p 0.95, top-k 64). Do not "tune" these
        // without a deliberate reason — they are the recommended configuration.
        let config = try ConversationConfig(
            systemMessage: systemMessage,
            initialMessages: initialMessages,
            tools: tools,
            samplerConfig: SamplerConfig(topK: 64, topP: 0.95, temperature: 1.0)
        )
        return try await engine.createConversation(with: config)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// Holds the worker ``Task`` so the session gate (or a torn-down consumer) can
/// cancel generation from outside the task. The handle is written once right
/// after the task is created and only read when cancelling, so a lock keeps the
/// cross-thread access well-defined.
private final class CancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<Void, Never>?

    var task: Task<Void, Never>? {
        get { lock.withLock { _task } }
        set { lock.withLock { _task = newValue } }
    }

    func cancel() {
        task?.cancel()
    }
}
