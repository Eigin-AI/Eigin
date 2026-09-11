#if DEBUG
import Foundation

struct BackgroundPromptTranscript: Codable, Identifiable {
    var id: Date {
        timestamp
    }

    let timestamp: Date
    let systemPrompt: String
    let messages: [ChatMessage]
    let producedMessages: [ChatMessage]
    let rounds: Int
    let signal: String
    let reason: String
}

/// Dev inspector ring buffer for background-prompt transcripts, backed by
/// `UserDefaults`. Conforms to ``BackgroundPromptTranscriptSink`` so the
/// background service records through injection instead of `#if DEBUG` calls.
struct BackgroundPromptDebug: BackgroundPromptTranscriptSink {
    private static let maxStored = 5
    private static let key = "backgroundPromptTranscripts"

    func store(
        systemPrompt: String,
        apiMessages: [ChatMessage],
        producedMessages: [ChatMessage],
        rounds: Int,
        signal: String,
        reason: String
    ) {
        let transcript = BackgroundPromptTranscript(
            timestamp: Date(),
            systemPrompt: systemPrompt,
            messages: apiMessages,
            producedMessages: producedMessages,
            rounds: rounds,
            signal: signal,
            reason: reason
        )

        var transcripts = Self.transcripts()
        transcripts.insert(transcript, at: 0)
        if transcripts.count > Self.maxStored {
            transcripts = Array(transcripts.prefix(Self.maxStored))
        }

        if let data = try? JSONEncoder().encode(transcripts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    static func getTranscripts() -> [BackgroundPromptTranscript] {
        transcripts()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func transcripts() -> [BackgroundPromptTranscript] {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([BackgroundPromptTranscript].self, from: $0) }
            ?? []
    }
}
#endif
