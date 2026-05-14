import Factory
import SwiftUI
import Textual

struct ChatMessageView: View {
    let role: String
    let content: String
    var messageID: String = ""
    var showFooter: Bool = false
    var animateFooter: Bool = false

    @Environment(\.colors) private var colors
    @Injected(\.speechService) private var speechService
    @Injected(\.voiceService) private var voiceService
    @Injected(\.languageManager) private var languageManager
    @State private var showCopied = false
    @State private var footerRevealed = false
    @State private var downloadItem: AssetItem?
    @State private var isCollapsed: Bool

    private static let collapseThreshold = 200
    private static let collapsedHeight: CGFloat = 110

    init(
        role: String,
        content: String,
        messageID: String = "",
        showFooter: Bool = false,
        animateFooter: Bool = false
    ) {
        self.role = role
        self.content = content
        self.messageID = messageID
        self.showFooter = showFooter
        self.animateFooter = animateFooter

        let isUser = role == "user"
        _isCollapsed = State(initialValue: isUser && content.count > Self.collapseThreshold)
    }

    private var isLongMessage: Bool {
        content.count > Self.collapseThreshold
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
        HStack {
            Spacer(minLength: 0)
            Text(content)
                .typography(Typography.chatMessageUser)
                .foregroundStyle(colors.text.standard.base)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: isLongMessage ? .infinity : nil, alignment: .leading)
                .frame(maxHeight: isCollapsed ? Self.collapsedHeight : .infinity, alignment: .top)
                .clipped()
                .mask(alignment: .top) {
                    if isLongMessage, isCollapsed {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 28)
                        }
                    } else {
                        Color.black
                    }
                }
                .padding(10)
                .background(colors.surface.standard.alternative)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .onTapGesture {
                    guard isLongMessage else { return }
                    Haptics.light()
                    withAnimation(Animations.gentle) {
                        isCollapsed.toggle()
                    }
                }
                .animation(Animations.gentle, value: isCollapsed)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .containerRelativeFrame(.horizontal, alignment: .trailing) { width, _ in
            width * 0.8
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: Spacing.n16) {
            ForEach(blocks) { block in
                ContentBlockView(block: block)
            }

            footerView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $downloadItem) { item in
            AssetDownloadPrompt(
                asset: item.asset,
                onAccept: {
                    downloadItem = nil
                    speechService.speak(content)
                },
                onDecline: {
                    downloadItem = nil
                    speechService.speak(content)
                }
            )
            .presentationDetents([.medium])
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
        .frame(height: 22)
        .opacity(animateFooter && !footerRevealed ? 0 : 1)
        .onAppear {
            if animateFooter {
                withAnimation(.easeIn(duration: Animations.fast)) {
                    footerRevealed = true
                }
            }
        }
        .onChange(of: animateFooter) {
            if animateFooter, !footerRevealed {
                withAnimation(.easeIn(duration: Animations.fast)) {
                    footerRevealed = true
                }
            }
        }
    }
}
