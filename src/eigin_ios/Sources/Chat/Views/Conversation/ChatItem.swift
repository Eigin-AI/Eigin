import Foundation

/// A single item in a chat feed. Each case renders differently in `ChatFeed`.
enum ChatItem: Identifiable {
    case message(id: String, role: String, content: String, attachments: [MessageAttachment] = [])
    case status(id: String, text: String)
    case error(id: String, error: ConnectionError)
    case toolGroup(id: String, tools: [ToolCallInfo])
    case options(id: String, set: OptionSet)
    case compaction(
        id: String,
        progress: Float?,
        summary: String?
    ) // nil progress = finished, 0–1 = in-progress

    var id: String {
        switch self {
        case .message(let id, _, _, _): id
        case .status(let id, _): id
        case .error(let id, _): id
        case .toolGroup(let id, _): id
        case .options(let id, _): id
        case .compaction(let id, _, _): id
        }
    }
}

extension ChatItem {
    /// Builds the canonical list of chat items from committed messages,
    /// in-progress tool events, streaming state, and an optional error.
    @MainActor
    static func buildItems(
        from messages: [ChatMessage],
        chatLoop: AgenticChatLoop,
        chatError: ConnectionError?
    ) -> [ChatItem] {
        var items: [ChatItem] = []
        var pendingTools: [ToolCallInfo] = []
        var pendingGroupID: String?

        // Build a lookup of tool results from role:"tool" messages.
        var toolResults: [String: String] = [:]
        for message in messages where message.role == "tool" {
            if let callID = message.toolCallID, let content = message.content {
                toolResults[callID] = content
            }
        }

        func flushTools() {
            guard !pendingTools.isEmpty else { return }
            items.append(.toolGroup(id: pendingGroupID ?? "tools", tools: pendingTools))
            pendingTools = []
            pendingGroupID = nil
        }

        for message in messages {
            switch message.role {
            case "assistant":
                // Render text content before tool calls so prose appears above
                // the tool group in the feed (matching the model's output order).
                if let content = message.content,
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    flushTools()
                    items.append(.message(
                        id: "msg-\(message.localID)",
                        role: "assistant",
                        content: content
                    ))
                }
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    // Only start a new group if there isn't one accumulating.
                    // This merges consecutive tool-only rounds into one visual group,
                    // so a multi-round tool chain without prose appears as a single block.
                    if pendingGroupID == nil {
                        pendingGroupID = "tools-\(toolCalls[0].id)"
                    }
                    for call in toolCalls {
                        pendingTools.append(ToolCallInfo(
                            id: call.id,
                            name: call.function.name,
                            status: .completed,
                            arguments: call.function.arguments,
                            result: toolResults[call.id]
                        ))
                    }
                }
            case "tool":
                continue
            default:
                flushTools()
                if message.isCompactionSummary {
                    let summaryText: String? = if let content = message.content {
                        content.replacingOccurrences(
                            of: "Summary of earlier conversation:\n\n",
                            with: ""
                        )
                    } else {
                        nil
                    }
                    items.append(.compaction(
                        id: "compaction-\(message.localID)",
                        progress: nil,
                        summary: summaryText
                    ))
                } else {
                    // User (and other non-tool) messages. Content may be nil for image-only sends.
                    let rawContent = message.content ?? ""
                    let displayContent = ChatTags.stripAll(from: rawContent)
                    let attachments = message.attachments ?? []
                    if !displayContent.isEmpty || !attachments.isEmpty {
                        items.append(.message(
                            id: "msg-\(message.localID)",
                            role: message.role,
                            content: displayContent,
                            attachments: attachments
                        ))
                    }
                }
            }
        }

        // In-progress tool events not yet committed to message history
        let committedIDs = Set(messages.compactMap(\.toolCalls).flatMap(\.self).map(\.id))
        for event in chatLoop.toolEvents where !committedIDs.contains(event.id) {
            if pendingGroupID == nil { pendingGroupID = "tools-\(event.id)" }
            pendingTools.append(ToolCallInfo(
                id: event.id,
                name: event.toolName,
                status: event.status,
                arguments: event.arguments
            ))
        }

        flushTools()

        // Append active option set at the end of the feed
        if let optionSet = chatLoop.pendingOptions {
            items.append(.options(id: optionSet.id, set: optionSet))
        }

        if let chatError {
            items.append(.error(id: "error", error: chatError))
        }
        return items
    }
}
