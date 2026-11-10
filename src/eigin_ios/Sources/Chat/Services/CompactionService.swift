import EiginSDK
import Foundation

/// Progress phases reported during compaction.
enum CompactionPhase {
    case waiting
    case streaming(Float) // 0.0–1.0 normalized against expected summary length
    case finalizing
}

/// Generates a conversation summary by asking the current model *inside* the
/// ongoing conversation — a cache-friendly continuation of the turn's exact
/// payload. Succeeds only when the reply carries a usable
/// `<conversation_summary>` block.
enum CompactionService {
    /// Fraction of the context window the summarise request may fill. It must
    /// fit the model the turn runs on, with headroom for the reply and estimator
    /// undercounting.
    static let summarizeRequestBudgetFraction: Double = 0.75

    /// Synthetic assistant acknowledgement inserted before the summarise
    /// instruction so two user messages never sit back-to-back (some providers
    /// reject unalternating roles).
    private static let summarizeAck = "Okay — summarizing instead of replying."

    /// Result of a compaction attempt.
    struct Outcome {
        /// The parsed summary, or `nil` when the attempt failed or produced
        /// unusable output. Callers set `needsCompaction` to retry next turn.
        let summary: String?
        /// True when the window-fit truncation dropped the *entire* covered
        /// history, leaving nothing to summarise — callers fall back to
        /// `[system] + retained` and must not retry.
        let droppedAllCovered: Bool
    }

    /// Summarises the older conversation by appending a summarise instruction to
    /// the turn's payload.
    ///
    /// `apiMessages` must be the exact payload being sent this turn (system
    /// prompt first, newest user message last) — the request appends to it
    /// byte-identically so the provider's prompt cache covers it.
    ///
    /// - `coveredCount`: number of conversation messages after the system prompt
    ///   that the summary will replace.
    /// - `retainedCount`: number of trailing conversation messages kept verbatim;
    ///   the instruction tells the model to skip them.
    ///
    /// Before sending, the covered history is truncated (oldest dropped) if the
    /// request wouldn't fit `summarizeRequestBudgetFraction` of the context
    /// window — an over-window summarise request is what fails on providers that
    /// reject or time out oversized prompts.
    static func compact(
        apiMessages inputMessages: [ChatMessage],
        coveredCount: Int,
        retainedCount: Int,
        contextWindow: Int,
        tools: [ToolDefinition]? = nil,
        cacheKey: String? = nil,
        baseURL: String,
        providerID: UUID,
        model: String,
        chatService: any ChatService,
        onProgress: (@Sendable (CompactionPhase) -> Void)? = nil
    ) async -> Outcome {
        // Summaries use visible history only; hidden continuation state is never summarized.
        let apiMessages = inputMessages.map { $0.reasoningScoped(to: nil) }
        let instruction = ChatMessage(
            role: "user",
            content: Prompt.Compaction.main(retainedCount: String(retainedCount))
        )
        // Keep user/assistant alternation when the turn payload ends on a user
        // message (the usual case: the message being answered).
        let suffix: [ChatMessage] =
            if apiMessages.last?.role == "user" {
                [ChatMessage(role: "assistant", content: summarizeAck), instruction]
            } else {
                [instruction]
            }

        var request = apiMessages + suffix

        // Window fit: shrink the covered history rather than sending an
        // oversized summarise request.
        let budget = Int(Double(contextWindow) * summarizeRequestBudgetFraction)
        let requestTokens = TokenEstimator.estimateRequest(
            messages: request,
            toolDefinitions: tools ?? []
        )
        if requestTokens > budget, coveredCount > 0 {
            let covered = Array(apiMessages.dropFirst().prefix(coveredCount))
            let nonCovered = [apiMessages[0]]
                + Array(apiMessages.dropFirst(1 + coveredCount))
                + suffix
            let fixedTokens = TokenEstimator.estimateRequest(
                messages: nonCovered,
                toolDefinitions: tools ?? []
            )
            let truncated = truncateForBudget(
                messages: covered,
                tokenBudget: budget - fixedTokens
            )
            if truncated.count < covered.count {
                AppLogger.info(
                    "Compaction: dropping \(public: covered.count - truncated.count) oldest messages so the summarise request fits the context window",
                    category: .chat
                )
            }
            if truncated.isEmpty {
                // Nothing left to summarise; the caller drops the covered
                // history and moves on rather than retrying a doomed request.
                return Outcome(summary: nil, droppedAllCovered: true)
            }
            request = [apiMessages[0]] + truncated
                + Array(apiMessages.dropFirst(1 + coveredCount))
                + suffix
        }

        onProgress?(.waiting)

        var summary = ""
        // Progress scales against the request we're actually sending — after
        // window-fit truncation, not the original conversation size.
        let expectedLength = max(200, TokenEstimator.estimateRequest(
            messages: request,
            toolDefinitions: tools ?? []
        ) / 2)

        do {
            // Best-effort background work: a foreground chat send preempts it.
            try await LocalGeneration.$priority.withValue(.background) {
                let stream = try await chatService.chatCompletionEventStream(
                    baseURL: baseURL,
                    providerID: providerID,
                    messages: request,
                    model: model,
                    tools: tools,
                    cacheKey: cacheKey
                )

                for try await event in stream {
                    if case .contentDelta(let delta) = event {
                        summary += delta
                        let progress = min(1.0, Float(summary.count) / Float(expectedLength))
                        onProgress?(.streaming(progress))
                    }
                }
            }
        } catch {
            AppLogger.error(
                "Summary generation failed: \(private: error.localizedDescription)",
                category: .chat
            )
            return Outcome(summary: nil, droppedAllCovered: false)
        }

        onProgress?(.finalizing)

        return Outcome(
            summary: parseSummary(summary),
            droppedAllCovered: false
        )
    }

    /// Extracts the summary from the model's reply. Requires the
    /// `<conversation_summary>` tag: in-conversation, an untagged reply is most
    /// likely the model answering the user — the failure mode the tags exist to
    /// prevent — and must not replace the summarised history. A missing closing
    /// tag is tolerated (take everything after the opening tag). Returns `nil`
    /// when unusable or too short to be useful.
    static func parseSummary(_ raw: String) -> String? {
        switch EiginSDK.Experimental.Context.parseSummary(raw) {
        case .accepted(let summary):
            return summary
        case .missingOpeningTag(let trimmedLength):
            AppLogger.warning(
                "Summary reply missing <conversation_summary> tag, skipping (\(public: trimmedLength) chars)",
                category: .chat
            )
            return nil
        case .tooShort(let bodyLength):
            AppLogger.warning(
                "Summary block too short (\(public: bodyLength) chars), skipping",
                category: .chat
            )
            return nil
        }
    }

    // MARK: - Retention

    /// Returns the newest messages to keep verbatim after compaction: whole
    /// turns (a user message plus any following assistant/tool messages), so a
    /// tool-call round is never split. Always keeps at least `minimumTurns`
    /// turns when present, then keeps walking back while the window fits
    /// `tokenBudget`.
    ///
    /// The walk stops at a synthetic compaction-summary carrier — those mark
    /// where the previous summary's coverage begins, and its content must be
    /// re-summarised, not retained.
    static func retainedTail(
        messages: [ChatMessage],
        tokenBudget: Int,
        minimumTurns: Int = 2
    ) -> [ChatMessage] {
        let selection = EiginSDK.Experimental.Context.retainedTail(
            messages: ContextSDK.messages(messages), tokenBudget: tokenBudget,
            minimumTurns: minimumTurns
        )
        return ContextSDK.apply(selection, to: messages)
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
        let selection = EiginSDK.Experimental.Context.truncateForBudget(
            messages: ContextSDK.messages(messages), tokenBudget: tokenBudget
        )
        return ContextSDK.apply(selection, to: messages)
    }

    /// Sliding window with hysteresis, for small-context on-device models.
    ///
    /// Keeps the newest messages within `highMark` tokens, but only advances the
    /// drop boundary once the conversation has grown a further
    /// `highMark - lowMark` tokens. Between advances the kept prefix is identical
    /// from turn to turn, so the on-device KV cache is reused instead of being
    /// re-prefilled every turn. (A plain budget truncation drops the oldest
    /// message on nearly every turn once full, which changes the prefix each time
    /// and forces a full re-prefill.)
    ///
    /// Whole messages are dropped — never partially truncated — so the prefix
    /// stays byte-stable. The result is always a contiguous suffix that never
    /// exceeds `highMark` tokens; at least the most recent message is always kept.
    static func windowedForBudget(
        messages: [ChatMessage],
        highMark: Int,
        lowMark: Int
    ) -> [ChatMessage] {
        let selection = EiginSDK.Experimental.Context.windowedForBudget(
            messages: ContextSDK.messages(messages), highMark: highMark, lowMark: lowMark
        )
        return ContextSDK.apply(selection, to: messages)
    }
}
