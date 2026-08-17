import Factory
import SwiftUI
import UIKit

struct ChatMessageView: View, Equatable {
    let role: String
    let content: String
    var attachments: [MessageAttachment] = []
    var messageID: String = ""
    /// True while this message is the live streaming turn.
    var isActivelyStreaming: Bool = false
    var showFooter: Bool = false
    var showUserMessageFooter: Bool = false
    var onUserMessageFooterAction: (() -> Void)?

    @Environment(\.colors) private var colors
    @Environment(\.gridBreakpoint) private var breakpoint
    @Injected(\.speechService) private var speechService
    @Injected(\.voiceService) private var voiceService
    @Injected(\.languageManager) private var languageManager
    @State private var showCopied = false
    @State private var downloadItem: AssetItem?

    init(
        role: String,
        content: String,
        attachments: [MessageAttachment] = [],
        messageID: String = "",
        isActivelyStreaming: Bool = false,
        showFooter: Bool = false,
        showUserMessageFooter: Bool = false,
        onUserMessageFooterAction: (() -> Void)? = nil
    ) {
        self.role = role
        self.content = content
        self.attachments = attachments
        self.messageID = messageID
        self.isActivelyStreaming = isActivelyStreaming
        self.showFooter = showFooter
        self.showUserMessageFooter = showUserMessageFooter
        self.onUserMessageFooterAction = onUserMessageFooterAction
    }

    /// Compares only what's drawn, not the action closures the feed rebuilds each render.
    /// Without this, every message re-splits its blocks on every streaming tick.
    nonisolated static func == (lhs: ChatMessageView, rhs: ChatMessageView) -> Bool {
        lhs.role == rhs.role
            && lhs.content == rhs.content
            && lhs.attachments == rhs.attachments
            && lhs.messageID == rhs.messageID
            && lhs.isActivelyStreaming == rhs.isActivelyStreaming
            && lhs.showFooter == rhs.showFooter
            && lhs.showUserMessageFooter == rhs.showUserMessageFooter
    }

    private var isUser: Bool {
        role == "user"
    }

    private var isPlayingThis: Bool {
        speechService.isSpeaking && speechService.currentText == content
    }

    private var isLoadingForThis: Bool {
        speechService.currentText == content
            && (speechService.isPreparingEngine || speechService.isBuffering)
    }

    private var showDownloadSheet: Binding<Bool> {
        Binding(
            get: { downloadItem != nil },
            set: { if !$0 { downloadItem = nil } }
        )
    }

    private var blocks: [ContentBlock] {
        guard !content.isEmpty else { return [] }
        return ContentBlock.split(
            content, messageID: messageID.isEmpty ? "msg-\(UUID().uuidString)" : messageID
        )
    }

    var body: some View {
        if isUser {
            userMessageView
        } else {
            assistantMessageView
        }
    }

    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: Spacing.n16) {
            if !attachments.isEmpty {
                AttachedImagesView(attachments: attachments)
                    .padding(.trailing, breakpoint.outer)
            }
            if !content.isEmpty {
                AppChatUserMessage(text: content)
            }
            if showUserMessageFooter, let action = onUserMessageFooterAction {
                userMessageFooter(action: action)
                    .padding(.trailing, breakpoint.outer + Spacing.n4)
            }
        }
        // Fill the row so attachments-only turns still right-anchor.
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(Animations.smooth, value: showUserMessageFooter)
    }

    private func userMessageFooter(action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: Spacing.n16) {
            Button {
                Haptics.light()
                action()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.text.standard.muted.opacity(0.4))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 16)
            .accessibilityLabel(Text(Localized.Provider.tryAgain))
        }
        .frame(height: 22)
        .transition(.opacity.combined(with: .scale))
    }

    private var assistantMessageView: some View {
        AppChatBrandMessage {
            VStack(alignment: .leading, spacing: Spacing.n16) {
                ForEach(blocks) { block in
                    ContentBlockView(
                        block: block,
                        isActivelyStreaming: isActivelyStreaming && block.id == blocks.last?.id
                    )
                    .equatable()
                }

                footerView
            }
        }
        .appSheet(
            isPresented: showDownloadSheet,
            title: downloadItem?.asset.displayName ?? "",
            detents: [.medium],
            showsDismissButton: false
        ) {
            AssetDownloadSheetContent(
                asset: downloadItem!.asset,
                onAccept: {
                    downloadItem = nil
                    speechService.speak(content)
                },
                onDecline: {
                    downloadItem = nil
                    speechService.speak(content)
                }
            )
        }
    }

    private var footerView: some View {
        HStack(alignment: .center, spacing: Spacing.n16) {
            if showFooter {
                Button {
                    Haptics.light()
                    UIPasteboard.general.string = content
                    withAnimation(.easeInOut(duration: 0.05)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation(.easeInOut(duration: 0.05)) {
                            showCopied = false
                        }
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.text.standard.muted.opacity(0.4))
                        .contentTransition(.symbolEffect(.replace))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 16)

                Button {
                    Haptics.light()
                    if isPlayingThis {
                        speechService.stop()
                    } else if let asset = voiceService.upgradeAsset(
                        for: languageManager.currentLanguage
                    ),
                        !asset.state.isDownloading
                    {
                        downloadItem = AssetItem(asset)
                    } else {
                        speechService.speak(content)
                    }
                } label: {
                    Image(
                        systemName: isLoadingForThis
                            ? "rays" : (isPlayingThis ? "stop.fill" : "play.fill")
                    )
                    .font(.system(size: 16))
                    .foregroundStyle(colors.text.standard.muted.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.rotate, options: .repeating, isActive: isLoadingForThis)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 16)
            }
        }
        // Height is reserved while empty so the footer fading in doesn't shift the
        // message. The fade runs only when `showFooter` flips, so history draws it at once.
        .frame(height: 22)
        .opacity(showFooter ? 1 : 0)
        .animation(.easeIn(duration: Animations.fast), value: showFooter)
    }
}
