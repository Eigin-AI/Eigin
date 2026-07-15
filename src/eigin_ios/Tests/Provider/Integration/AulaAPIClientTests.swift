@testable import Eigin
import Foundation
import Testing

/// Pins down the load-bearing assumptions about how we talk to Aula's
/// unofficial API: the session cookies and `csrfp-token` we attach, and the
/// version-bump-on-410 retry. These are the parts most likely to drift, so a
/// change that breaks them should fail here.
@Suite("AulaAPIClient")
struct AulaAPIClientTests {
    private let session = AulaSession(
        accessToken: "tok",
        refreshToken: "ref",
        expiresAt: nil,
        cookies: ["Csrfp-Token": "csrf1", "PHPSESSID": "sess1"],
        apiVersion: 21,
        children: []
    )

    @Test func attachesAccessTokenAsQueryParamOnGet() async throws {
        let http = FakeAulaHTTP { _ in (200, Data("{}".utf8)) }
        let client = AulaAPIClient(http: http)

        _ = try await client.get(method: "profiles.getProfilesByLogin", session: session)

        let request = try #require(http.requests.first)
        let url = try #require(request.url?.absoluteString)
        #expect(url.contains("www.aula.dk/api/v21/"))
        #expect(url.contains("method=profiles.getProfilesByLogin"))
        #expect(url.contains("access_token=tok"))
        // Aula's API rejects a Bearer header — the token only travels as a
        // query param.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        // CSRF rides only on POSTs (mirrors the reference app client).
        #expect(request.value(forHTTPHeaderField: "csrfp-token") == nil)
    }

    @Test func sendsCsrfHeaderOnlyOnPost() async throws {
        let http = FakeAulaHTTP { _ in (200, Data("{}".utf8)) }
        let client = AulaAPIClient(http: http)

        _ = try await client.post(
            method: "calendar.getEventsByProfileIdsAndResourceIds",
            jsonBody: ["instProfileIds": [1]],
            session: session
        )

        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "csrfp-token") == "csrf1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try #require(request.url?.absoluteString).contains("access_token=tok"))
    }

    @Test func omitsAccessTokenParamForCookieOnlySessions() async throws {
        // The web login flow never mints an OAuth code — the browser drives
        // the API with cookies alone, and so must we.
        var cookieOnly = session
        cookieOnly.accessToken = nil
        let http = FakeAulaHTTP { _ in (200, Data("{}".utf8)) }
        let client = AulaAPIClient(http: http)

        _ = try await client.get(method: "profiles.getProfilesByLogin", session: cookieOnly)

        let url = try #require(http.requests.first?.url?.absoluteString)
        #expect(!url.contains("access_token"))
        #expect(url.contains("method=profiles.getProfilesByLogin"))
    }

    @Test func foldsRotatedSetCookieBackIntoTheReturnedSession() async throws {
        // Aula rotates PHPSESSID on every response; the returned session must
        // carry the new value (and keep untouched cookies) so the next call
        // authenticates instead of 401ing on the spent cookie.
        let http = FakeAulaHTTP(
            handler: { _ in (200, Data("{}".utf8)) },
            headers: { _ in
                ["Set-Cookie": "PHPSESSID=rotated; path=/; domain=.aula.dk; secure; HttpOnly"]
            }
        )
        let client = AulaAPIClient(http: http)

        let response = try await client.get(method: "messaging.getThreads", session: session)

        #expect(response.session.cookies["PHPSESSID"] == "rotated")
        // Cookies the response didn't set are preserved.
        #expect(response.session.cookies["Csrfp-Token"] == "csrf1")
    }

    @Test func ignoresNonAulaSetCookies() async throws {
        let http = FakeAulaHTTP(
            handler: { _ in (200, Data("{}".utf8)) },
            headers: { _ in ["Set-Cookie": "tracker=abc; domain=.evil.example; path=/"] }
        )
        let client = AulaAPIClient(http: http)

        let response = try await client.get(method: "messaging.getThreads", session: session)

        #expect(response.session.cookies["tracker"] == nil)
        #expect(response.session.cookies["PHPSESSID"] == "sess1")
    }

    @Test func bumpsApiVersionOn410ThenRetriesAndReportsNewVersion() async throws {
        // 410 on v21, success on v22.
        let http = FakeAulaHTTP { request in
            request.url!.absoluteString.contains("/v21/")
                ? (410, Data())
                : (200, Data(#"{"ok":true}"#.utf8))
        }
        let client = AulaAPIClient(http: http)

        let response = try await client.get(method: "messaging.getThreads", session: session)

        #expect(response.session.apiVersion == 22)
        #expect(http.requests.count == 2)
        #expect(try #require(http.requests[0].url?.absoluteString.contains("/v21/")))
        #expect(try #require(http.requests[1].url?.absoluteString.contains("/v22/")))
        #expect(response.data == Data(#"{"ok":true}"#.utf8))
    }

    @Test func mapsUnauthorizedToSessionExpired() async throws {
        let http = FakeAulaHTTP { _ in (403, Data()) }
        let client = AulaAPIClient(http: http)

        await #expect(throws: AulaProviderError.sessionExpired) {
            _ = try await client.get(method: "messaging.getThreads", session: session)
        }
    }

    @Test func givesUpAfterExhaustingVersionBumps() async throws {
        // Always 410 — the client must stop rather than loop forever.
        let http = FakeAulaHTTP { _ in (410, Data()) }
        let client = AulaAPIClient(http: http)

        await #expect(throws: AulaProviderError.self) {
            _ = try await client.get(method: "messaging.getThreads", session: session)
        }
        #expect(http.requests.count == AulaAPIClient.maxVersionBumps + 1)
    }
}
