import SwiftUI

/// Live text stream that mirrors the call phase:
/// - Listening: dictation text flows in (same style as ChatInputBar dictation)
/// - Processing: "Thinking..." label or active tool name
/// - Speaking: agent's words flow through as they're spoken
/// - Idle: "Connecting..." label
///
/// Labels are buffered with a minimum display time so fast tool calls
/// don't flash by too quickly to read.
struct LiveCallStatus: View {
    let service: LiveCallService

    @Environment(\.colors) private var colors

    // MARK: - Minimum Display Time

    @State private var displayedLabel: String? = nil
    @State private var labelSetAt: Date = .distantPast
    @State private var pendingUpdate: Task<Void, Never>?
    @State private var initialized = false

    private static let minimumDisplayTime: TimeInterval = 0.75

    /// The label the service wants right now, or nil for streaming phases.
    private var desiredLabel: String? {
        if let permission = service.chatLoop.pendingPermission {
            return permission.toolDisplayName
        }
        switch service.phase {
        case .processing:
            return service.activeToolDisplayName
                ?? Localized.Agent.thinking
        case .idle:
            return Localized.Network.connecting
        case .listening, .speaking:
            return nil
        }
    }

    /// Whether the view should show a streaming DictationStreamView.
    private var isStreaming: Bool {
        service.error == nil
            && service.chatLoop.pendingPermission == nil
            && (service.phase == .listening || service.phase == .speaking)
    }

    var body: some View {
        Group {
            if let error = service.error {
                Text(error)
                    .font(Typography.body)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if isStreaming {
                streamingContent
            } else if let label = initialized ? displayedLabel : desiredLabel {
                phaseLabel(label)
            }
        }
        .frame(height: 24)
        .onChange(of: desiredLabel) {
            scheduleLabel(desiredLabel)
        }
        .onChange(of: isStreaming) {
            if isStreaming {
                pendingUpdate?.cancel()
                displayedLabel = nil
            }
        }
        .onAppear {
            displayedLabel = desiredLabel
            labelSetAt = .now
            initialized = true
        }
    }

    // MARK: - Streaming Content

    @ViewBuilder
    private var streamingContent: some View {
        switch service.phase {
        case .listening:
            if service.transcription.isEmpty {
                phaseLabel(Localized.Voice.listening)
            } else {
                DictationStreamView(
                    text: service.transcription,
                    state: service.dictationState,
                    textStyle: colors.textPrimary
                )
            }
        case .speaking:
            if service.speakingText.isEmpty {
                phaseLabel(Localized.Voice.speaking)
            } else {
                DictationStreamView(
                    text: service.speakingText,
                    state: .idle,
                    textStyle: colors.textPrimary
                )
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Label Buffering

    private func scheduleLabel(_ newLabel: String?) {
        pendingUpdate?.cancel()

        guard let newLabel else { return }

        let elapsed = Date.now.timeIntervalSince(labelSetAt)
        if elapsed >= Self.minimumDisplayTime || displayedLabel == nil {
            displayedLabel = newLabel
            labelSetAt = .now
        } else {
            let remaining = Self.minimumDisplayTime - elapsed
            pendingUpdate = Task { @MainActor in
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
                displayedLabel = newLabel
                labelSetAt = .now
            }
        }
    }

    // MARK: - Helpers

    private func phaseLabel(_ label: String) -> some View {
        Text(label)
            .font(Typography.body)
            .foregroundStyle(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
