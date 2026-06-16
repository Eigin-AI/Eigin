@testable import Eigin
import Foundation
import Testing

/// Verifies the relay inference client's credit wiring: an HTTP 402 from the relay (wallet below
/// the
/// admit floor) is translated so ``CreditWalletManager/withCredits(_:)`` fails over to the next
/// wallet, and is surfaced as ``CreditsError/noCreditsRemaining`` once none remain.
@Suite("RelayLLMClient", .serialized)
struct RelayLLMClientTests {
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

    private func makeClient(host: String, manager: DefaultCreditWalletManager) -> RelayLLMClient {
        RelayLLMClient(
            walletManager: manager,
            relayClient: FakeRelayClient(),
            baseURL: URL(string: host)!,
            eiginKey: "relay-key",
            session: FakeURLProtocol.fakeSession()
        )
    }

    @Test func failsOverToNextWalletWhenRelayReturns402() async throws {
        let host = "https://failover.test"
        let url = "\(host)/v1/chat/completions"
        // First wallet is rejected (below the admit floor); the second succeeds.
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
}
