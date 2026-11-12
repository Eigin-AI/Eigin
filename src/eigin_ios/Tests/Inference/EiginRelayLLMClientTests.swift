@testable import Eigin
import Foundation
import Testing

/// Exercises SDK relay failover through the app wallet and URLSession adapters.
@Suite("EiginRelayLLMClient", .serialized)
struct EiginRelayLLMClientTests {
    /// A minimal valid SSE body: one content delta then a stop.
    private let successSSE = Data(
        [
            #"data: {"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}"#,
            "",
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "",
        ]
        .joined(separator: "\n")
        .utf8
    )

    private func makeManager(_ wallets: [(token: String, credits: Int)])
        -> DefaultCreditWalletManager
    {
        let manager = DefaultCreditWalletManager(
            relayClient: FakeRelayClient(),
            keychain: FakeKeychainService()
        )
        for wallet in wallets {
            manager.add(CreditWallet(
                token: wallet.token,
                credits: wallet.credits,
                status: .active,
                productID: nil,
                updatedAt: Date(timeIntervalSince1970: 0)
            ))
        }
        return manager
    }

    private func makeClient(
        host: String,
        manager: DefaultCreditWalletManager
    ) -> EiginRelayLLMClient {
        EiginRelayLLMClient(
            walletManager: manager,
            baseURL: URL(string: host)!,
            eiginKey: "relay-key",
            session: FakeURLProtocol.fakeSession()
        )
    }

    @Test func failsOverToNextWalletWhenRelayReturns402() async throws {
        let host = "https://failover.test"
        let url = "\(host)/v1/chat/completions"
        // First wallet is rejected (insufficient credits); the second succeeds.
        FakeURLProtocol.enqueueResponse(for: url, data: Data(), statusCode: 402)
        FakeURLProtocol.enqueueResponse(for: url, data: successSSE, statusCode: 200)

        let manager = makeManager([("a", 100), ("b", 100)])
        let client = makeClient(host: host, manager: manager)

        let stream = try await client.chatCompletionEventStream(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "test-model",
            tools: nil
        )
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        // The exhausted first wallet was evicted; the second served the request.
        #expect(manager.wallets().map(\.token) == ["b"])
        #expect(events.contains(.contentDelta("hi")))
    }

    @Test func forwardsEffortThroughCreditWrapper() async throws {
        let host = "https://relay-reasoning.test"
        let url = "\(host)/v1/chat/completions"
        FakeURLProtocol.stubResponse(for: url, data: successSSE, statusCode: 200)
        let client: any LLMClient = makeClient(host: host, manager: makeManager([("token", 100)]))
        let stream = try await client.chatCompletionEventStream(
            messages: [ChatMessage(role: "user", content: "hi")],
            model: "mistral/mistral-medium-2604", tools: nil, cacheKey: nil,
            reasoningEffort: ReasoningEffort.none
        )
        for try await _ in stream {}
        let data = try #require(FakeURLProtocol.lastRequestBody(for: url))
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["reasoning_effort"] as? String == "none")
    }

    @Test func throwsNoCreditsWhenSoleWalletReturns402() async {
        let host = "https://exhausted.test"
        let url = "\(host)/v1/chat/completions"
        FakeURLProtocol.enqueueResponse(for: url, data: Data(), statusCode: 402)

        let manager = makeManager([("only", 100)])
        let client = makeClient(host: host, manager: manager)

        await #expect(throws: CreditsError.noCreditsRemaining) {
            _ = try await client.chatCompletionEventStream(
                messages: [ChatMessage(role: "user", content: "hi")],
                model: "test-model",
                tools: nil
            )
        }
        // The lone wallet was zeroed and evicted.
        #expect(manager.wallets().isEmpty)
    }

    @Test func discoveryUsesSDKWithoutWalletAuthorization() async throws {
        let host = "https://relay-models.test"
        let url = "\(host)/v1/models"
        FakeURLProtocol.stubResponse(
            for: url,
            data: Data(#"{"data":[{"id":"zebra"},{"id":"alpha"}]}"#.utf8),
            statusCode: 200
        )
        let models = try await makeClient(host: host, manager: makeManager([])).fetchModels()
        #expect(models == ["alpha", "zebra"])
        let request = try #require(FakeURLProtocol.lastRequest(for: url))
        #expect(request.value(forHTTPHeaderField: "X-Eigin-Key") == "relay-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func transportErrorsKeepURLSessionCategoryAndWallet() async throws {
        let host = "https://relay-offline.test"
        FakeURLProtocol.stubError(
            for: "\(host)/v1/chat/completions",
            error: URLError(.notConnectedToInternet)
        )
        let manager = makeManager([("a", 100)])
        do {
            _ = try await makeClient(host: host, manager: manager).chatCompletionStream(
                messages: [],
                model: "test"
            )
            Issue.record("Expected offline error")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        }
        #expect(manager.wallets().map(\.token) == ["a"])
    }
}
