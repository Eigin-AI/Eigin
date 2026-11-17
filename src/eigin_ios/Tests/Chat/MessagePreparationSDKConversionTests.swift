@testable import Eigin
import EiginSDK
import Foundation
import Testing

@Suite("SDK outgoing preparation integration")
struct MessagePreparationSDKConversionTests {
    @Test func preservesMetadataIdentityAndAttachmentsWithoutMutatingHistory() throws {
        let attachment = MessageAttachment(
            kind: .image,
            mimeType: "image/png",
            width: 12,
            height: 24,
            byteCount: 99
        )
        let reasoning = ReasoningHistory(
            origin: .init(providerID: UUID(), endpoint: "https://example.test/v1", model: "model"),
            format: "opaque", payload: Data([0, 255, 128]), visibleText: "answer",
            additionalInputTokens: 42
        )
        var user = ChatMessage(
            role: "user",
            content: "question",
            providerMetadata: [:],
            attachments: [attachment]
        )
        user.compactionRetainedMessageCount = 0
        let assistant = ChatMessage(
            role: "assistant",
            content: "answer",
            providerMetadata: ["signature": "private"],
            reasoningHistory: reasoning
        )
        let history = [user, assistant]
        let selected = try MessagePreparationSDKConversion.select(history)
        let result = MessagePreparationSDKConversion.prepare(
            selected, history: history, systemPrompt: "system", systemHint: "hint",
            supportsVision: true
        )
        #expect(result.map(\.role) == ["system", "user", "assistant"])
        #expect(result[1].localID == user.localID)
        #expect(result[1].attachments == [attachment])
        #expect(result[1].providerMetadata == [:])
        #expect(result[1].compactionRetainedMessageCount == 0)
        #expect(result[1].content == "question\n\nhint")
        #expect(result[2].localID == assistant.localID)
        #expect(result[2].providerMetadata == assistant.providerMetadata)
        #expect(result[2].reasoningHistory == reasoning)
        #expect(history[0].content == "question")
        #expect(history[0].attachments == [attachment])
        #expect(history[1].reasoningHistory == reasoning)

        let hinted = MessagePreparationSDKConversion.appendHint("paging", to: result)
        #expect(hinted[1].localID == user.localID)
        #expect(hinted[1].attachments == [attachment])
        #expect(hinted[2].reasoningHistory == reasoning)
        #expect(result[1].content == "question\n\nhint")
    }

    @Test func selectionFeedsHintsAndAssemblyPreservesSummaryIdentity() throws {
        let old = ChatMessage(role: "user", content: "old")
        let retained = ChatMessage(role: "user", content: "retained")
        var summary = ChatMessage(role: "system", content: "memory")
        summary.isCompactionSummary = true
        summary.compactionRetainedMessageCount = 1
        let history = [old, retained, summary]
        let selected = try MessagePreparationSDKConversion.select(history)
        let hintHistory = MessagePreparationSDKConversion.conversation(selected, history: history)
        #expect(hintHistory.map(\.localID) == [retained.localID])
        let result = MessagePreparationSDKConversion.prepare(
            selected, history: history, systemPrompt: "small prompt", systemHint: "hint",
            supportsVision: false
        )
        #expect(result.map(\.role) == ["system", "user", "assistant", "user"])
        #expect(result[0].content == "small prompt")
        #expect(result[1].localID == "context-summary")
        #expect(result[2].localID == "context-summary-ack")
        #expect(result[3].localID == retained.localID)
        #expect(result[3].content == "retained\n\nhint")
        #expect(summary.isCompactionSummary)
        #expect(summary.content == "memory")
    }

    @Test func nonVisionPreparationStripsOnlyOutgoingReferences() throws {
        let attachment = MessageAttachment(kind: .image, mimeType: "image/png", byteCount: 123)
        let user = ChatMessage(
            role: "user",
            content: nil,
            providerMetadata: ["key": "value"],
            attachments: [attachment]
        )
        let selected = try MessagePreparationSDKConversion.select([user])
        let output = MessagePreparationSDKConversion.prepare(
            selected, history: [user], systemPrompt: "system", systemHint: nil,
            supportsVision: false
        )
        #expect(output[1].attachments == nil)
        #expect(output[1]
            .content == "[an image was attached here, but this model cannot view images]")
        #expect(output[1].localID == user.localID)
        #expect(output[1].providerMetadata == user.providerMetadata)
        #expect(user.attachments == [attachment])
        #expect(user.content == nil)
    }

    @Test func invalidSummaryFailsSafely() {
        var summary = ChatMessage(role: "system", content: "memory")
        summary.isCompactionSummary = true
        summary.compactionRetainedMessageCount = -1
        #expect(throws: EiginSDK.Experimental.Conversation.PreparationError.self) {
            try MessagePreparationSDKConversion.select([summary])
        }
    }

    @Test func duplicateRepairPreservesSwiftUnicodeEquality() throws {
        let calls = ChatMessage(
            role: "assistant",
            toolCalls: [.init(
                id: "é",
                type: "function",
                function: .init(name: "lookup", arguments: "{}")
            )]
        )
        let first = ChatMessage(
            role: "tool",
            content: "café",
            toolCallID: "é",
            providerMetadata: ["clé": "café"]
        )
        let duplicate = ChatMessage(
            role: "tool",
            content: "cafe\u{301}",
            toolCallID: "e\u{301}",
            providerMetadata: ["cle\u{301}": "cafe\u{301}"]
        )
        #expect(first.content == duplicate.content)
        let history = [calls, first, duplicate]
        let output = try MessagePreparationSDKConversion.prepare(
            MessagePreparationSDKConversion.select(history), history: history,
            systemPrompt: "system", systemHint: nil, supportsVision: true
        )
        #expect(output.count == 3)
        #expect(output[2].localID == first.localID)
        #expect(try Array(#require(output[2].content?.utf8)) ==
            Array(#require(first.content?.utf8)))
    }
}

extension MessagePreparationSDKConversionTests {
    @Test func longHistoryConversionPreservesSourceIdentity() throws {
        let history = (0 ..< 1000).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "\(index):" + String(repeating: "x", count: 1000)
            )
        }
        let selected = try MessagePreparationSDKConversion.select(history)
        let hintHistory = MessagePreparationSDKConversion.conversation(selected, history: history)
        let output = MessagePreparationSDKConversion.prepare(
            selected, history: history, systemPrompt: "system", systemHint: "hint",
            supportsVision: true
        )
        #expect(hintHistory.map(\.localID) == history.map(\.localID))
        #expect(output.dropFirst().map(\.localID) == history.map(\.localID))
    }
}
