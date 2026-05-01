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
                VStack(alignment: .leading, spacing: Spacing.md) {
                    headerSection
                    timelineSection
                }
                .padding()
            }
            .background(colors.background.ignoresSafeArea())
            .navigationTitle(Localized.Debug.transcriptTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localized.Debug.done) { dismiss() }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(transcript.signal.hasPrefix("notify") ? "Notify" : "Silent")
                    .font(Typography.headline)
                    .foregroundStyle(transcript.signal.hasPrefix("notify") ? .green : .orange)
                Spacer()
                Text(Localized.Agent.roundsCount(String(transcript.rounds)))
                    .font(Typography.caption)
                    .foregroundStyle(colors.textSecondary)
            }
            Text(transcript.reason)
                .font(Typography.caption)
                .foregroundStyle(colors.textSecondary)
            Text(transcript.timestamp, style: .date)
                .font(Typography.caption)
                .foregroundStyle(colors.textSecondary)
            Text(verbatim: " ")
            Text(transcript.timestamp, style: .time)
                .font(Typography.caption)
                .foregroundStyle(colors.textSecondary)
        }
        .padding()
        .background(colors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Localized.Ui.timeline(String(timeline.count)))
                .font(Typography.headline)

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
                    .font(Typography.caption)
                    .foregroundStyle(colors.textTertiary)
                Text(verbatim: "→ \(toolCall.function.name)")
                    .font(Typography.caption.bold())
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
                    .foregroundStyle(colors.textSecondary)
                    .textSelection(.enabled)
            } else {
                Text(args)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .padding(Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func messageBubble(_ message: ChatMessage, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "[\(index)]")
                    .font(Typography.caption)
                    .foregroundStyle(colors.textTertiary)
                Text(message.role)
                    .font(Typography.caption.bold())
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
                            .foregroundStyle(colors.textSecondary)
                            .textSelection(.enabled)
                    } else {
                        Text(content)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(colors.textSecondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(content)
                        .font(Typography.caption)
                        .foregroundStyle(colors.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceSecondary.opacity(0.5))
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
