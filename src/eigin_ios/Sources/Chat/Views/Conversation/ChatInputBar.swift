import Factory
import SwiftUI

/// Chat-specific wrapper around ``AppChatInput``.
///
/// Handles dictation orchestration, send-mode selection, sounds, and haptics.
/// The actual UI lives in `AppChatInput`; this component owns the
/// chat-domain behaviour.
struct ChatInputBar: View {
    @Binding var text: String
    let isDisabled: Bool
    let onSend: (InteractionMode) -> Void
    var onStop: (() -> Void)?
    var isFocused: FocusState<Bool>.Binding
    var spaces: [SpaceSnapshot] = []
    var currentSpaceID: UUID?
    var onMoveToSpace: ((UUID?) -> Void)?
    var agentName: String = ""
    var permissionRequest: PermissionRequest?
    var onPermissionResponse: ((PermissionResponse) -> Void)?
    var onActionTap: (() -> Void)?
    var hasStagedAttachments = false
    /// Arms dictation as soon as the bar appears (widget/shortcut launched chat).
    var autoStartDictation = false

    @Environment(\.colors) private var colors
    @Environment(\.scenePhase) private var scenePhase
    @Injected(\.dictationService) private var dictationService
    @Injected(\.speechService) private var speechService
    @Injected(\.languageManager) private var languageManager
    @Injected(\.vocabularyStore) private var vocabularyStore

    @State private var soundManager = SoundManager()
    @State private var isDictating = false
    @State private var textBeforeDictation = ""
    @State private var dictationText = ""
    @State private var didAutoStartDictation = false

    private var effectiveText: String {
        guard isDictating else { return text }
        if textBeforeDictation.isEmpty {
            return dictationText
        } else if dictationText.isEmpty {
            return textBeforeDictation
        } else {
            return textBeforeDictation + " " + dictationText
        }
    }

    private var canSend: Bool {
        let hasText = !effectiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || hasStagedAttachments) && !isDisabled
    }

    private var showStopButton: Bool {
        onStop != nil && isDisabled
    }

    private var micState: AppChatInput.MicState {
        guard isDictating, dictationService.state.isActive else { return .idle }
        switch dictationService.state {
        case .preparing:
            return .active
        case .listening, .transcribing:
            return .active
        case .error:
            return .error
        case .idle:
            return .idle
        }
    }

    var body: some View {
        AppChatInput(
            text: $text,
            isSendEnabled: canSend,
            showStopButton: showStopButton,
            micState: micState,
            onSend: send,
            onStop: stopStreaming,
            onMicTap: isDictating ? stopDictation : startDictation,
            onActionTap: onActionTap.map { tap in
                {
                    Haptics.light()
                    tap()
                }
            },
            overlayText: isDictating ? effectiveText : nil,
            isFocused: isFocused
        )
        .animation(Animations.snap, value: isDictating)
        .onChange(of: dictationService.transcription) { _, transcription in
            guard isDictating else { return }
            dictationText = transcription
        }
        .onAppear {
            armAutoDictation()
        }
        // A widget launch arms the chat while the app is still transitioning to
        // the foreground; recording can't start until the scene is active.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            armAutoDictation()
        }
        // Navigating away mid-dictation (e.g. a widget tap replaces the
        // stack) destroys this bar, but the service is shared and singleton —
        // stop it or the mic keeps recording into nothing.
        .onDisappear {
            if isDictating {
                dictationService.stop()
            }
        }
    }

    /// Arms the auto-started dictation once, and only while the app is active.
    private func armAutoDictation() {
        guard autoStartDictation, !didAutoStartDictation, scenePhase == .active else { return }
        didAutoStartDictation = true
        startDictation()
    }

    private func startDictation() {
        Haptics.light()
        soundManager.playUISound(.dictationStarted)
        speechService.stop()
        isFocused.wrappedValue = false
        textBeforeDictation = text
        dictationText = ""
        isDictating = true
        dictationService
            .setLocale(Locale(identifier: languageManager.currentLanguage.speechLocaleIdentifier))
        dictationService.setContextualStrings(vocabularyStore.allWords(agentName: agentName))
        dictationService.start()
    }

    private func stopDictation() {
        Haptics.light()
        dictationService.stop()
        text = effectiveText
        isDictating = false
        soundManager.playUISound(.dictationStopped)
    }

    private func send() {
        Haptics.medium()
        isFocused.wrappedValue = false
        let mode: InteractionMode = isDictating ? .dictation : .text
        if isDictating {
            text = effectiveText
            dictationService.stop()
            isDictating = false
        }
        soundManager.playUISound(.sending)
        onSend(mode)
    }

    private func stopStreaming() {
        Haptics.light()
        onStop?()
    }
}
