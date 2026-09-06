import SwiftData
import SwiftUI

/// View-only stage for chat screenshot scenes: one finished turn, composed
/// from literal `ChatItem`s and rendered through the same row views
/// ``ChatFeed`` uses. Laid out like a fresh send — user bubble at the top,
/// reply filling the screen below.
struct ScreenshotCanvas: View {
    /// Header chat created by the installer; the header renders its title.
    let chat: Chat?
    let items: [ChatItem]
    /// When set, the real permission prompt sheet presents over the canvas
    /// (`asks-first` scene).
    var permissionRequest: PermissionRequest?
    /// Initial composer text (`follow-up` scene), so the screen reads mid-reply.
    var composerText: String?

    @State private var messageText: String
    @State private var isSheetPresented = false
    @State private var viewportHeight: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    @Environment(\.colors) private var colors

    init(
        chat: Chat?,
        items: [ChatItem],
        permissionRequest: PermissionRequest? = nil,
        composerText: String? = nil
    ) {
        self.chat = chat
        self.items = items
        self.permissionRequest = permissionRequest
        _messageText = State(initialValue: composerText ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(
                chat: chat,
                onBack: {},
                onPhone: {},
                isPhoneDisabled: true
            )
            ScrollView {
                VStack(alignment: .leading, spacing: Sizing.Chat.Gap.message) {
                    ForEach(items) { item in
                        ChatFeedRow(item: item)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: viewportHeight,
                    alignment: .topLeading
                )
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, newValue in
                viewportHeight = newValue
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatInputBar(
                    text: $messageText,
                    // A prefilled composer must look sendable.
                    isDisabled: messageText.isEmpty,
                    onSend: { _ in },
                    onStop: nil,
                    isFocused: $isInputFocused,
                    agentName: "Eigin"
                )
                .ignoresSafeArea(.container, edges: .horizontal)
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .appSheet(
            isPresented: $isSheetPresented,
            title: Localized.Permission.sheetTitle,
            descriptionContent: permissionRequest.map { request in
                AnyView(
                    PermissionDisclosureText(
                        agentName: "Eigin",
                        toolDisplayName: request.toolDisplayName,
                        disclosure: request.disclosure
                    )
                )
            } ?? AnyView(EmptyView()),
            fitsContent: true
        ) {
            if let permissionRequest {
                PermissionRequestSheetContent(
                    agentName: "Eigin",
                    toolDisplayName: permissionRequest.toolDisplayName,
                    disclosure: permissionRequest.disclosure,
                    allowOnceLabel: Localized.Permission.allowOnce,
                    allowForChatLabel: Localized.Permission.allowForChat,
                    denyLabel: Localized.Permission.deny
                ) { _ in
                    // A capture only; never answered.
                }
                .accessibilityIdentifier("screenshot-permission-sheet")
            }
        }
        .onAppear { isSheetPresented = permissionRequest != nil }
    }
}
