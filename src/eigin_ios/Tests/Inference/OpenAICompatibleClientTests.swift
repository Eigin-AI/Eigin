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
