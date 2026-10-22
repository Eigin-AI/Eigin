@testable import Eigin
import Foundation
import Testing

@Suite("AnthropicClient", .serialized)
struct AnthropicClientTests {
    private let baseURL = "https://api.anthropic.com/v1"

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
