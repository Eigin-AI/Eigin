import Factory
import SwiftUI

/// Full-screen voice mode overlaid on the chat.
struct LiveCallView: View {
    let agent: Agent
    let provider: Provider
    let initialMessages: [ChatMessage]
    @Binding var messages: [ChatMessage]
    @Binding var isPresented: Bool
    let permissionPolicy: AgentPermissionPolicy
    let chatID: UUID?
    let spaceID: UUID?
    let space: Space?
    let mcpServers: [MCPServer]
    var onPersist: (([ChatMessage]) -> Void)?
    var onChatGrant: (([ToolCapability]) -> Void)?
    /// Invoked with the underlying error when the call ends abnormally.
    var onError: ((Error) -> Void)?

    /// When set, used in place of the `@State` service — only for previews.
    var previewService: LiveCallService?

    @Injected(\.dictationService) private var dictationService
    @Environment(\.colors) private var colors
    @Environment(\.scenePhase) private var scenePhase

    @State private var service = LiveCallService()

    /// How much of the avatar blob's wobble is showing — re-anchored on every
    /// phase change so the wobble eases in and out over `Animations.slow`.
    @State private var blobIntensity = MorphIntensity.none

    /// Mirrors the loop's pending permission so the sheet stays alive through
    /// its dismissal animation, matching the chat permission flow.
    @State private var presentedPermission: PermissionRequest?

    var body: some View {
        ZStack {
            colors.surface.standard.base
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LiveCallAvatar(emoji: agent.emoji, intensity: blobIntensity)
                    .padding(.top, Spacing.n48)

                LiveCallStatus(service: service)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.vertical, Spacing.n16)
                    .padding(.horizontal, Spacing.n32)

                Spacer(minLength: 0)
            }
            .safeAreaInset(edge: .bottom, spacing: Spacing.n16) {
                LiveCallPillBar(service: service, onEnd: endCall)
            }
        }
        .onAppear {
            if let previewService {
                service = previewService
            } else {
                dictationService.stop()
                service.start(context: LiveCallContext(
                    agent: agent,
                    provider: provider,
                    messages: initialMessages,
                    permissionPolicy: permissionPolicy,
                    chatID: chatID,
                    spaceID: spaceID,
                    space: space,
                    mcpServers: mcpServers,
                    onPersist: onPersist,
                    onChatGrant: onChatGrant,
                    onError: onError
                ))
            }
        }
        .statusBarHidden()
        .onChange(of: service.phase) { oldPhase, newPhase in
            if oldPhase != .idle, newPhase == .idle {
                messages = service.messages
                isPresented = false
            }
        }
        .onChange(of: service.phase) { _, phase in
            // The blob wobbles only while the agent is working.
            blobIntensity = blobIntensity.transitioned(to: phase == .processing, at: .now)
        }
        .onChange(of: scenePhase) { _, newPhase in
            service.isForegrounded = newPhase == .active
            if newPhase == .background, service.chatLoop.pendingPermission != nil {
                service.chatLoop.resolvePermission(.deny)
            }
        }
        .onChange(of: service.chatLoop.pendingPermission) { _, request in
            if let request {
                presentedPermission = request
                service.playPermissionSound()
            } else {
                presentedPermission = nil
            }
        }
        .appSheet(
            isPresented: Binding(
                get: { presentedPermission != nil },
                set: { if !$0 { presentedPermission = nil } }
            ),
            title: Localized.Permission.sheetTitle,
            descriptionContent: presentedPermission.map { request in
                AnyView(PermissionDisclosureText(
                    agentName: agent.name,
                    toolDisplayName: request.toolDisplayName,
                    disclosure: request.disclosure
                ))
            },
            fitsContent: true
        ) {
            if let request = presentedPermission {
                PermissionRequestSheetContent(
                    agentName: agent.name,
                    toolDisplayName: request.toolDisplayName,
                    disclosure: request.disclosure,
                    allowOnceLabel: Localized.Permission.allowOnce,
                    allowForChatLabel: Localized.Permission.allowForChat,
                    denyLabel: Localized.Permission.deny,
                    onResponse: { response in
                        service.chatLoop.resolvePermission(response)
                    }
                )
            }
        }
    }

    private func endCall() {
        service.stop()
    }
}

// MARK: - Preview helpers

private struct PreviewCallView: View {
    let phase: LiveCallService.Phase
    let transcription: String

    @State var messages: [ChatMessage] = []
    @State var isPresented = true

    var body: some View {
        let service = LiveCallService()
        service.configureForPreview(phase: phase, transcription: transcription)

        return LiveCallView(
            agent: Agent(name: "Eigin", providerID: UUID(), model: "gpt-4o"),
            provider: Provider(name: "Preview", baseURL: "https://fake.local"),
            initialMessages: [],
            messages: $messages,
            isPresented: $isPresented,
            permissionPolicy: AgentPermissionPolicy(
                builtInGrants: [:],
                discoveredGrants: [:],
                chatGrants: [],
                canPromptUser: false
            ),
            chatID: nil,
            spaceID: nil,
            space: nil,
            mcpServers: [],
            previewService: service
        )
        .previewEnvironment()
    }
}

// MARK: - Previews

#Preview("Idle") {
    PreviewCallView(phase: .idle, transcription: "")
}

#Preview("Listening") {
    PreviewCallView(
        phase: .listening,
        transcription: "Tell me about the thing you're working on right now"
    )
}

#Preview("Processing") {
    PreviewCallView(phase: .processing, transcription: "")
}
