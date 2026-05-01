import Foundation
import SwiftData

#if DEBUG
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

enum BackgroundPromptDebug {
    private static let maxStored = 5
    private static let key = "backgroundPromptTranscripts"

    static func store(
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

        var transcripts = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([BackgroundPromptTranscript].self, from: $0) }
            ?? []

        transcripts.insert(transcript, at: 0)
        if transcripts.count > maxStored {
            transcripts = Array(transcripts.prefix(maxStored))
        }

        if let data = try? JSONEncoder().encode(transcripts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func getTranscripts() -> [BackgroundPromptTranscript] {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([BackgroundPromptTranscript].self, from: $0) }
            ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
#endif
