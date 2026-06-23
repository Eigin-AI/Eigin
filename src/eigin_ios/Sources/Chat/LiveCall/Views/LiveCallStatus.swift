import SwiftUI

/// Live text stream that mirrors the call phase in the center of the screen.
///
/// - Listening: dictation text flows in centered and large, like the agent speaking.
/// - Processing: "Thinking..." or the active tool name.
/// - Speaking: the agent's words stream in as they are spoken.
/// - Idle: "Connecting..."
///
/// Every state renders through one container: text starts under the avatar and
/// grows downward, then pins to the bottom once it fills the region so new
/// words push older lines up into a soft top fade — an endless stream rather
/// than a scrollable transcript.
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

    /// Whether the text is taller than the region and so rising into the fade.
    /// Resting text stays crisp; the fade only applies once words push up.
    @State private var isOverflowing = false

    private static let minimumDisplayTime: TimeInterval = 0.75

    // MARK: - Streaming Display

    /// Upper bound on the characters laid out. Older text has already risen out
    /// of view, so trimming it keeps text layout cost bounded across long
    /// turns. Because the text is bottom-anchored once it overflows, trimming
    /// the front never shifts the visible words. The full transcript still
    /// flows into the chat messages.
    private static let maxDisplayedCharacters = 1000

    /// Height of the soft fade where older lines dissolve at the top edge.
    /// Mirrors the collapse fade on long user messages (`AppChatUserMessage`),
    /// flipped to the top. Applied only while the text overflows, so it never
    /// pushes resting text down from the avatar.
    private static let fadeHeight: CGFloat = Spacing.n40

    // MARK: - Current Text

    private enum TextRole { case body, muted, error }

    /// The text to show right now and how to style it, unified across phases so
    /// every state flows through the same container.
    private var display: (text: String, role: TextRole)? {
        if let error = service.error {
            return (error, .error)
        }
        if isStreaming {
            guard !displayedText.isEmpty else {
                let placeholder = service.phase == .speaking
                    ? Localized.Voice.speaking
                    : Localized.Voice.listening
                return (placeholder, .muted)
            }
            return (displayedText, .body)
        }
        if let label = initialized ? displayedLabel : desiredLabel {
            return (label, .muted)
        }
        return nil
    }

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

    /// Whether the view should show streaming text rather than a static label.
    private var isStreaming: Bool {
        service.error == nil
            && service.chatLoop.pendingPermission == nil
            && (service.phase == .listening || service.phase == .speaking)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                Group {
                    if let display {
                        Text(display.text)
                            .typography(Typography.standfirst)
                            .foregroundStyle(color(for: display.role))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { scroll in
                scroll.contentSize.height > scroll.containerSize.height + 0.5
            } action: { _, overflowing in
                isOverflowing = overflowing
            }
            .mask(mask)
        }
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

    /// The live text for the current streaming phase: dictation while
    /// listening, the agent's words while speaking.
    private var phaseText: String {
        switch service.phase {
        case .listening: service.transcription
        case .speaking: service.speakingText
        default: ""
        }
    }

    /// Trailing window of the streaming text laid out on screen.
    private var displayedText: String {
        let text = phaseText
        guard text.count > Self.maxDisplayedCharacters else { return text }
        return String(text.suffix(Self.maxDisplayedCharacters))
    }

    private func color(for role: TextRole) -> Color {
        switch role {
        case .body: colors.text.standard.base
        case .muted: colors.text.standard.muted
        case .error: colors.text.standard.error
        }
    }

    /// Solid while resting so text stays crisp; the top fade only kicks in
    /// once words overflow and start rising.
    @ViewBuilder
    private var mask: some View {
        if isOverflowing {
            fadeMask
        } else {
            Color.black
        }
    }

    /// Fades rising lines out at the top edge while leaving the newest words
    /// at the bottom fully crisp.
    private var fadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.fadeHeight)

            Color.black
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
}
