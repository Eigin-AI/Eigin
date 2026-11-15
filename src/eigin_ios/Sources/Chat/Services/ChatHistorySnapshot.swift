import Foundation

/// Converts persisted history without monopolizing the UI executor on long chats.
@MainActor
enum ChatHistorySnapshot {
    /// Target under half a 120Hz frame (~8.3ms) for history work; individual reads can overrun.
    private static let batchBudget: Duration = .milliseconds(4)

    /// Reads models on their owning actor and preserves complete message order and metadata.
    static func messages(from persisted: [Message]) async throws -> [ChatMessage] {
        var messages: [ChatMessage] = []
        messages.reserveCapacity(persisted.count)
        var batchStarted = ContinuousClock.now
        for message in persisted {
            try Task.checkCancellation()
            messages.append(message.toChatMessage())
            if batchStarted.duration(to: .now) >= batchBudget {
                await Task.yield()
                batchStarted = .now
            }
        }
        try Task.checkCancellation()
        return messages
    }
}
