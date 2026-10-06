@testable import Eigin
import Foundation
import Testing

@Suite("ResponsesAPIClient", .serialized)
struct ResponsesAPIClientTests {
    private let baseURL = "https://api.openai.com/v1"

    // MARK: - fetchModels

    @Test func fetchModelsParsesSIWCShapeAndFiltersVisibility() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "\(baseURL)/models"
        let body = """
        {"models":[
            {"slug":"gpt-6.1-sol","display_name":"GPT-6.1 Sol","visibility":"list"},
            {"slug":"gpt-6.1-luna","display_name":"GPT-6.1 Luna","visibility":"list"},
            {"slug":"gpt-6.1-secret","display_name":"Internal","visibility":"internal"}
        ]}
        """
        FakeURLProtocol.stubResponse(for: url, data: Data(body.utf8), statusCode: 200)

        let client = ResponsesAPIClient(apiToken: "token", session: session)
        let models = try await client.fetchModels()

        #expect(models == ["gpt-6.1-sol", "gpt-6.1-luna"])
    }

    @Test func fetchModelsAcceptsStandardShape() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/models",
            data: Data(#"{"data":[{"id":"b-model"},{"id":"a-model"}]}"#.utf8),
            statusCode: 200
        )

        let client = ResponsesAPIClient(apiToken: "token", session: session)
        let models = try await client.fetchModels()

        #expect(models == ["b-model", "a-model"])
    }

    @Test func fetchModelsMapsSubscriptionError() async throws {
        let session = FakeURLProtocol.fakeSession()
        let body = #"{"detail":{"code":"subscription_sharing_user_not_eligible","message":"not eligible"}}"#
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/models",
            data: Data(body.utf8),
            statusCode: 403
        )

        let client = ResponsesAPIClient(apiToken: "token", session: session)

        do {
            _ = try await client.fetchModels()
            Issue.record("Expected planNotEligible")
        } catch let error as ResponsesAPIError {
            #expect(error == .planNotEligible)
        }
    }

    // MARK: - Request mapping

    private func sentBody(for url: String) throws -> [String: Any] {
        let data = try #require(FakeURLProtocol.lastRequestBody(for: url))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func requestMapsSystemToInstructionsAndOmitsForbiddenFields() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "\(baseURL)/responses"
        FakeURLProtocol.stubResponse(for: url, data: Data(Self.emptyStream.utf8), statusCode: 200)

        let client = ResponsesAPIClient(apiToken: "token", session: session)
        _ = try await client.chatCompletionEventStream(messages: [
            ChatMessage(role: "system", content: "Be brief."),
            ChatMessage(role: "user", content: "hello"),
        ], model: "gpt-6.1-sol")

        let body = try sentBody(for: url)
        #expect(body["instructions"] as? String == "Be brief.")
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] as? Bool == true)
        #expect(body["model"] as? String == "gpt-6.1-sol")
        for forbidden in ["temperature", "top_p", "max_output_tokens", "previous_response_id"] {
            #expect(body[forbidden] == nil, "request must not send \(forbidden)")
        }
        let input = try #require(body["input"] as? [[String: Any]])
        let first = try #require(input.first)
        #expect(first["type"] as? String == "message")
        #expect(first["role"] as? String == "user")
        let content = try #require(first["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "input_text")
        #expect(content.first?["text"] as? String == "hello")
    }

    @Test func requestMapsToolCallsAndResults() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "\(baseURL)/responses"
        FakeURLProtocol.stubResponse(for: url, data: Data(Self.emptyStream.utf8), statusCode: 200)

        var assistant = ChatMessage(role: "assistant", content: "")
        assistant.toolCalls = [ToolCall(
            id: "call_1",
            type: "function",
            function: .init(name: "get_weather", arguments: #"{"city":"Oslo"}"#)
        )]
        let client = ResponsesAPIClient(apiToken: "token", session: session)
        _ = try await client.chatCompletionEventStream(messages: [
            ChatMessage(role: "user", content: "weather?"),
            assistant,
            ChatMessage(role: "tool", content: "sunny", toolCallID: "call_1"),
        ], model: "gpt-6.1-sol", tools: [ToolDefinition(
            name: "get_weather",
            description: "Gets weather",
            parameters: JSONSchema(
                type: "object",
                properties: ["city": .init(type: "string", description: "City")],
                required: ["city"]
            )
        )])

        let body = try sentBody(for: url)
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == 3)

        let call = input[1]
        #expect(call["type"] as? String == "function_call")
        #expect(call["call_id"] as? String == "call_1")
        #expect(call["name"] as? String == "get_weather")

        let output = input[2]
        #expect(output["type"] as? String == "function_call_output")
        #expect(output["call_id"] as? String == "call_1")
        #expect(output["output"] as? String == "sunny")

        let tools = try #require(body["tools"] as? [[String: Any]])
        let tool = try #require(tools.first)
        // Responses tool shape is flat — no "function" wrapper.
        #expect(tool["type"] as? String == "function")
        #expect(tool["name"] as? String == "get_weather")
        #expect(tool["parameters"] != nil)
    }

    @Test func builderMapsImageAttachments() throws {
        let store = StubAttachmentStore(data: Data([0xFF, 0xD8, 0xFF]))
        let attachment = MessageAttachment(
            id: UUID(), kind: .image, mimeType: "image/jpeg", byteCount: 3
        )
        let body = ResponsesRequestBuilder.body(
            messages: [ChatMessage(
                role: "user",
                content: "what's this?",
                attachments: [attachment]
            )],
            model: "gpt-6.1-sol",
            attachmentStore: store
        )

        let data = try JSONEncoder().encode(body)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try #require(json["input"] as? [[String: Any]])
        let content = try #require(input.first?["content"] as? [[String: Any]])
        let image = try #require(content.last)
        #expect(image["type"] as? String == "input_image")
        let dataURL = try #require(image["image_url"] as? String)
        #expect(dataURL.hasPrefix("data:image/jpeg;base64,"))
    }

    // MARK: - SSE mapping

    @Test func streamYieldsDeltasAndStop() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/responses",
            data: Data(Self.textStream.utf8),
            statusCode: 200
        )

        let client = ResponsesAPIClient(apiToken: "token", session: session)
        let events = try await collect(
            client.chatCompletionEventStream(messages: [
                ChatMessage(role: "user", content: "hi"),
            ], model: "gpt-6.1-sol")
        )

        #expect(events == [.contentDelta("Hel"), .contentDelta("lo"), .finished(.stop)])
    }

    @Test func streamEmitsToolCallsWithToolCallsFinish() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/responses",
            data: Data(Self.toolStream.utf8),
            statusCode: 200
        )

        let client = ResponsesAPIClient(apiToken: "token", session: session)
        let events = try await collect(
            client.chatCompletionEventStream(messages: [
                ChatMessage(role: "user", content: "weather?"),
            ], model: "gpt-6.1-sol")
        )

        #expect(events.count == 2)
        #expect(events[0] == .toolCall(ToolCall(
            id: "call_9",
            type: "function",
            function: .init(name: "get_weather", arguments: #"{"city":"Oslo"}"#)
        )))
        #expect(events[1] == .finished(.toolCalls))
    }

    @Test func streamFailedThrowsMappedError() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/responses",
            data: Data(Self.failedStream.utf8),
            statusCode: 200
        )

        let client = ResponsesAPIClient(apiToken: "token", session: session)

        do {
            _ = try await collect(
                client.chatCompletionEventStream(messages: [
                    ChatMessage(role: "user", content: "hi"),
                ], model: "gpt-6.1-sol")
            )
            Issue.record("Expected usageLimitExceeded")
        } catch let error as ResponsesAPIError {
            #expect(error == .usageLimitExceeded)
        }
    }

    @Test func streamWithoutCompletionThrowsInterrupted() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/responses",
            data: Data("data: {\"type\":\"response.output_text.delta\",\"delta\":\"cut\"}\n\n"
                .utf8),
            statusCode: 200
        )

        let client = ResponsesAPIClient(apiToken: "token", session: session)

        do {
            _ = try await collect(
                client.chatCompletionEventStream(messages: [
                    ChatMessage(role: "user", content: "hi"),
                ], model: "gpt-6.1-sol")
            )
            Issue.record("Expected interruptedStream")
        } catch let error as ResponsesAPIError {
            #expect(error == .interruptedStream)
        }
    }

    // MARK: - Factory

    @Test func factoryRoutesChatGPTSentinelToResponsesClient() {
        let client = LLMClientFactory.client(baseURL: "openai-chatgpt://", apiToken: "token")
        #expect(client is ResponsesAPIClient)
    }

    // MARK: - Fixtures

    private static let emptyStream =
        """
        data: {"type":"response.created"}

        data: {"type":"response.completed"}

        """

    private static let textStream =
        """
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hel"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"lo"}

        data: {"type":"response.completed"}

        """

    private static let toolStream =
        """
        data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_9","name":"get_weather"}}

        data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_9","name":"get_weather","arguments":"{\\"city\\":\\"Oslo\\"}"}}

        data: {"type":"response.completed"}

        """

    private static let failedStream =
        """
        data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"limit"}}}

        """

    private func collect(
        _ stream: AsyncThrowingStream<ChatStreamEvent, Error>
    ) async throws -> [ChatStreamEvent] {
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    /// Minimal attachment store returning fixed bytes, mirroring
    /// ``ImageWireConversionTests``' stub.
    private final class StubAttachmentStore: ChatAttachmentStoring, @unchecked Sendable {
        let fixedData: Data

        init(data: Data) {
            fixedData = data
        }

        func save(imageData: Data, id: UUID) throws -> MessageAttachment {
            MessageAttachment(
                id: id,
                kind: .image,
                mimeType: "image/jpeg",
                byteCount: fixedData.count
            )
        }

        func load(id _: UUID) -> Data? {
            fixedData
        }

        func loadThumbnail(id _: UUID) -> Data? {
            fixedData
        }

        func fileURL(for _: UUID) -> URL? {
            nil
        }

        func delete(id _: UUID) {}
        func deleteAll(_: [MessageAttachment]) {}
    }
}
