import SwiftData
import SwiftUI

/// A single row in the chat list, showing title, timestamp, and last message preview.
struct ChatRowView: View {
    let chat: Chat
    let spaces: [Space]
    @Query private var previewMessages: [Message]

    init(chat: Chat, spaces: [Space]) {
        self.chat = chat
        self.spaces = spaces
        _previewMessages = Query(ChatListQueries.preview(chat: chat))
    }

    @Environment(\.colors) private var colors

    var body: some View {
        HStack(spacing: Spacing.n16) {
            chatAvatar

            VStack(alignment: .leading, spacing: Spacing.n4) {
                Text(chat.title.isEmpty ? Localized.Tools.New.chat : chat.title)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                    .lineLimit(1)

                Text(preview)
                    .typography(Typography.body)
                    .foregroundStyle(colors.text.standard.muted)
                    .lineLimit(2, reservesSpace: true)
            }
        }
    }

    private var preview: String {
        previewMessages.first
            .map { ChatTags.stripAll(from: $0.content) } ?? "No messages yet"
    }

    private var chatAvatar: some View {
        ZStack {
            Circle()
                .fill(colors.surface.standard.alternative)
                .frame(width: 36, height: 36)

            if let spaceID = chat.spaceID,
               let space = spaces.first(where: { $0.id == spaceID })
            {
                Text(space.emoji)
                    .typography(Typography.note)
            } else {
                Image(systemName: "bubble.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.accent)
            }
        }
    }
}
