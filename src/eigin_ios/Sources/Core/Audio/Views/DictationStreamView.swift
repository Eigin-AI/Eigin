import SwiftUI

/// Streaming dictation text display — right-aligned, single line,
/// head-truncated with a left-edge gradient fade so the newest
/// text is always visible.
///
/// Used in both `ChatInputBar` and `LiveCallView`.
struct DictationStreamView: View {
    let text: String
    var state: AppDictationState = .idle
    var placeholder: String = Localized.Voice.listening
    var textStyle: Color = .secondary
    var errorStyle: Color = .red

    private var displayText: String? {
        switch state {
        case .idle:
            text.isEmpty ? nil : text
        case .preparing:
            "Preparing..."
        case .listening:
            text.isEmpty ? placeholder : text
        case .transcribing:
            text.isEmpty ? placeholder : text
        case .error(let message):
            message
        }
    }

    private var isError: Bool {
        if case .error = state { return true }
        return false
    }

    var body: some View {
        Group {
            if let displayText, !displayText.isEmpty {
                Text(displayText)
                    .typography(Typography.body)
                    .foregroundStyle(isError ? errorStyle : textStyle)
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
                    .animation(Animations.snap, value: displayText)
            }
        }
        .frame(minHeight: 22)
    }
}
