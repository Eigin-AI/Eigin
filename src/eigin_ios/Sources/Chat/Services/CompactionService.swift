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
        apiMessages: [ChatMessage],
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
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.range(of: "<conversation_summary>") else {
            AppLogger.warning(
                "Summary reply missing <conversation_summary> tag, skipping (\(public: trimmed.count) chars)",
                category: .chat
            )
            return nil
        }
        var body = String(trimmed[open.upperBound...])
        if let close = body.range(of: "</conversation_summary>") {
            body = String(body[..<close.lowerBound])
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count >= 50 else {
            AppLogger.warning(
                "Summary block too short (\(public: body.count) chars), skipping",
                category: .chat
            )
            return nil
        }
        return body
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
        var retainedStart = messages.count
        var budgetLeft = tokenBudget
        var turnsKept = 0
        var scanFrom = messages.count
        while scanFrom > 0 {
            // A turn is a user message plus everything after it; whole turns are
            // kept so a tool-call round is never split.
            guard
                let turnStart = messages[..<scanFrom].lastIndex(where: {
                    $0.role == "user"
                })
            else { break }
            // A synthetic summary carrier marks where the previous summary's
            // coverage begins — re-summarise it, don't retain it.
            if messages[turnStart].content?.hasPrefix("<conversation_summary>") == true {
                break
            }
            let turn = Array(messages[turnStart ..< scanFrom])
            let turnTokens = TokenEstimator.estimate(messages: turn)
            if turnsKept >= minimumTurns, turnTokens > budgetLeft { break }
            budgetLeft -= turnTokens
            turnsKept += 1
            retainedStart = turnStart
            scanFrom = turnStart
        }
        guard retainedStart < messages.count else { return [] }
        return Array(messages[retainedStart...])
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

        // Newest first; also count tool-call framing, via the shared estimator.
        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            let msgTokens = TokenEstimator.estimate(messages: [messages[i]])
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
        guard !messages.isEmpty else { return [] }
        guard highMark > 0 else { return [messages[messages.count - 1]] }

        // Cumulative tokens before each message. `cumulativeBefore[i]` is the cost
        // of messages[0..<i]; these values don't change when newer messages are
        // appended, which is what lets the boundary stay put across turns.
        var cumulativeBefore = [Int](repeating: 0, count: messages.count + 1)
        for i in messages.indices {
            let cost = TokenEstimator.estimate(messages: [messages[i]])
            cumulativeBefore[i + 1] = cumulativeBefore[i] + cost
        }
        let total = cumulativeBefore[messages.count]
        if total <= highMark { return messages }

        let low = max(0, min(lowMark, highMark - 1))
        let step = highMark - low // ≥ 1
        // Quantise the dropped-token threshold to whole multiples of `step` so it
        // only increases in jumps. Within a jump the boundary — and therefore the
        // kept prefix — is identical from one turn to the next. The flooring also
        // bounds the kept size below `highMark`: kept = total - dropped ≤ low + r
        // where 0 ≤ r < step, so kept < highMark.
        let dropThreshold = ((total - low) / step) * step

        // Drop the fewest oldest messages needed to clear the threshold.
        var start = 0
        while start < messages.count, cumulativeBefore[start] < dropThreshold {
            start += 1
        }
        // Never drop everything: keep at least the most recent message.
        if start >= messages.count { start = messages.count - 1 }
        return Array(messages[start...])
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
}
