import SwiftUI

/// Streaming dictation text display — right-aligned, single line,
/// head-truncated with a left-edge gradient fade so the newest
/// text is always visible.
///
/// Used in both `ChatInputBar` and `LiveCallView`.
struct DictationStreamView: View {
    let text: String
    var placeholder: String = Localized.Voice.listening
    var error: String?
    var textStyle: Color = .secondary
    var errorStyle: Color = .red

    var body: some View {
        Group {
            if let error {
                Text(error)
                    .font(.body)
                    .foregroundStyle(errorStyle)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(textStyle.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(text)
                    .font(.body)
                    .foregroundStyle(textStyle)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .mask {
                        HStack(spacing: 0) {
                            LinearGradient(
                                colors: [.clear, .white],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 40)
                            Color.white
                        }
                    }
                    .contentTransition(.interpolate)
                    .animation(Animations.snap, value: text)
            }
        }
        .frame(minHeight: 22)
    }
}
