@testable import Eigin
import EiginSDK

/// Test-only request builders using the production SDK conversion adapter.
enum MessagePreparationTestSupport {
    static func splitAtLatestSummary(_ messages: [ChatMessage])
        -> (summary: String?, conversation: [ChatMessage])
    {
        let selected = try! MessagePreparationSDKConversion.select(messages)
        return (
            selected.summary,
            MessagePreparationSDKConversion.conversation(selected, history: messages)
        )
    }

    static func preparedHistory(
        _ messages: [ChatMessage],
        supportsVision: Bool = true
    ) -> [ChatMessage] {
        let selected = try! MessagePreparationSDKConversion.select(messages)
        return Array(MessagePreparationSDKConversion.prepare(
            selected, history: messages, systemPrompt: "", systemHint: nil,
            supportsVision: supportsVision
        ).dropFirst())
    }

    static func buildAPIMessages(
        agent: Agent, conversationMessages: [ChatMessage],
        compactionSummary: String? = nil, systemHint: String? = nil
    ) -> [ChatMessage] {
        var selected = try! MessagePreparationSDKConversion.select(conversationMessages)
        selected.summary = compactionSummary
        return MessagePreparationSDKConversion.prepare(
            selected, history: conversationMessages, systemPrompt: SystemPrompt.build(for: agent),
            systemHint: systemHint, supportsVision: true
        )
    }
}
