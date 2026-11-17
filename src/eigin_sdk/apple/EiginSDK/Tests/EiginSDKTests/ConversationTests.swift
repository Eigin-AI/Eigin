import EiginSDK
import Foundation
import Testing

private typealias Conversation = EiginSDK.Experimental.Conversation

@Suite("Experimental conversation bindings")
struct ConversationTests {
    private func message(_ role: String, _ text: String?) -> Conversation.Message {
        .init(sourceIndex: nil, role: role, content: text, name: nil, toolCallId: nil,
              toolCalls: nil, attachments: nil, providerMetadata: nil, reasoningHistory: nil,
              isCompactionSummary: false, compactionRetainedMessageCount: nil)
    }

    @Test func preparesValuesAcrossBindingsWithoutLosingMetadata() throws {
        var user = message("user", "question")
        user.attachments = [.init(id: "opaque-reference", kind: "image", mimeType: "image/png", width: Int64.max, height: nil, byteCount: 100)]
        user.providerMetadata = [:]
        var assistant = message("assistant", "answer")
        assistant.reasoningHistory = .init(
            origin: .init(providerId: "opaque-provider", endpoint: "endpoint", model: "model"),
            format: "opaque", payload: Data([0, 255]), visibleText: "answer", additionalInputTokens: 42
        )
        let selected = try Conversation.select([user, assistant])
        #expect(selected.messages[1].sourceIndex == 1)
        let output = Conversation.prepare(selected, options: .init(systemPrompt: "system", systemHint: "hint", supportsVision: true))
        #expect(output.map(\.message.role) == ["system", "user", "assistant"])
        #expect(output[1].origin == .history(sourceIndex: 0))
        #expect(output[1].message.attachments == user.attachments)
        #expect(output[1].message.providerMetadata == [:])
        #expect(output[2].message.providerMetadata == nil)
        #expect(output[2].message.reasoningHistory == assistant.reasoningHistory)
        #expect(user.content == "question")
        let hinted = Conversation.appendHint("paging", to: output)
        #expect(hinted[1].message.content == "question\n\nhint\n\npaging")
        #expect(hinted[2].message.reasoningHistory == assistant.reasoningHistory)
    }

    @Test func summarySelectionAndErrorsCrossBindings() throws {
        var summary = message("system", "memory")
        summary.isCompactionSummary = true
        summary.compactionRetainedMessageCount = Int64.max
        let selected = try Conversation.select([message("user", "retained"), summary])
        #expect(selected.messages.count == 1)
        #expect(selected.summary == "memory")
        let output = Conversation.prepare(selected, options: .init(systemPrompt: "system", systemHint: nil, supportsVision: false))
        #expect(output[1].origin == .summary)
        #expect(output[2].origin == .summaryAcknowledgement)
        summary.compactionRetainedMessageCount = Int64.min
        #expect(throws: Conversation.PreparationError.self) {
            try Conversation.select([summary])
        }
    }
}

extension ConversationTests {
    @Test func longHistoryPreparationPreservesOrdering() throws {
        let history = (0 ..< 1000).map { index in
            message(index.isMultiple(of: 2) ? "user" : "assistant", "\(index):" + String(repeating: "x", count: 1000))
        }
        let selected = try Conversation.select(history)
        let output = Conversation.prepare(selected, options: .init(systemPrompt: "system", systemHint: "hint", supportsVision: true))
        #expect(output.count == 1001)
        #expect(output.last?.origin == .history(sourceIndex: 999))
    }
}
