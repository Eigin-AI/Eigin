import Foundation

/// Conversation depth before the current response, independent of prompt paging.
struct RoutingTurnContext: Sendable {
    let responseTurnCount: Int

    init(responseTurnCount: Int) {
        self.responseTurnCount = responseTurnCount
    }

    /// Counts visible response exchanges; recovery fragments share their user's turn.
    init(messages: [ChatMessage]) {
        var count = 0
        var hasResponse = false
        for message in messages where !message.isCompactionSummary {
            if message.role == "user" { hasResponse = false }
            guard message.role == "assistant", !hasResponse,
                  message.toolCalls?.isEmpty ?? true,
                  !(message.content?.isEmpty ?? true) else { continue }
            count += 1
            hasResponse = true
        }
        responseTurnCount = count
    }
}

extension RouteRequest {
    /// Early responses require strong evidence before paying reasoning latency.
    var messageNeedsReasoning: Bool {
        let text = lastUserMessage ?? ""
        guard !text.isEmpty else { return false }
        let penalty = turnContext.map {
            QueryComplexity.threshold * Double(max(0, 4 - $0.responseTurnCount)) / 4
        } ?? 0
        return QueryComplexity.needsReasoning(text: text, conversationPenalty: penalty)
    }
}
