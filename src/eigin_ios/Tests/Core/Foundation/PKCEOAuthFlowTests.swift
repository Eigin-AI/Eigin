@testable import Eigin
import Foundation
import Testing

@Suite("PKCEOAuthFlow")
struct PKCEOAuthFlowTests {
    private func makeConfig(
        tokenEndpoint: String,
        extraTokenParams: [String: String] = [:]
    ) -> PKCEOAuthConfig {
        PKCEOAuthConfig(
            authorizationEndpoint: URL(string: "https://example.com/auth")!,
            tokenEndpoint: URL(string: tokenEndpoint)!,
            clientID: "client-123",
            extraTokenParams: extraTokenParams
        )
    }

    @Test func refreshDecodesTokenResponse() async throws {
        let session = FakeURLProtocol.fakeSession()
        let endpoint = "https://example.com/refresh-ok"
        FakeURLProtocol.stubResponse(
            for: endpoint,
            data: Data(
                #"{"access_token":"new-token","token_type":"Bearer","expires_in":1800,"refresh_token":"new-refresh"}"#
                    .utf8
            ),
            statusCode: 200
        )

        let response = try await PKCEOAuthFlow.refresh(
            refreshToken: "old-refresh",
            config: makeConfig(tokenEndpoint: endpoint),
            urlSession: session
        )

        #expect(response.accessToken == "new-token")
        #expect(response.refreshToken == "new-refresh")
        #expect(response.expiresIn == 1800)
    }

    @Test func refreshThrowsOnServerError() async throws {
        let session = FakeURLProtocol.fakeSession()
        let endpoint = "https://example.com/refresh-error"
        FakeURLProtocol.stubResponse(for: endpoint, data: Data(), statusCode: 400)

        await #expect(throws: PKCEOAuthFlow.FlowError.self) {
            _ = try await PKCEOAuthFlow.refresh(
                refreshToken: "old-refresh",
                config: self.makeConfig(tokenEndpoint: endpoint),
                urlSession: session
            )
        }
    }

    @Test func refreshIncludesExtraTokenParams() async throws {
        let session = FakeURLProtocol.fakeSession()
        let endpoint = "https://example.com/refresh-extra"
        FakeURLProtocol.stubResponse(
            for: endpoint,
            data: Data(#"{"access_token":"tok","token_type":"Bearer"}"#.utf8),
            statusCode: 200
        )

        _ = try await PKCEOAuthFlow.refresh(
            refreshToken: "old-refresh",
            config: makeConfig(
                tokenEndpoint: endpoint,
                extraTokenParams: ["resource": "https://mcp.example.com"]
            ),
            urlSession: session
        )

        let body = try #require(FakeURLProtocol.lastRequestBody(for: endpoint))
        let bodyString = String(data: body, encoding: .utf8)
        #expect(bodyString?.contains("resource=") == true)
    }
}
