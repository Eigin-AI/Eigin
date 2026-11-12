@testable import Eigin
import Foundation
import Testing

@Suite("ResponsesAPIClient", .serialized)
struct ResponsesAPIClientTests {
    private let baseURL = "https://api.openai.com/v1"

    @Test(arguments: ["response.incomplete", "response.refusal.done"])
    func incompleteAndRefusedResponsesAreNotRecoverable(type: String) async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/responses",
            data: Data("data: {\"type\":\"\(type)\"}\n\n".utf8),
            statusCode: 200
        )
        let client = ResponsesAPIClient(apiToken: "token", session: session)
        do {
            let stream = try await client.chatCompletionEventStream(messages: [], model: "test")
            for try await _ in stream {}
            Issue.record("Expected nonrecoverable completion failure")
        } catch let error as StreamCompletionError {
            if type == "response.incomplete" {
                guard case .outputLimit = error
                else { Issue.record("Expected output limit"); return }
            } else {
                guard case .policyStop = error else { Issue.record("Expected policy stop"); return }
            }
        }
    }

    @Test(arguments: ["max_output_tokens", "content_filter"])
    func incompleteReasonSelectsAppropriateCard(reason: String) async throws {
        let session = FakeURLProtocol.fakeSession()
        let payload = """
        data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"\(
            reason
        )"}}}


        """
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/responses", data: Data(payload.utf8), statusCode: 200
        )
        let client = ResponsesAPIClient(apiToken: "token", session: session)
        do {
            let stream = try await client.chatCompletionEventStream(messages: [], model: "test")
            for try await _ in stream {}
            Issue.record("Expected a nonrecoverable incomplete response")
        } catch let error as StreamCompletionError {
            let card = ConnectionError(from: error)
            if reason == "content_filter" {
                guard case .policyStop = error else { Issue.record("Expected policy stop"); return }
                #expect(card.title == Localized.Errors.Chat.policyStopTitle)
            } else {
                guard case .outputLimit = error
                else { Issue.record("Expected output limit"); return }
                #expect(card.title == Localized.Errors.Chat.outputLimitTitle)
            }
        }
    }

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

    @Test(arguments: [
        "subscription_sharing_user_not_eligible",
        "subscription_sharing_usage_limit_exceeded",
        "subscription_sharing_invalid_user",
        "subscription_sharing_usage_unavailable",
        "subscription_sharing_unsupported_capability",
    ])
    func subscriptionFailuresPreserveCardsAndRetryPolicy(code: String) async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/responses", data: Data("{\"code\":\"\(code)\"}".utf8), statusCode: 400
        )
        let expected: ResponsesAPIError = switch code {
        case "subscription_sharing_user_not_eligible": .planNotEligible
        case "subscription_sharing_usage_limit_exceeded": .usageLimitExceeded
        case "subscription_sharing_invalid_user": .invalidUser
        case "subscription_sharing_usage_unavailable": .usageUnavailable
        default: .unsupportedCapability(param: nil)
        }
        do {
            _ = try await ResponsesAPIClient(apiToken: "token", session: session)
                .chatCompletionEventStream(messages: [], model: "test")
            Issue.record("Expected subscription failure before streaming")
        } catch let error as ResponsesAPIError {
            #expect(error == expected)
            #expect(error.isRetryable == (code == "subscription_sharing_usage_unavailable"))
            #expect(ConnectionError(from: error).title == ConnectionError(from: expected).title)
        }
    }

    // MARK: - validateAPIKey

    @Test(arguments: [401, 403])
    func validateAPIKeyThrowsOnAuthFailure(statusCode: Int) async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/responses",
            data: Data(),
            statusCode: statusCode
        )

        let client = ResponsesAPIClient(apiToken: "bad-token", session: session)

        do {
            try await client.validateAPIKey(model: "gpt-6.1")
            Issue.record("Expected invalidUser to be thrown")
        } catch let error as ResponsesAPIError {
            #expect(error == .invalidUser)
        }
    }

    @Test(arguments: [400, 404, 429, 500])
    func validateAPIKeyIgnoresNonAuthErrors(statusCode: Int) async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(baseURL)/responses",
            data: Data(),
            statusCode: statusCode
        )

        let client = ResponsesAPIClient(apiToken: "token", session: session)
        try await client.validateAPIKey(model: "gpt-6.1")
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

    @Test(arguments: [false, true])
    func hostLoadsImageAttachments(unreadable: Bool) async throws {
        let store = StubAttachmentStore(data: unreadable ? nil : Data([0xFF, 0xD8, 0xFF]))
        let attachment = MessageAttachment(
            id: UUID(),
            kind: .image,
            mimeType: "image/jpeg",
            byteCount: 3
        )
        let session = FakeURLProtocol.fakeSession()
        let url = "\(baseURL)/responses"
        FakeURLProtocol.stubResponse(for: url, data: Data(Self.emptyStream.utf8), statusCode: 200)
        let client = ResponsesAPIClient(apiToken: "token", session: session, attachmentStore: store)
        _ = try await collect(client.chatCompletionEventStream(messages: [ChatMessage(
            role: "user", content: "", attachments: [attachment]
        )], model: "test"))
        let body = try sentBody(for: url)
        let input = try #require(body["input"] as? [[String: Any]])
        let content = try #require(input.first?["content"] as? [[String: Any]])
        #expect(content.count == 1)
        if unreadable {
            #expect(content[0]["type"] as? String == "input_text")
            #expect(content[0]["text"] as? String == "")
        } else {
            #expect(content[0]["type"] as? String == "input_image")
            #expect(content[0]["image_url"] as? String == "data:image/jpeg;base64,/9j/")
        }
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
        let fixedData: Data?

        init(data: Data?) {
            fixedData = data
        }

        func save(imageData: Data, id: UUID) throws -> MessageAttachment {
            MessageAttachment(
                id: id,
                kind: .image,
                mimeType: "image/jpeg",
                byteCount: fixedData?.count ?? 0
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
