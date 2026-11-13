@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("AnthropicClient", .serialized)
struct AnthropicClientTests {
    private let baseURL = "https://api.anthropic.com/v1"

    @Test(arguments: [false, true])
    func requiresMessageStop(complete: Bool) async throws {
        let session = FakeURLProtocol.fakeSession()
        var sse = "event: message_delta\ndata: {\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n"
        if complete { sse += "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n" }
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/messages",
            data: Data(sse.utf8),
            statusCode: 200
        )
        let client = AnthropicClient(baseURL: baseURL, apiToken: "token", session: session)
        var finished = false
        do {
            let stream = try await client.chatCompletionEventStream(
                messages: [],
                model: "test",
                tools: nil
            )
            for try await event in stream {
                if case .finished = event { finished = true }
            }
            #expect(complete)
        } catch let error as StreamCompletionError {
            guard case .interrupted = error else { Issue.record("Wrong failure"); return }
            #expect(!complete)
        }
        #expect(finished == complete)
    }

    @Test(arguments: [false, true], [false, true])
    func conflictingToolResultsAreRejectedAfterRepair(
        duplicate: Bool,
        interrupted: Bool
    ) async throws {
        let base = "https://history-\(UUID().uuidString).test/v1"
        let url = "\(base)/messages"
        FakeURLProtocol.stubResponse(
            for: url, data: Data(Self.finishedStream.utf8), statusCode: 200
        )
        let calls = ["first", "second"].map {
            ToolCall(id: $0, type: "function", function: .init(name: "read_core", arguments: "{}"))
        }
        let messages = [
            ChatMessage(role: "assistant", content: nil, toolCalls: calls),
            ChatMessage(role: "tool", content: "One", toolCallID: "first"),
            ChatMessage(role: "tool", content: "Two", toolCallID: "second"),
        ] +
            (duplicate ? [ChatMessage(
                role: "tool",
                content: "Conflicting output",
                toolCallID: "first"
            )] : [])
            + (interrupted ? [
                ChatMessage(role: "tool", content: "One", toolCallID: "first"),
                ChatMessage(
                    role: "tool",
                    content: ToolResult.interruptedContent,
                    toolCallID: "first"
                ),
            ] : [])
        let client = AnthropicClient(
            baseURL: base,
            apiToken: "token",
            session: FakeURLProtocol.fakeSession()
        )
        do {
            let stream = try await client.chatCompletionEventStream(
                messages: MessagePipeline.repairSequence(messages),
                model: "test",
                tools: nil
            )
            for try await _ in stream {}
            #expect(!duplicate)
            #expect(FakeURLProtocol.lastRequest(for: url) != nil)
        } catch let error as ToolHistoryError {
            #expect(duplicate)
            #expect(FakeURLProtocol.lastRequest(for: url) == nil)
            #expect(RoutingFailure(from: error) == .notTheModelsFault)
            let card = ConnectionError(from: error)
            #expect(card.title == Localized.Errors.Chat.invalidHistoryTitle)
            #expect(card.suggestion == Localized.Errors.Chat.invalidHistoryBody)
            #expect(card.recovery == nil)
        }
    }

    @Test(arguments: [false, true])
    @MainActor func persistedInterruptedHistoryCanBeSentWithoutRewritingIt(
        realFirst: Bool
    ) async throws {
        let store = try ModelContainer(
            for: Schema(SchemaV12.models, version: SchemaV12.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let placeholder = ChatMessage(
            role: "tool",
            content: ToolResult.interruptedContent,
            toolCallID: "options"
        )
        let actual = ChatMessage(role: "tool", content: "Dismissed", toolCallID: "options")
        let duplicates = realFirst ? [actual, placeholder] : [placeholder, actual]
        let history = [
            ChatMessage(role: "user", content: "Help me choose"),
            ChatMessage(role: "assistant", content: "Choose an option", toolCalls: [
                ToolCall(
                    id: "options",
                    type: "function",
                    function: .init(name: "present_options", arguments: "{}")
                ),
            ]),
        ] + duplicates + [ChatMessage(role: "user", content: "Something else")]
        for (index, message) in history.enumerated() {
            let row = Message.from(message)
            row.timestamp = Date(timeIntervalSince1970: Double(index))
            store.mainContext.insert(row)
        }
        try store.mainContext.save()
        let context = ModelContext(store)
        let descriptor = FetchDescriptor<Message>(sortBy: [SortDescriptor(\.timestamp)])
        let loaded = try context.fetch(descriptor).map { $0.toChatMessage() }
        let repaired = MessagePipeline.repairSequence(loaded)
        let base = "https://repaired-\(UUID().uuidString).test/v1"
        let url = "\(base)/messages"
        FakeURLProtocol.stubResponse(
            for: url,
            data: Data(Self.finishedStream.utf8),
            statusCode: 200
        )
        let client = AnthropicClient(
            baseURL: base,
            apiToken: "token",
            session: FakeURLProtocol.fakeSession()
        )
        let stream = try await client.chatCompletionEventStream(
            messages: repaired,
            model: "test",
            tools: nil
        )
        for try await _ in stream {}
        let data = try #require(FakeURLProtocol.lastRequestBody(for: url))
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let results = messages.flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "tool_result" }
        #expect(results.count == 1)
        #expect(results.first?["tool_use_id"] as? String == "options")
        #expect(results.first?["content"] as? String == "Dismissed")
        let unchanged = try ModelContext(store).fetch(descriptor).map { $0.toChatMessage() }
        #expect(unchanged.map(\.localID) == loaded.map(\.localID))
        #expect(unchanged.map(\.content) == loaded.map(\.content))
    }

    // MARK: - validateAPIKey

    @Test(arguments: [401, 403])
    func validateAPIKeyThrowsOnAuthFailure(statusCode: Int) async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "\(baseURL)/messages"
        FakeURLProtocol.stubResponse(for: url, data: Data(), statusCode: statusCode)

        let client = AnthropicClient(baseURL: baseURL, apiToken: "bad-token", session: session)

        do {
            try await client.validateAPIKey(model: "claude-sonnet-4-6")
            Issue.record("Expected httpError(\(statusCode)) to be thrown")
        } catch let error as OpenAICompatibleClientError {
            guard case .httpError(statusCode, _) = error else {
                Issue.record("Expected httpError(\(statusCode)), got \(error)")
                return
            }
        }
    }

    @Test(arguments: [400, 404, 429, 500])
    func validateAPIKeyIgnoresNonAuthErrors(statusCode: Int) async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/messages",
            data: Data(),
            statusCode: statusCode
        )

        let client = AnthropicClient(baseURL: baseURL, apiToken: "token", session: session)
        try await client.validateAPIKey(model: "claude-sonnet-4-6")
    }

    @Test func validateAPIKeySendsMinimalPing() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "\(baseURL)/messages"
        FakeURLProtocol.stubResponse(for: url, data: Data(), statusCode: 200)

        let client = AnthropicClient(baseURL: baseURL, apiToken: "token", session: session)
        try await client.validateAPIKey(model: "claude-sonnet-4-6")

        let data = try #require(FakeURLProtocol.lastRequestBody(for: url))
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(body["model"] as? String == "claude-sonnet-4-6")
        #expect(body["max_tokens"] as? Int == 1)
        #expect(messages.count == 1)
        #expect(messages.first?["role"] as? String == "user")
    }
}

extension AnthropicClientTests {
    @Test func factoryUsesAnthropicAdapter() {
        #expect(LLMClientFactory.client(baseURL: baseURL, apiToken: "token") is AnthropicClient)
    }

    @Test(arguments: [false, true])
    func hostLoadsImagesAndPreservesCacheControl(unreadable: Bool) async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "\(baseURL)/messages"
        FakeURLProtocol.stubResponse(
            for: url,
            data: Data(Self.finishedStream.utf8),
            statusCode: 200
        )
        let store = StubAttachmentStore(data: unreadable ? nil : Data([1, 2, 3]))
        let attachment = MessageAttachment(
            id: UUID(),
            kind: .image,
            mimeType: "image/png",
            byteCount: 3
        )
        let client = AnthropicClient(
            baseURL: baseURL,
            apiToken: "token",
            session: session,
            attachmentStore: store
        )
        let stream = try await client.chatCompletionEventStream(messages: [
            ChatMessage(role: "system", content: "Be brief."),
            ChatMessage(role: "user", content: "hello", attachments: [attachment]),
        ], model: "test", tools: nil, cacheKey: "ignored")
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        #expect(events == [.finished(.stop)])
        let data = try #require(FakeURLProtocol.lastRequestBody(for: url))
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["cache_control"] as? [String: String] == ["type": "ephemeral"])
        #expect(body["max_tokens"] as? Int == 8192)
        #expect(body["system"] as? String == "Be brief.")
        #expect(body["prompt_cache_key"] == nil)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(content.last?["text"] as? String == "hello")
        #expect(content.count == (unreadable ? 1 : 2))
        if !unreadable {
            let source = try #require(content[0]["source"] as? [String: String])
            #expect(source == ["type": "base64", "media_type": "image/png", "data": "AQID"])
        }
    }

    @Test func textAndToolsReachChatLoop() async throws {
        let session = FakeURLProtocol.fakeSession()
        let sse = """
        event: content_block_delta
        data: {"index":0,"delta":{"type":"text_delta","text":"hello"}}

        event: content_block_start
        data: {"index":1,"content_block":{"type":"tool_use","id":"c","name":"weather"}}

        event: content_block_delta
        data: {"index":1,"delta":{"type":"input_json_delta","partial_json":"{}"}}

        event: content_block_stop
        data: {"index":1}

        event: message_delta
        data: {"delta":{"stop_reason":"tool_use"}}

        event: message_stop
        data: {}

        """
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/messages",
            data: Data(sse.utf8),
            statusCode: 200
        )
        let client = AnthropicClient(baseURL: baseURL, apiToken: "token", session: session)
        let stream = try await client.chatCompletionEventStream(messages: [], model: "test")
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        #expect(events == [
            .contentDelta("hello"),
            .toolCall(.init(
                id: "c",
                type: "function",
                function: .init(name: "weather", arguments: "{}")
            )),
            .finished(.toolCalls),
        ])
    }

    @Test(arguments: ["max_tokens", "refusal"])
    func sdkFailuresRetainChatErrorMeaning(reason: String) async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/messages",
            data: Data("event: message_delta\ndata: {\"delta\":{\"stop_reason\":\"\(reason)\"}}\n\n"
                .utf8),
            statusCode: 200
        )
        let client = AnthropicClient(baseURL: baseURL, apiToken: "token", session: session)
        do {
            let stream = try await client.chatCompletionEventStream(messages: [], model: "test")
            for try await _ in stream {}
            Issue.record("Expected completion failure")
        } catch let error as StreamCompletionError {
            if reason == "max_tokens" {
                guard case .outputLimit = error
                else { Issue.record("Expected output limit"); return }
            } else {
                guard case .policyStop = error else { Issue.record("Expected policy stop"); return }
            }
        }
    }

    private static let finishedStream = "event: message_delta\ndata: {\"delta\":{\"stop_reason\":\"end_turn\"}}\n\nevent: message_stop\ndata: {}\n\n"

    private final class StubAttachmentStore: ChatAttachmentStoring, @unchecked Sendable {
        let data: Data?
        init(data: Data?) {
            self.data = data
        }

        func save(imageData: Data, id: UUID) throws -> MessageAttachment {
            MessageAttachment(
                id: id,
                kind: .image,
                mimeType: "image/png",
                byteCount: imageData.count
            )
        }

        func load(id _: UUID) -> Data? {
            data
        }

        func loadThumbnail(id _: UUID) -> Data? {
            data
        }

        func fileURL(for _: UUID) -> URL? {
            nil
        }

        func delete(id _: UUID) {}
        func deleteAll(_: [MessageAttachment]) {}
    }
}
