import Foundation

/// Progress phases reported during compaction.
enum CompactionPhase {
    case waiting
    case streaming(Float) // 0.0–1.0 normalized against expected summary length
    case finalizing
}

/// Generates a conversation summary by making an API call to the same model.
enum CompactionService {
    /// Summarises the given messages into a single block of text.
    /// Returns `nil` if the API call fails or the result is too short to be useful.
    static func compact(
        messages: [ChatMessage],
        baseURL: String,
        providerID: UUID,
        model: String,
        chatService: ChatService,
        onProgress: (@Sendable (CompactionPhase) -> Void)? = nil
    ) async -> String? {
        let transcript = formatTranscript(messages)

        let summaryMessages: [ChatMessage] = [
            ChatMessage(role: "system", content: Prompt.Compaction.main),
            ChatMessage(role: "user", content: transcript),
        ]

        onProgress?(.waiting)

        var summary = ""
        let expectedLength = max(200, transcript.count / 8)

        do {
            let stream = try await chatService.chatCompletionStream(
                baseURL: baseURL,
                providerID: providerID,
                messages: summaryMessages,
                model: model
            )

            for try await token in stream {
                summary += token
                let progress = min(1.0, Float(summary.count) / Float(expectedLength))
                onProgress?(.streaming(progress))
            }
        } catch {
            AppLogger.error(
                "Summary generation failed: \(private: error.localizedDescription)",
                category: .chat
            )
            return nil
        }

        onProgress?(.finalizing)

        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 50 else {
            AppLogger.warning(
                "Summary too short (\(public: trimmed.count) chars), skipping",
                category: .chat
            )
            return nil
        }

        return trimmed
    }

    // MARK: - Truncation

    /// Returns the newest messages that fit within the given token budget.
    /// Walks backward (newest first), accumulating token estimates with per-message
    /// framing overhead. When the oldest message that would fit exceeds the remaining
    /// budget, its content is truncated with "…" so partial context is preserved
    /// rather than dropping it entirely.
    static func truncateForBudget(
        messages: [ChatMessage],
        tokenBudget: Int
    ) -> [ChatMessage] {
        var accumulated = 0
        var startIndex = messages.count

        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            let msgTokens = TokenEstimator.estimate(messages[i].content ?? "") + 4
            if accumulated + msgTokens > tokenBudget {
                // Partial fit: truncate the oldest message to fill remaining budget.
                let remaining = tokenBudget - accumulated - 4
                if i == startIndex - 1, remaining > 20 {
                    let truncated = truncateContent(
                        messages[i].content ?? "", maxTokens: remaining
                    )
                    var partial = messages[i]
                    partial = ChatMessage(
                        role: partial.role,
                        content: truncated,
                        toolCallID: partial.toolCallID,
                        name: partial.name,
                        toolCalls: partial.toolCalls
                    )
                    var result = [partial]
                    result.append(contentsOf: messages[(i + 1)...])
                    return result
                }
                break
            }
            accumulated += msgTokens
            startIndex = i
        }

        if startIndex >= messages.count { return [] }
        return Array(messages[startIndex...])
    }

    /// Truncates content to approximately `maxTokens` tokens, appending "…".
    /// Uses the ~4 chars/token heuristic to avoid re-estimating repeatedly.
    private static func truncateContent(_ content: String, maxTokens: Int) -> String {
        let maxChars = maxTokens * 4
        guard content.count > maxChars else { return content }
        let start = content.index(content.endIndex, offsetBy: -(maxChars - 1))
        return "…" + String(content[start...])
    }

    // MARK: - Private

    private static func formatTranscript(_ messages: [ChatMessage]) -> String {
        messages.compactMap { msg in
            guard let content = msg.content, !content.isEmpty else { return nil }
            let label: String = switch msg.role {
            case "user": "User"
            case "assistant": "Assistant"
            case "system": "System"
            case "tool": "Tool(\(msg.name ?? "unknown"))"
            default: msg.role.capitalized
            }
            return "\(label): \(content)"
        }.joined(separator: "\n\n")
    }
}
