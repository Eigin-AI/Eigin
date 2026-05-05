import Factory
import SwiftUI

/// The default chat input content: expandable text field + action buttons.
///
/// The text field is always visible. The bottom row has a `+` button on the
/// left. Tapping it expands a horizontal strip of action pills (replacing
/// the mic/send buttons). Tapping `×` or selecting an action collapses it.
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
    var browsingRequest: BrowsingRequest?
    var onBrowsingComplete: ((BrowsingResult) -> Void)?

    @Environment(\.colors) private var colors
    @Injected(\.dictationService) private var dictationService
    @Injected(\.speechService) private var speechService
    @Injected(\.languageManager) private var languageManager
    @Injected(\.vocabularyStore) private var vocabularyStore

    @State private var soundManager = SoundManager()
    @State private var isExpanded = false
    @State private var showSpacePicker = false

    @State private var isDictating = false
    /// Text that was in the field before dictation started.
    @State private var textBeforeDictation = ""

    /// Controls content opacity for phased transitions.
    @State private var showContent = true
    /// Delayed mirror of `isPrompting` — swaps content only after fade-out completes.
    @State private var displayedPrompting = false
    /// Retained copy so the permission UI stays rendered during fade-out
    /// even after the external `permissionRequest` becomes nil.
    @State private var retainedPermission: PermissionRequest?
    /// Delayed mirror of `isBrowsing` — swaps content only after fade-out completes.
    @State private var displayedBrowsing = false
    /// Retained copy so the browsing UI stays rendered during fade-out.
    @State private var retainedBrowsing: BrowsingRequest?
    /// Incremented on each transition to invalidate stale asyncAfter callbacks.
    @State private var transitionGeneration = 0

    private var isPrompting: Bool {
        permissionRequest != nil
    }

    private var isBrowsing: Bool {
        browsingRequest != nil
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !isDisabled
    }

    private var showStopButton: Bool {
        onStop != nil && isDisabled
    }

    private var hasActions: Bool {
        onMoveToSpace != nil && (!spaces.isEmpty || currentSpaceID != nil)
    }

    /// Which mode to display — used to drive the 3-phase transition.
    private enum DisplayMode: Equatable {
        case normal, prompting, browsing
    }

    private var activeMode: DisplayMode {
        if isBrowsing { return .browsing }
        if isPrompting { return .prompting }
        return .normal
    }

    var body: some View {
        ChatBottomBox {
            Group {
                if displayedBrowsing {
                    browsingContent
                } else if displayedPrompting {
                    permissionContent
                } else {
                    normalContent
                }
            }
            .opacity(showContent ? 1 : 0)
            .allowsHitTesting(showContent)
        }
        .animation(Animations.snap, value: displayedPrompting)
        .animation(Animations.snap, value: displayedBrowsing)
        .onChange(of: activeMode) {
            runModeTransition()
        }
        // Back-to-back browsing: new request while already browsing.
        // Force-recreate the WebBrowsingView without a full mode transition.
        .onChange(of: browsingRequest?.id) { oldID, newID in
            guard oldID != nil, newID != nil, displayedBrowsing else { return }
            retainedBrowsing = browsingRequest
        }
        .overlay {
            if isDictating, dictationService.state.isActive {
                RoundedRectangle(cornerRadius: 16)
                    .fill(colors.accent)
                    .modifier(RecordingGlowModifier())
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.xs)
                    .allowsHitTesting(false)
            } else if displayedBrowsing {
                BrowsingScanOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.xs)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showSpacePicker) {
            SpacePickerSheet(
                spaces: spaces,
                currentSpaceID: currentSpaceID,
                onSelect: { spaceID in
                    onMoveToSpace?(spaceID)
                    Haptics.medium()
                    withAnimation(Animations.snap) { isExpanded = false }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .animation(Animations.snap, value: isDictating)
        .onChange(of: dictationService.transcription) { _, transcription in
            guard isDictating else { return }
            if textBeforeDictation.isEmpty {
                text = transcription
            } else if transcription.isEmpty {
                text = textBeforeDictation
            } else {
                text = textBeforeDictation + " " + transcription
            }
        }
    }

    // MARK: - Mode Transition

    /// Runs the 3-phase (fade out → swap → fade in) content transition.
    /// Each call increments `transitionGeneration` so stale asyncAfter
    /// callbacks from a previous transition are no-ops.
    private func runModeTransition() {
        transitionGeneration += 1
        let gen = transitionGeneration

        // Capture requests before they go nil so the UI stays rendered during fade-out
        if isPrompting { retainedPermission = permissionRequest }
        if isBrowsing { retainedBrowsing = browsingRequest }

        // Phase 1: fade out old content
        withAnimation(.easeOut(duration: Animations.fast)) {
            showContent = false
        }
        // Phase 2: swap content + resize box (after fade-out)
        DispatchQueue.main.asyncAfter(deadline: .now() + Animations.fast) {
            guard gen == transitionGeneration else { return }
            withAnimation(Animations.gentle) {
                displayedPrompting = isPrompting
                displayedBrowsing = isBrowsing
            }
            // Phase 3: fade in new content (after resize starts)
            DispatchQueue.main.asyncAfter(deadline: .now() + Animations.fast) {
                guard gen == transitionGeneration else { return }
                withAnimation(.easeIn(duration: Animations.fast)) {
                    showContent = true
                }
                // Release retained state after fade-in completes
                if !isPrompting { retainedPermission = nil }
                if !isBrowsing { retainedBrowsing = nil }
            }
        }
    }

    // MARK: - Normal Content

    private var normalContent: some View {
        VStack(spacing: Spacing.sm) {
            // Text area
            if isDictating, dictationService.state.isActive {
                DictationStreamView(
                    text: dictationService.transcription,
                    state: dictationService.state,
                    textStyle: colors.textSecondary
                )
            } else {
                TextField(Localized.Chat.Input.messagePlaceholder, text: $text, axis: .vertical)
                    .focused(isFocused)
                    .lineLimit(1 ... 10)
                    .disabled(isDisabled)
                    .onSubmit { if canSend { onSend(.text) } }
            }

            // Bottom row — plus button + either pills or mic/send
            HStack(spacing: Spacing.sm) {
                if hasActions {
                    Button {
                        Haptics.light()
                        withAnimation(Animations.snap) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundStyle(colors.textSecondary)
                            .rotationEffect(.degrees(isExpanded ? 45 : 0))
                            .frame(width: 40, height: 40)
                            .background(colors.textSecondary.opacity(0.15))
                            .clipShape(Circle())
                    }
                }

                if isExpanded {
                    actionPills
                        .transition(.offset(x: -40).combined(with: .opacity))
                        .animation(Animations.snap.delay(0.1), value: isExpanded)
                } else {
                    inputButtons
                        .transition(.offset(x: 10).combined(with: .opacity))
                        .animation(Animations.snap, value: isExpanded)
                }
            }
        }
    }

    // MARK: - Permission Content

    private var permissionContent: some View {
        VStack(spacing: Spacing.sm) {
            if let request = retainedPermission ?? permissionRequest {
                let actor = agentName.isEmpty || agentName.count > 20 ? "Agent" : agentName
                Text(Localized.Permission.wantsToUseFormat(actor, request.toolDisplayName))
                    .font(Typography.callout)
                    .foregroundStyle(colors.textSecondary)

                Button {
                    Haptics.light()
                    onPermissionResponse?(.allowOnce)
                } label: {
                    Text(Localized.Permission.allowOnce)
                        .font(Typography.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)

                Button {
                    Haptics.light()
                    onPermissionResponse?(.allowForChat)
                } label: {
                    Text(Localized.Permission.allowForChat)
                        .font(Typography.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(colors.accent)

                Button {
                    Haptics.light()
                    onPermissionResponse?(.deny)
                } label: {
                    Text(Localized.Permission.deny)
                        .font(Typography.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(colors.destructive)
            }
        }
    }

    // MARK: - Browsing Content

    private var browsingContent: some View {
        let request = retainedBrowsing ?? browsingRequest ?? BrowsingRequest(
            id: "",
            url: URL(string: "about:blank")!,
            toolDisplayName: ""
        )
        return WebBrowsingView(
            request: request,
            agentName: agentName,
            onComplete: { result in onBrowsingComplete?(result) },
            onStop: onStop
        )
        // Force full teardown + recreation for each new browsing request
        .id(request.id)
    }

    // MARK: - Action Pills

    private var actionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                if onMoveToSpace != nil, !spaces.isEmpty || currentSpaceID != nil {
                    ActionPill(icon: "square.grid.2x2", label: Localized.Ui.space) {
                        showSpacePicker = true
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 8)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 8)
            }
        )
    }

    // MARK: - Input Buttons (mic, stop, send)

    private var inputButtons: some View {
        HStack {
            Spacer()

            Button { isDictating ? stopDictation() : startDictation() } label: {
                Group {
                    switch dictationService.state {
                    case .idle:
                        Image(systemName: "mic")
                            .foregroundStyle(colors.textSecondary)
                    case .preparing:
                        Image(systemName: "mic")
                            .foregroundStyle(colors.accent)
                    case .listening, .transcribing:
                        Image(systemName: "mic.fill")
                            .foregroundStyle(colors.accent)
                    case .error:
                        Image(systemName: "mic")
                            .foregroundStyle(.red)
                    }
                }
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(
                    dictationService.state.isActive
                        ? colors.accent.opacity(0.15)
                        : colors.textSecondary.opacity(0.15)
                )
                .clipShape(Circle())
            }
            .modifier(SubtlePulseModifier(isActive: dictationService.state.isActive))
            .disabled(!isDictating && isDisabled)

            if showStopButton {
                Button(action: stopStreaming) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(colors.accent)
                        .clipShape(Circle())
                }
                .transition(.scale.combined(with: .opacity))
            } else if canSend {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(colors.accent)
                        .clipShape(Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Animations.snap, value: canSend)
        .animation(Animations.snap, value: showStopButton)
    }

    // MARK: - Actions

    private func startDictation() {
        Haptics.light()
        soundManager.playUISound(.dictationStarted)
        speechService.stop()
        isFocused.wrappedValue = false
        textBeforeDictation = text
        isDictating = true
        dictationService
            .setLocale(Locale(identifier: languageManager.currentLanguage.speechLocaleIdentifier))
        dictationService.setContextualStrings(vocabularyStore.allWords(agentName: agentName))
        dictationService.start()
    }

    private func stopDictation() {
        Haptics.light()
        dictationService.stop()
        isDictating = false
        soundManager.playUISound(.dictationStopped)
    }

    private func send() {
        Haptics.medium()
        let mode: InteractionMode = isDictating ? .dictation : .text
        if isDictating {
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

// MARK: - Action Pill

/// A pill-shaped button with icon and label for the actions strip.
private struct ActionPill: View {
    let icon: String
    let label: String
    let action: () -> Void

    @Environment(\.colors) private var colors

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Label(label, systemImage: icon)
                .font(Typography.callout)
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, Spacing.md)
                .frame(height: 40)
                .background(colors.textSecondary.opacity(0.1), in: Capsule())
        }
    }
}

// MARK: - Recording Animations

/// Gentle opacity pulse on the mic button while recording.
private struct SubtlePulseModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && isPulsing ? 0.5 : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onChange(of: isActive) { _, active in
                isPulsing = active
            }
            .onAppear {
                if isActive { isPulsing = true }
            }
    }
}

/// Very subtle accent glow that pulses over the chat box during recording.
private struct RecordingGlowModifier: ViewModifier {
    @State private var glowing = false

    func body(content: Content) -> some View {
        content
            .opacity(glowing ? 0.08 : 0.03)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: glowing
            )
            .onAppear { glowing = true }
    }
}

/// A gradient band that sweeps vertically over the input bar during browsing.
/// Uses `Color.primary` so it's dark in light mode, light in dark mode.
private struct BrowsingScanOverlay: View {
    @State private var offset: CGFloat = -1.0

    private let bandHeight: CGFloat = 220

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let yPos = offset * (height + bandHeight) - bandHeight

            LinearGradient(
                colors: [
                    Color.primary.opacity(0),
                    Color.primary.opacity(0.03),
                    Color.primary.opacity(0.05),
                    Color.primary.opacity(0.03),
                    Color.primary.opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: bandHeight)
            .frame(maxWidth: .infinity)
            .offset(y: yPos)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 4.0).repeatForever(autoreverses: true)
            ) {
                offset = 1.0
            }
        }
    }
}
