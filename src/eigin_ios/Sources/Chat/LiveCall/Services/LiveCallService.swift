@preconcurrency import AVFoundation
import Factory
import SwiftData
import SwiftUI

/// Orchestrates turn-based voice conversation: listen → process → speak → repeat.
///
/// Uses ``CallManager`` (CallKit) to keep the session alive in the background
/// and show native call UI on the lock screen. Manages its own
/// ``DefaultDictationService`` instance and delegates streaming TTS to
/// ``DefaultSpeechService``. Uses ``AgenticChatLoop`` for chat completion
/// with tool support.
@Observable
@MainActor
final class LiveCallService: @unchecked Sendable {
    enum Phase: Equatable {
        case idle
        case listening
        case processing
        case speaking
    }

    enum ResponseSpeed: CaseIterable {
        case fast, balanced, slow

        var silenceThreshold: TimeInterval {
            switch self {
            case .fast: 1.0
            case .balanced: 2.0
            case .slow: 3.5
            }
        }

        var label: String {
            switch self {
            case .fast: Localized.Ui.fast
            case .balanced: Localized.Settings.balanced
            case .slow: Localized.Ui.slow
            }
        }

        var icon: Image {
            switch self {
            case .fast: Iconography.Functional.Speed.fast
            case .balanced: Iconography.Functional.Speed.balanced
            case .slow: Iconography.Functional.Speed.slow
            }
        }
    }

    // MARK: - Public State

    private(set) var phase: Phase = .idle
    private(set) var transcription = ""
    private(set) var error: String?
    private(set) var isMuted = false
    var isForegrounded = true
    var speakingText: String {
        speech.speakingText
    }

    var dictationState: AppDictationState {
        dictation.state
    }

    /// Display name of the currently executing or awaiting-permission tool, if any.
    var activeToolDisplayName: String? {
        let active = chatLoop.toolEvents.last(where: {
            $0.status == .executing || $0.status == .awaitingPermission
        })
        return active.map { ToolRegistry.displayName(for: $0.toolName) }
    }

    var messages: [ChatMessage] = []
    var responseSpeed: ResponseSpeed = .balanced

    // MARK: - Dependencies

    private var agent: Agent?
    private var provider: Provider?

    // MARK: - Permissions & Tool Context

    /// Permission policy inherited from the parent chat (with prompting disabled).
    private var permissionPolicy: AgentPermissionPolicy?
    /// Chat ID inherited from the parent chat for chat-scoped tools.
    private var chatID: UUID?
    /// Space ID inherited from the parent chat for space-scoped tools.
    private var spaceID: UUID?
    /// Space context inherited from the parent chat for system prompt.
    private var space: Space?
    /// Enabled MCP servers for per-turn tool discovery.
    private var mcpServers: [MCPServer] = []
    /// Pre/post-processor between the agent and the LLM.
    private var gatekeeper: Gatekeeper?
    /// Per-turn persistence callback provided by the caller.
    private var onPersist: (([ChatMessage]) -> Void)?
    /// Callback to persist chat-level tool grants to SwiftData.
    private var onChatGrant: (([ToolCapability]) -> Void)?
    /// Callback invoked with the underlying error when the call ends abnormally,
    /// so the parent chat can surface it after the call dismisses.
    private var onError: ((Error) -> Void)?

    // MARK: - CallKit

    private var callManager: CallManager {
        CallManager.shared
    }

    // MARK: - Dictation (own instance)

    private let dictation = DefaultDictationService()

    // MARK: - Audio Route

    private let routeCoordinator = AudioRouteCoordinator()

    // MARK: - Silence Detection

    private var silenceTask: Task<Void, Never>?
    private var lastTranscription = ""
    private var lastTranscriptionUpdate: Date = .now
    private var recoveringStartedAt: Date?

    /// Upper bound on route-change recovery before we treat it as a hard
    /// failure. Longer than DictationService's internal retry ladder so a slow
    /// but working handover isn't cut off, while a wedged one surfaces instead
    /// of being masked.
    private static let recoveryTimeout: TimeInterval = 12.0

    // MARK: - Chat

    private(set) var chatLoop = AgenticChatLoop(
        isBootstrap: false, throttler: PassthroughThrottler()
    )
    private var streamTask: Task<Void, Never>?

    // MARK: - Dictation Retry

    private var dictationRetries = 0
    private let maxDictationRetries = 5

    // MARK: - Error Termination

    /// True once a non-recoverable error has triggered the farewell + hang-up
    /// sequence, so `speech.onComplete` knows to end the call rather than
    /// resume listening.
    private var isEndingCall = false
    /// Upper bound on how long we wait for the farewell to finish speaking
    /// before hanging up anyway (e.g. if the TTS engine itself is broken).
    private static let errorFarewellWatchdogDuration: TimeInterval = 10.0

    /// How long tool execution waits for the spoken intent to finish after
    /// playback last made progress — long healthy speech keeps resetting the
    /// bound, only a stall releases the tool early.
    private static let preToolSpeechWait: TimeInterval = 25.0

    // MARK: - Sound

    private let soundManager = SoundManager()

    /// Play an audio cue to alert the user that a tool needs permission.
    func playPermissionSound() {
        soundManager.play(.attention)
    }

    // MARK: - Extracted Services

    private var speech: (any SpeechService)!

    // MARK: - Init

    init() {
        dictation.keepSessionActive = true
    }

    // MARK: - Public API

    func start(context: LiveCallContext) {
        agent = context.agent
        provider = context.provider
        messages = context.messages
        speech = Container.shared.speechService()
        isEndingCall = false
        speech.onComplete = { [weak self] in
            guard let self else { return }
            if isEndingCall {
                stop()
                return
            }
            guard phase == .speaking || phase == .processing else { return }
            startListeningPhase()
        }
        speech.onAudioStarted = { [weak self] in
            guard let self, phase == .processing else { return }
            startSpeakingPhase()
        }
        // Warm up the voice model now so its cold load isn't on the reply path.
        speech.voiceIdentifier = context.agent.voiceIdentifier
        speech.prepare()
        error = nil

        // Inherit chat permissions — prompting is dynamically gated by isForegrounded
        permissionPolicy = AgentPermissionPolicy(
            builtInGrants: context.permissionPolicy.builtInGrants,
            discoveredGrants: context.permissionPolicy.discoveredGrants,
            chatGrants: context.permissionPolicy.chatGrants,
            canPromptUser: isForegrounded
        )
        chatID = context.chatID
        spaceID = context.spaceID
        space = context.space
        gatekeeper = Gatekeeper(
            proactivity: context.agent.proactivity,
            knowledgeService: Container.shared.knowledgeService()
        )
        mcpServers = context.mcpServers
        onPersist = context.onPersist
        onChatGrant = context.onChatGrant
        onError = context.onError

        UIApplication.shared.isIdleTimerDisabled = true
        soundManager.preparePlayers()

        // Watch for Bluetooth/headphone/car route changes for the whole call
        // and rebuild the active audio graph when they settle.
        routeCoordinator.onRecover = { [weak self] in
            self?.handleRouteRecovery()
        }
        routeCoordinator.start()

        // Wire up callbacks on the shared CallManager for this session.
        callManager.onAudioActivated = { [weak self] in
            self?.handleAudioActivated()
        }
        callManager.onCallEnded = { [weak self] in
            self?.handleCallEnded()
        }
        callManager.onMuteChanged = { [weak self] muted in
            self?.handleMuteChanged(muted)
        }

        // CallKit will activate the audio session and call us back
        // via onAudioActivated, where we begin listening.
        let name = "\(context.agent.emoji) \(context.agent.name)"
        AppLogger.info(
            "Live call starting with agent \(public: context.agent.name)", category: .livecall
        )
        callManager.startCall(handle: name)
    }

    func stop() {
        AppLogger.info("Live call stopping", category: .livecall)
        silenceTask?.cancel()
        silenceTask = nil
        dictation.stop()
        speech.cancel()
        soundManager.stopAll()
        streamTask?.cancel()
        chatLoop.onContentDelta = nil
        chatLoop.onSegmentEnd = nil
        chatLoop.beforeToolCall = nil
        chatLoop.afterToolCall = nil
        chatLoop.abort()
        chatLoop.settle()

        phase = .idle
        isEndingCall = false
        UIApplication.shared.isIdleTimerDisabled = false

        routeCoordinator.stop()
        callManager.clearCallbacks()
        callManager.endCall()
    }

    /// Interrupts the agent during processing or speaking and returns to listening.
    func interrupt() {
        guard phase == .processing || phase == .speaking else { return }
        Haptics.medium()

        chatLoop.onContentDelta = nil
        chatLoop.onSegmentEnd = nil
        chatLoop.beforeToolCall = nil
        chatLoop.afterToolCall = nil
        speech.cancel()
        soundManager.stopAll()
        streamTask?.cancel()

        let checkpoint = chatLoop.stop()
        if !checkpoint.isEmpty {
            messages.append(contentsOf: checkpoint)
        }
        chatLoop.settle()

        startListeningPhase()
    }

    // MARK: - CallKit Callbacks

    private func handleAudioActivated() {
        guard phase == .idle else { return }
        startListeningPhase()
    }

    private func handleCallEnded() {
        // CallKit ended the call externally (e.g. real phone call came in).
        guard phase != .idle else { return }
        AppLogger.info("Call ended externally by CallKit", category: .livecall)
        silenceTask?.cancel()
        silenceTask = nil
        dictation.stop()
        speech.cancel()
        soundManager.stopAll()
        streamTask?.cancel()
        chatLoop.onContentDelta = nil
        chatLoop.onSegmentEnd = nil
        chatLoop.beforeToolCall = nil
        chatLoop.afterToolCall = nil
        chatLoop.abort()
        chatLoop.settle()

        routeCoordinator.stop()
        callManager.clearCallbacks()
        phase = .idle
        isEndingCall = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Audio Route Recovery

    /// Rebuild the active phase's audio graph after a route change, and keep the
    /// call off the ear receiver when nothing external is connected.
    private func handleRouteRecovery() {
        updateSpeakerRouting()
        switch phase {
        case .listening:
            AppLogger.info("Route changed — recovering dictation", category: .livecall)
            dictation.recover()
        case .speaking:
            AppLogger.info("Route changed — recovering speech", category: .livecall)
            speech.recover()
        case .processing, .idle:
            break
        }
    }

    /// Force the built-in speaker only when the sole output is the ear receiver;
    /// otherwise release any override so a connected Bluetooth/car route wins.
    private func updateSpeakerRouting() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let external = outputs.contains {
            $0.portType != .builtInReceiver && $0.portType != .builtInSpeaker
        }
        let receiverOnly = !external && outputs.contains { $0.portType == .builtInReceiver }
        do {
            try session.overrideOutputAudioPort(receiverOnly ? .speaker : .none)
        } catch {
            AppLogger.warning(
                "Speaker routing override failed: \(private: error.localizedDescription)",
                category: .livecall
            )
        }
    }

    private func handleMuteChanged(_ muted: Bool) {
        isMuted = muted
        if muted {
            dictation.stop()
        } else if phase == .listening {
            dictation.start()
        }
    }

    // MARK: - Phase Transitions

    private func startListeningPhase() {
        Haptics.light()
        transcription = ""

        lastTranscription = ""
        lastTranscriptionUpdate = .now
        dictationRetries = 0
        soundManager.stop(.waiting)
        soundManager.play(.dictationStarted)

        dictation.stop()
        let lang = Container.shared.languageManager().currentLanguage
        dictation.setLocale(Locale(identifier: lang.speechLocaleIdentifier))
        if let agent {
            let store = Container.shared.vocabularyStore()
            dictation.setContextualStrings(store.allWords(agentName: agent.name))
        }
        if !isMuted {
            dictation.start()
        }
        startSilenceDetection()

        if dictation.state == .listening {
            phase = .listening
        } else {
            Task { @MainActor in
                while dictation.state != .listening, dictation.state != .idle {
                    try? await Task
                        .sleep(for: .milliseconds(Int(Self.dictationReadyPollInterval * 1000)))
                }
                if case .listening = dictation.state {
                    phase = .listening
                }
            }
        }
    }

    private static let dictationReadyPollInterval: TimeInterval = 0.05

    private func startProcessingPhase() {
        silenceTask?.cancel()
        silenceTask = nil

        let text = dictation.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        dictation.stop()

        guard !text.isEmpty else {
            startListeningPhase()
            return
        }

        Haptics.medium()
        phase = .processing
        transcription = text

        soundManager.play(.dictationStopped)
        soundManager.play(.waiting, loops: 25)

        sendMessage(text)
    }

    private func startSpeakingPhase() {
        Haptics.medium()
        phase = .speaking
        soundManager.stop(.waiting)
    }

    /// Thinking state while tools run and the next model round warms up, so
    /// the silence reads as "working" instead of dead air. The waiting sound
    /// only starts if it isn't already looping — re-entry from different tool
    /// boundaries must not restart the cue.
    private func startThinkingPhase() {
        phase = .processing
        if !soundManager.isPlaying(.waiting) {
            soundManager.play(.waiting, loops: 25)
        }
    }

    // MARK: - Silence Detection

    private func startSilenceDetection() {
        silenceTask?.cancel()
        // Use Task.sleep in a MainActor-isolated loop instead of DispatchSourceTimer.
        // Task.sleep is scheduled through Swift concurrency's cooperative thread pool
        // and is not subject to the same GCD timer coalescing that throttles timers
        // when the app is backgrounded, even during an active CallKit audio session.
        silenceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.checkSilence()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func checkSilence() {
        guard phase == .listening else { return }

        // Dictation is recovering from an audio route change (e.g. BT
        // connect/disconnect). Reset the silence timer so we don't
        // prematurely end the turn while it reconnects. Add a timeout
        // so we don't get stuck in recovery forever.
        if dictation.isRecovering {
            if recoveringStartedAt == nil {
                recoveringStartedAt = .now
            }
            // Keep the turn alive while recovery is genuinely in progress.
            lastTranscriptionUpdate = .now
            // Only give up if recovery is wedged well past the retry ladder —
            // surface it as an error rather than silently proceeding deaf.
            if let started = recoveringStartedAt,
               Date.now.timeIntervalSince(started) >= Self.recoveryTimeout
            {
                recoveringStartedAt = nil
                AppLogger.error("Audio route recovery timed out", category: .livecall)
                error = Localized.Voice.recoveryFailed
                stop()
            }
            return
        }
        recoveringStartedAt = nil

        if case .error(let message) = dictation.state {
            if dictationRetries < maxDictationRetries {
                dictationRetries += 1
                AppLogger.warning(
                    "Dictation error, retry \(public: dictationRetries)/\(public: maxDictationRetries): \(private: message)",
                    category: .livecall
                )
                dictation.stop()
                let delay = min(2.0, 0.3 + Double(dictationRetries) * 0.3)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard let self, phase == .listening else { return }
                    dictation.start()
                }
            } else {
                AppLogger.error(
                    "Dictation failed after \(public: maxDictationRetries) retries: \(private: message)",
                    category: .livecall
                )
                error = message
                stop()
            }
            return
        }

        let current = dictation.transcription
        transcription = current

        if current != lastTranscription {
            lastTranscription = current
            lastTranscriptionUpdate = .now
        } else if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Date.now.timeIntervalSince(lastTranscriptionUpdate) >= responseSpeed
                  .silenceThreshold
        {
            startProcessingPhase()
        }
    }

    // MARK: - Skills

    @MainActor
    private func loadActiveSkills(agent: Agent) -> [Skill] {
        guard let chat = fetchChat(agent: agent) else { return [] }
        return chat.activeSkillEntries.compactMap {
            SkillCatalog.skill(forID: $0.skillID, mcpServers: mcpServers)
        }
    }

    @MainActor
    private func clearActiveSkills(agent: Agent) {
        fetchChat(agent: agent)?.clearActiveSkills()
    }

    @MainActor
    private func fetchChat(agent: Agent) -> Chat? {
        guard let chatID, let context = agent.modelContext else { return nil }
        let targetChatID = chatID
        var descriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.id == targetChatID }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Chat

    private func sendMessage(_ text: String) {
        guard let agent, let provider else { return }
        guard let policy = permissionPolicy else { return }
        let chatService = Container.shared.chatService()
        guard let gatekeeper else { return }

        let userMessage = ChatMessage(role: "user", content: text)
        messages.append(userMessage)
        onPersist?([userMessage])

        // Reset streaming TTS for next turn
        speech.reset()
        speech.voiceIdentifier = agent.voiceIdentifier

        // Build a policy with dynamic canPromptUser based on foreground state
        let livePolicy = AgentPermissionPolicy(
            builtInGrants: policy.builtInGrants,
            discoveredGrants: policy.discoveredGrants,
            chatGrants: policy.chatGrants,
            canPromptUser: isForegrounded
        )

        chatLoop = AgenticChatLoop(
            isBootstrap: false, throttler: PassthroughThrottler(), permissionPolicy: livePolicy
        )
        chatLoop.onChatGrant = { [weak self] capabilities in
            guard let self else { return }
            if var p = permissionPolicy {
                p.grantForChat(capabilities)
                permissionPolicy = p
            }
            onChatGrant?(capabilities)
        }
        chatLoop.onContentDelta = { [weak self] delta in
            guard let self, phase == .processing || phase == .speaking else { return }
            // Keep voice in sync so mid-turn changes (via SetPresentationTool) take effect.
            speech.voiceIdentifier = self.agent?.voiceIdentifier
            speech.feedDelta(delta)
        }
        chatLoop.onSegmentEnd = { [weak self] in
            guard let self, phase == .processing || phase == .speaking else { return }
            // Speak the pre-tool prose now instead of waiting for the whole
            // turn; open the stream again when the next round streams in.
            speech.flushSegment()
        }
        chatLoop.beforeToolCall = { [weak self] toolName in
            guard let self else { return }
            // Let the agent finish saying what it's about to do before acting
            // on it, so tool UI doesn't appear over unspoken speech. Bounded so
            // a playback stall can't freeze the turn.
            await speech.waitUntilPlaybackDrains(timeout: Self.preToolSpeechWait)
            // The drain also resumes on cancel/reset during teardown — don't
            // touch phase or sound after a hangup or interrupt.
            guard !Task.isCancelled, phase == .processing || phase == .speaking
            else { return }
            speech.markAudioEnded()
            // Thinking starts now for every tool. Prompted tools stay silent —
            // the permission beep is the cue; the waiting sound joins once the
            // request is granted (afterToolCall).
            let willPrompt = permissionPolicy?.permissionLevel(for: toolName) == .ask
            guard willPrompt == false else {
                phase = .processing
                return
            }
            startThinkingPhase()
        }
        chatLoop.afterToolCall = { [weak self] in
            guard let self else { return }
            // Back to thinking for the next round's model latency. The next
            // block's onAudioStarted flips us back to speaking.
            guard phase == .processing || phase == .speaking else { return }
            startThinkingPhase()
        }

        streamTask = Task { [weak self] in
            guard let self else { return }

            let activeSkills = loadActiveSkills(agent: agent)

            let turn = await MessagePipeline.prepareTurn(
                messages: messages, agent: agent, space: space,
                permissionPolicy: policy,
                spaceID: spaceID, chatID: chatID,
                mcpServers: mcpServers,
                activeSkills: activeSkills,
                activeFlow: fetchChat(agent: agent)?.activeFlow,
                gatekeeper: gatekeeper,
                mode: .liveCall,
                hasSpaces: false,
                needsCompaction: false
            )

            // Auto-compact if approaching context limits (silent, no progress UI)
            let compactionResult = await MessagePipeline.compactIfNeeded(
                apiMessages: turn.apiMessages,
                estimatedTokens: turn.estimatedTokens,
                contextWindow: turn.contextWindow,
                baseURL: provider.baseURL, providerID: provider.id,
                model: agent.model, chatService: Container.shared.chatService()
            )
            let apiMessages = compactionResult.apiMessages
            if let summary = compactionResult.summary {
                messages.append(summary)
                onPersist?([summary])
                clearActiveSkills(agent: agent)
            }

            // Rebuild tool registry mid-turn when skills are activated.
            chatLoop.onToolsChanged = { [weak self] in
                guard let self else {
                    return (tools: turn.registry.definitions, executor: turn.registry)
                }
                let updatedSkills = loadActiveSkills(agent: agent)
                // Connect only the MCP servers backing active skills — turn.mcpTools
                // reflects only what was active at turn start.
                let activeMCPSkillIDs = Set(updatedSkills.map(\.id))
                    .intersection(turn.mcpSkills.map(\.id))
                nonisolated(unsafe) let activeMCPServers = activeMCPSkillIDs.compactMap {
                    MCPServerSkill.server(forSkillID: $0, servers: mcpServers)
                }
                let mcpTools = await Container.shared.mcpServerManager()
                    .prepareTools(servers: activeMCPServers)
                let updatedRegistry = ToolRegistry.chat(
                    spaceID: spaceID, chatID: chatID,
                    agentID: agent.id,
                    permissionPolicy: policy,
                    activeSkills: BundledSkill.alwaysActive
                        + updatedSkills.filter { !$0.alwaysActive },
                    mcpTools: mcpTools,
                    mcpSkills: turn.mcpSkills
                )
                return (tools: updatedRegistry.definitions, executor: updatedRegistry)
            }

            do {
                let produced = try await chatLoop.run(
                    messages: apiMessages,
                    tools: turn.registry.definitions,
                    agent: agent, provider: provider,
                    chatService: chatService, toolExecutor: turn.registry,
                    cacheKey: chatID?.uuidString
                )
                messages.append(contentsOf: produced)
                onPersist?(produced)
                chatLoop.settle()
                chatLoop.onContentDelta = nil
                speech.finish()
            } catch is CancellationError {
                // Stopped by user
            } catch {
                guard !Task.isCancelled else {
                    // The user interrupted the turn (taking a turn cancels the
                    // in-flight request), which surfaces as URLError.cancelled
                    // rather than Swift's CancellationError. interrupt() already
                    // handles teardown and restarts listening — nothing to do.
                    return
                }
                AppLogger.error(
                    "Live call chat error: \(private: error.localizedDescription)",
                    category: .livecall
                )
                endCallWithError(error)
            }
        }
    }

    /// Ends the call gracefully after a non-recoverable error: speaks a canned
    /// localized farewell, surfaces the error to the parent chat, and hangs up
    /// once the farewell finishes (or after a watchdog timeout, whichever
    /// comes first).
    private func endCallWithError(_ error: Error) {
        guard phase != .idle else { return }

        silenceTask?.cancel()
        silenceTask = nil
        dictation.stop()
        soundManager.stopAll()
        chatLoop.abort()
        chatLoop.onContentDelta = nil
        chatLoop.onSegmentEnd = nil
        chatLoop.beforeToolCall = nil
        chatLoop.afterToolCall = nil

        onError?(error)
        isEndingCall = true

        phase = .speaking
        speech.reset()
        speech.voiceIdentifier = agent?.voiceIdentifier
        speech.feedDelta(Localized.Voice.errorFarewell)
        speech.finish()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.errorFarewellWatchdogDuration))
            guard let self, isEndingCall else { return }
            stop()
        }
    }
}

// MARK: - Preview Configuration

extension LiveCallService {
    /// Configures a freshly-initialized service for canvas preview of a specific phase.
    /// Only safe for previews — never call after `start(context:)`.
    func configureForPreview(phase: Phase, transcription: String = "") {
        self.phase = phase
        self.transcription = transcription
    }
}
