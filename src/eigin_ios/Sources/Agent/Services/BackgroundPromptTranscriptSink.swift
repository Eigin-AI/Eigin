/// Where background-prompt transcripts are recorded. Debug builds keep the
/// dev inspector's ring buffer (``BackgroundPromptDebug``); release records
/// nothing.
///
/// Pulled out of ``BackgroundPromptService`` so the record seam has a home of
/// its own, next to its implementers.
protocol BackgroundPromptTranscriptSink {
    func store(
        systemPrompt: String,
        apiMessages: [ChatMessage],
        producedMessages: [ChatMessage],
        rounds: Int,
        signal: String,
        reason: String
    )
}

/// Records nothing — the release default.
struct NoOpTranscriptSink: BackgroundPromptTranscriptSink {
    func store(
        systemPrompt: String,
        apiMessages: [ChatMessage],
        producedMessages: [ChatMessage],
        rounds: Int,
        signal: String,
        reason: String
    ) {}
}

#if DEBUG
/// Records into ``BackgroundPromptDebug`` — the debug default.
struct DebugTranscriptSink: BackgroundPromptTranscriptSink {
    func store(
        systemPrompt: String,
        apiMessages: [ChatMessage],
        producedMessages: [ChatMessage],
        rounds: Int,
        signal: String,
        reason: String
    ) {
        BackgroundPromptDebug().store(
            systemPrompt: systemPrompt,
            apiMessages: apiMessages,
            producedMessages: producedMessages,
            rounds: rounds,
            signal: signal,
            reason: reason
        )
    }
}
#endif
