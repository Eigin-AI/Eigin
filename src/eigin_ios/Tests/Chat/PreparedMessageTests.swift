@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Prepared message persistence")
struct PreparedMessageTests {
    @Test("Concurrent preparation preserves message metadata and order through persistence")
    @MainActor
    func roundTrip() async throws {
        let id = UUID()
        let calls = [ToolCall(
            id: "call-1", type: "function",
            function: .init(name: "lookup", arguments: "{\"query\":\"hello\"}")
        )]
        let attachments = [MessageAttachment(kind: .image, mimeType: "image/png", byteCount: 42)]
        var assistant = ChatMessage(
            role: "assistant", content: "Answer", toolCalls: calls,
            attachments: attachments, localID: "msg-\(id.uuidString)"
        )
        assistant.reasoningHistory = ReasoningHistory(
            origin: ReasoningOrigin(
                providerID: UUID(),
                endpoint: "https://example.com",
                model: "test"
            ),
            format: "test", payload: Data(repeating: 65, count: 100_000),
            visibleText: "Answer", additionalInputTokens: 123
        )
        assistant.isCompactionSummary = true
        assistant.compactionRetainedMessageCount = 2
        let tool = ChatMessage(role: "tool", content: "Result", toolCallID: "call-1")
        let prepared = await PreparedMessage.prepare([assistant, tool])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: config
        )
        let context = ModelContext(container)
        let models = prepared.map { $0.makeMessage() }
        for model in models {
            context.insert(model)
        }
        try context.save()
        let restored = try ModelContext(container).fetch(FetchDescriptor<Message>())
        let saved = try #require(restored.first { $0.id == id }).toChatMessage()
        #expect(saved.content == assistant.content)
        #expect(saved.toolCalls == calls)
        #expect(saved.attachments == attachments)
        #expect(saved.reasoningHistory == assistant.reasoningHistory)
        #expect(saved.isCompactionSummary)
        #expect(saved.compactionRetainedMessageCount == 2)
        #expect(models.map(\.role) == ["assistant", "tool"])
        #expect(models[1].toolCallID == "call-1")
        #expect(restored.count == 2)
    }
}
