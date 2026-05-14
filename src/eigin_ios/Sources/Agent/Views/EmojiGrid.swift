import SwiftUI

struct EmojiGrid: View {
    @Binding var selectedEmoji: String
    @Binding var isPresented: Bool
    let colors: ResolvedColors

    @State private var customEmoji = ""

    private static let emojis = [
        "🤖", "💻", "🧠", "⚡", "🔮", "🛸",
        "🦊", "🐙", "🦉", "🐺", "🦋", "🐬",
        "😎", "🧙", "🥷", "👻", "🎭", "🧑‍🚀",
        "🌟", "🔥", "🌊", "🎯", "💎", "🪐",
        "🎨", "🎵", "📚", "🧩", "🍀",
    ]

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: Spacing.n8), count: 6)

    var body: some View {
        VStack(spacing: Spacing.n16) {
            LazyVGrid(columns: columns, spacing: Spacing.n8) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button {
                        Haptics.light()
                        selectedEmoji = emoji
                        isPresented = false
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack(spacing: Spacing.n8) {
                TextField("Custom", text: $customEmoji)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Button {
                    let trimmed = customEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Haptics.light()
                        selectedEmoji = String(trimmed.prefix(1))
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colors.accent)
                }
                .buttonStyle(.plain)
                .disabled(customEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.n16)
        .presentationCompactAdaptation(.popover)
    }
}
