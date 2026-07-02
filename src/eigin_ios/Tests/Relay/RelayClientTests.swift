@testable import Eigin
import Foundation
import Testing

@Suite("RelayClient", .serialized)
struct RelayClientTests {
    private let base = URL(string: "https://relay.test")!

    private func makeClient() -> DefaultRelayClient {
        DefaultRelayClient(baseURL: base, apiKey: "key", session: FakeURLProtocol.fakeSession())
    }

    @Test func redeemDecodesWallet() async throws {
        FakeURLProtocol.stubResponse(
            for: "https://relay.test/v1/credits/redeem",
            data: Data(#"{"token":"eict_abc","credits":500,"status":"active"}"#.utf8),
            statusCode: 200
        )
        let response = try await makeClient().redeem(type: "apple_iap", proof: "jws")
        #expect(response.token == "eict_abc")
        #expect(response.credits == 500)
        #expect(response.status == .active)
    }

    @Test func productsDecodesCatalog() async throws {
        FakeURLProtocol.stubResponse(
            for: "https://relay.test/v1/credits/products",
            data: Data(#"{"products":[{"id":"eigin.credits.v1.apple.500","credits":500}]}"#.utf8),
            statusCode: 200
        )
        let products = try await makeClient().products()
        #expect(products.count == 1)
        #expect(products.first?.id == "eigin.credits.v1.apple.500")
        #expect(products.first?.credits == 500)
    }

    @Test func balanceDecodes() async throws {
        FakeURLProtocol.stubResponse(
            for: "https://relay.test/v1/credits/balance",
            data: Data(#"{"credits":342,"status":"refunded"}"#.utf8),
            statusCode: 200
        )
        let response = try await makeClient().balance(token: "eict_abc")
        #expect(response.credits == 342)
        #expect(response.status == .refunded)
    }

    @Test func modelsParsesSortedIDs() async throws {
        FakeURLProtocol.stubResponse(
            for: "https://relay.test/v1/models",
            data: Data(#"{"object":"list","data":[{"id":"zebra"},{"id":"alpha"}]}"#.utf8),
            statusCode: 200
        )
        let models = try await makeClient().models()
        #expect(models == ["alpha", "zebra"])
    }

    @Test func searchReturnsRawBody() async throws {
        FakeURLProtocol.stubResponse(
            for: "https://relay.test/v1/search?q=swift",
            data: Data(#"{"results":[]}"#.utf8),
            statusCode: 200
        )
        let body = try await makeClient().search(query: "swift")
        #expect(body == #"{"results":[]}"#)
    }

    @Test func searchIncludesRegionAndFocusWhenProvided() async throws {
        FakeURLProtocol.stubResponse(
            for: "https://relay.test/v1/search?q=pandekager&region=DK&focus=recipes",
            data: Data(#"{"results":[]}"#.utf8),
            statusCode: 200
        )
        let body = try await makeClient().search(
            query: "pandekager",
            region: "DK",
            focus: "recipes"
        )
        #expect(body == #"{"results":[]}"#)
    }

    @Test func redeemMapsProofFailure() async {
        FakeURLProtocol.stubResponse(
            for: "https://relay.test/v1/credits/redeem",
            data: Data(#"{"error":{"message":"bad","type":"unprocessable"}}"#.utf8),
            statusCode: 422
        )
        await #expect(throws: RelayClientError.proofVerificationFailed("bad")) {
            _ = try await makeClient().redeem(type: "apple_iap", proof: "x")
        }
    }

    @Test func errorMappingPrefersBodyType() {
        let body = Data(#"{"error":{"message":"no funds","type":"insufficient_credits"}}"#.utf8)
        #expect(RelayClientError.from(status: 402, body: body) == .insufficientCredits("no funds"))
    }

    @Test func errorMappingFallsBackToStatus() {
        let body = Data("not json".utf8)
        #expect(RelayClientError.from(status: 401, body: body) == .authentication(nil))
        #expect(RelayClientError.from(status: 400, body: body) == .invalidRequest(nil))
        #expect(RelayClientError.from(status: 422, body: body) == .proofVerificationFailed(nil))
        #expect(RelayClientError.from(status: 429, body: body) == .rateLimit(nil))
        #expect(RelayClientError.from(status: 502, body: body) == .upstream(nil))
        #expect(RelayClientError.from(status: 500, body: body) == .server(500, nil))
    }

    @Test func notConfiguredWhenMissingKey() async {
        let client = DefaultRelayClient(
            baseURL: base,
            apiKey: nil,
            session: FakeURLProtocol.fakeSession()
        )
        await #expect(throws: RelayClientError.notConfigured) {
            _ = try await client.balance(token: "t")
        }
    }
}
