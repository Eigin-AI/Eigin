import SwiftUI

/// A single row in the chat list, showing title, timestamp, and last message preview.
struct ChatRowView: View {
    let chat: Chat
    let spaces: [Space]

    @Environment(\.colors) private var colors

    var body: some View {
        HStack(spacing: Spacing.md) {
            chatAvatar

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(chat.title.isEmpty ? Localized.Tools.New.chat : chat.title)
                    .typography(Typography.headline)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                Text(chat.lastVisibleMessage
                    .map { ChatTags.stripAll(from: $0.content) } ?? "No messages yet")
                    .typography(Typography.callout)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(2, reservesSpace: true)
            }
        }
    }

    private var chatAvatar: some View {
        ZStack {
            Circle()
                .fill(colors.surface)
                .frame(width: 36, height: 36)

            if let spaceID = chat.spaceID,
               let space = spaces.first(where: { $0.id == spaceID })
            {
                Text(space.emoji)
                    .typography(Typography.callout)
            } else {
                Image(systemName: "bubble.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.accent)
            }
        }
    }
}
