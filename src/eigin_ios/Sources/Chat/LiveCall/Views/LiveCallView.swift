import Factory
import SwiftUI

/// Full-screen voice mode overlaid on the chat with a translucent material backdrop.
///
/// The bottom box shows a live text stream: dictation while listening,
/// a status label while thinking, and the agent's words as they're spoken.
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

    @Injected(\.dictationService) private var dictationService
    @Environment(\.themeManager) private var themeManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var service = LiveCallService()

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack {
                Spacer()
                AgentCard(agent: agent, service: service)
                Spacer()
                LiveCallFooter(service: service, onEnd: endCall)
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.colors, colors)
        .presentationBackground(.clear)
        .onAppear {
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
                onChatGrant: onChatGrant
            ))
        }
        .statusBarHidden()
        .onChange(of: service.phase) { oldPhase, newPhase in
            // Auto-dismiss when stopped externally (e.g. CallKit end, real call)
            if oldPhase != .idle, newPhase == .idle {
                messages = service.messages
                isPresented = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            service.isForegrounded = newPhase == .active
            if newPhase == .background, service.chatLoop.pendingPermission != nil {
                service.chatLoop.resolvePermission(.deny)
            }
        }
    }

    private var colors: ResolvedColors {
        themeManager.colors(for: .dark)
    }

    // MARK: - Actions

    private func endCall() {
        service.stop()
        // onChange(of: service.phase) handles message sync and dismiss
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var messages: [ChatMessage] = []
    @Previewable @State var isPresented = true

    LiveCallView(
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
        mcpServers: []
    )
    .previewEnvironment()
}
