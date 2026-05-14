#if DEBUG
import SwiftUI

struct TranscriptDetail: View {
    let transcript: BackgroundPromptTranscript
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss

    private struct TimelineItem: Identifiable {
        let id = UUID()
        let index: Int
        let type: ItemType

        enum ItemType {
            case message(ChatMessage)
            case toolCall(ToolCall)
        }
    }

    private var timeline: [TimelineItem] {
        var items: [TimelineItem] = []
        var idx = 0

        for message in transcript.messages {
            items.append(TimelineItem(index: idx, type: .message(message)))
            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    idx += 1
                    items.append(TimelineItem(index: idx, type: .toolCall(toolCall)))
                }
            }
            idx += 1
        }

        for message in transcript.producedMessages {
            items.append(TimelineItem(index: idx, type: .message(message)))
            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    idx += 1
                    items.append(TimelineItem(index: idx, type: .toolCall(toolCall)))
                }
            }
            idx += 1
        }

        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.n16) {
                    headerSection
                    timelineSection
                }
                .padding()
            }
            .background(colors.surface.standard.base.ignoresSafeArea())
            .navigationTitle(Localized.Debug.transcriptTitle, style: Typography.titleXl)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localized.Debug.done) { dismiss() }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.n4) {
            HStack {
                Text(transcript.signal.hasPrefix("notify") ? "Notify" : "Silent")
                    .typography(Typography.titleXS)
                    .foregroundStyle(transcript.signal.hasPrefix("notify") ? .green : .orange)
                Spacer()
                Text(Localized.Agent.roundsCount(String(transcript.rounds)))
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
            }
            Text(transcript.reason)
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
            Text(transcript.timestamp, style: .date)
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
            Text(verbatim: " ")
            Text(transcript.timestamp, style: .time)
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
        .padding()
        .background(colors.surface.standard.base)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: Spacing.n4) {
            Text(Localized.Ui.timeline(String(timeline.count)))
                .typography(Typography.titleXS)

            ForEach(timeline) { item in
                switch item.type {
                case .message(let message):
                    messageBubble(message, index: item.index)
                case .toolCall(let toolCall):
                    toolCallBubble(toolCall, index: item.index)
                }
            }
        }
    }

    private func toolCallBubble(_ toolCall: ToolCall, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "[\(index)]")
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.disabled)
                Text(verbatim: "→ \(toolCall.function.name)")
                    .font(Typography.miniLabel.font.bold())
                    .foregroundStyle(.purple)
            }

            let args = toolCall.function.arguments
            if let data = args.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(
                   withJSONObject: json,
                   options: .prettyPrinted
               ),
               let prettyString = String(data: prettyData, encoding: .utf8)
            {
                Text(prettyString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.text.standard.muted)
                    .textSelection(.enabled)
            } else {
                Text(args)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.text.standard.muted)
                    .textSelection(.enabled)
            }
        }
        .padding(Spacing.n4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface.standard.base.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func messageBubble(_ message: ChatMessage, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "[\(index)]")
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.disabled)
                Text(message.role)
                    .font(Typography.miniLabel.font.bold())
                    .foregroundStyle(roleColor(message.role))
            }

            if let content = message.content, !content.isEmpty {
                if content.hasPrefix("{") || content.hasPrefix("[") {
                    if let data = content.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data),
                       let prettyData = try? JSONSerialization.data(
                           withJSONObject: json,
                           options: .prettyPrinted
                       ),
                       let prettyString = String(data: prettyData, encoding: .utf8)
                    {
                        Text(prettyString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(colors.text.standard.muted)
                            .textSelection(.enabled)
                    } else {
                        Text(content)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(colors.text.standard.muted)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(content)
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(Spacing.n4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface.standard.base.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "system": .blue
        case "user": .green
        case "assistant": .orange
        default: .gray
        }
    }
}
#endif
