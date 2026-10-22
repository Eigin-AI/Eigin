@testable import Eigin
import Foundation
import Testing

@Suite("OpenAICompatibleClient", .serialized)
struct OpenAICompatibleClientTests {
    private func makeModelsJSON(ids: [String]) -> Data {
        let entries = ids.map { "{\"id\":\"\($0)\"}" }.joined(separator: ",")
        return Data("{\"data\":[\(entries)]}".utf8)
    }

    @Test func fetchModelsParsesSortedIDs() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "https://api.example.com/v1/models"
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeModelsJSON(ids: ["zebra-model", "alpha-model", "mid-model"]),
            statusCode: 200
        )

        let client = OpenAICompatibleClient(
            baseURL: "https://api.example.com/v1",
            apiToken: "test-token",
            session: session
        )
        let models = try await client.fetchModels()

        #expect(models == ["alpha-model", "mid-model", "zebra-model"])
    }

    @Test func fetchModelsThrowsOnHTTP401() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "https://api.example.com/v1/models"
        FakeURLProtocol.stubResponse(for: url, data: Data(), statusCode: 401)

        let client = OpenAICompatibleClient(
            baseURL: "https://api.example.com/v1",
            apiToken: "bad-token",
            session: session
        )

        do {
            _ = try await client.fetchModels()
            Issue.record("Expected OpenAICompatibleClientError to be thrown")
        } catch let error as OpenAICompatibleClientError {
            guard case .httpError(401, _) = error else {
                Issue.record("Expected httpError(401), got \(error)")
                return
            }
        }
    }

    @Test func fetchModelsThrowsOnInvalidURL() async throws {
        let session = FakeURLProtocol.fakeSession()
        let client = OpenAICompatibleClient(
            baseURL: "ht tp://inva lid",
            apiToken: "token",
            session: session
        )

        do {
            _ = try await client.fetchModels()
            Issue.record("Expected OpenAICompatibleClientError to be thrown")
        } catch let error as OpenAICompatibleClientError {
            guard case .invalidURL = error else {
                Issue.record("Expected invalidURL, got \(error)")
                return
            }
        }
    }

    private func sentBody(for url: String) throws -> [String: Any] {
        let data = try #require(FakeURLProtocol.lastRequestBody(for: url))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - validateAPIKey

    @Test(arguments: [401, 403])
    func validateAPIKeyThrowsOnAuthFailure(statusCode: Int) async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "https://api.example.com/v1/chat/completions"
        FakeURLProtocol.stubResponse(for: url, data: Data(), statusCode: statusCode)

        let client = OpenAICompatibleClient(
            baseURL: "https://api.example.com/v1",
            apiToken: "bad-token",
            session: session
        )

        do {
            try await client.validateAPIKey(model: "some-model")
            Issue.record("Expected httpError(\(statusCode)) to be thrown")
        } catch let error as OpenAICompatibleClientError {
            guard case .httpError(statusCode, _) = error else {
                Issue.record("Expected httpError(\(statusCode)), got \(error)")
                return
            }
        }
    }

    /// Non-auth failures pass: the model may not exist or be busy, which says
    /// nothing about the key.
    @Test(arguments: [400, 404, 429, 500])
    func validateAPIKeyIgnoresNonAuthErrors(statusCode: Int) async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "https://api.example.com/v1/chat/completions",
            data: Data(),
            statusCode: statusCode
        )

        let client = OpenAICompatibleClient(
            baseURL: "https://api.example.com/v1",
            apiToken: "token",
            session: session
        )

        try await client.validateAPIKey(model: "some-model")
    }

    @Test func validateAPIKeySendsMinimalPing() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "https://api.example.com/v1/chat/completions"
        FakeURLProtocol.stubResponse(for: url, data: Data(), statusCode: 200)

        let client = OpenAICompatibleClient(
            baseURL: "https://api.example.com/v1",
            apiToken: "token",
            session: session
        )
        try await client.validateAPIKey(model: "some-model")

        let body = try sentBody(for: url)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(body["model"] as? String == "some-model")
        #expect(body["max_tokens"] as? Int == 1)
        #expect(messages.count == 1)
        #expect(messages.first?["role"] as? String == "user")
        #expect(messages.first?["content"] as? String == "hi")
    }

    @Test func includesPromptCacheKeyForOpenAICompatibleProvider() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "https://api.example.com/v1/chat/completions"
        FakeURLProtocol.stubResponse(for: url, data: Data("data: [DONE]\n\n".utf8), statusCode: 200)

        let client = OpenAICompatibleClient(
            baseURL: "https://api.example.com/v1",
            apiToken: "token",
            session: session
        )
        _ = try await client.chatCompletionEventStream(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "gpt-4o",
            tools: nil,
            cacheKey: "chat-123"
        )

        let body = try sentBody(for: url)
        #expect(body["prompt_cache_key"] as? String == "chat-123")
    }

    @Test func omitsPromptCacheKeyForGemini() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        FakeURLProtocol.stubResponse(for: url, data: Data("data: [DONE]\n\n".utf8), statusCode: 200)

        let client = OpenAICompatibleClient(
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            apiToken: "token",
            session: session
        )
        _ = try await client.chatCompletionEventStream(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "gemini-2.0-flash",
            tools: nil,
            cacheKey: "chat-123"
        )

        let body = try sentBody(for: url)
        #expect(body["prompt_cache_key"] == nil)
    }

    @Test func trailingSlashBaseURLHandled() async throws {
        let session = FakeURLProtocol.fakeSession()
        let url = "https://api.example.com/v1/models"
        FakeURLProtocol.stubResponse(
            for: url,
            data: makeModelsJSON(ids: ["model-a"]),
            statusCode: 200
        )

        let client = OpenAICompatibleClient(
            baseURL: "https://api.example.com/v1/",
            apiToken: "token",
            session: session
        )
        let models = try await client.fetchModels()

        #expect(models == ["model-a"])
    }
}
