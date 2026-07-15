@testable import Eigin
import Foundation
import Testing

/// Exercises the credential-free SAML tail ``AulaFormWalker`` drives after the
/// interactive web view hands off a pending form — the replacement for the
/// old fresh-authorize `AulaSilentAuthorizer`, which couldn't traverse these
/// 200-HTML form hops at all.
@Suite("AulaFormWalker")
struct AulaFormWalkerTests {
    private let redirectHost = "app-private.aula.dk"
    private let tokenEndpoint =
        URL(string: "https://login.aula.dk/simplesaml/module.php/oidc/token.php")!

    private func config() -> PKCEOAuthConfig {
        PKCEOAuthConfig(
            authorizationEndpoint: URL(
                string: "https://login.aula.dk/simplesaml/module.php/oidc/authorize.php"
            )!,
            tokenEndpoint: tokenEndpoint,
            clientID: "client",
            scopes: ["aula-sensitive"],
            redirectURI: "https://\(redirectHost)"
        )
    }

    private func stubTokenExchange() {
        FakeURLProtocol.stubResponse(
            for: tokenEndpoint.absoluteString,
            data: Data(
                #"{"access_token":"tok","token_type":"Bearer","expires_in":3600,"refresh_token":"ref"}"#
                    .utf8
            ),
            statusCode: 200
        )
    }

    @Test func reachesCallbackAfterFormPostAndRedirect() async throws {
        stubTokenExchange()
        let action =
            try #require(
                URL(
                    string: "https://broker.unilogin.dk/auth/realms/broker/broker/nemlogin3/endpoint"
                )
            )
        let callback = try #require(URL(string: "https://\(redirectHost)?code=abc123&state=state1"))
        let http = FakeAulaFormWalkerHTTP()
        http.stub(action, statusCode: 302, location: callback)

        let result = try await AulaFormWalker.walk(
            firstForm: AulaHTMLForm(
                action: action.absoluteString,
                fields: ["SAMLResponse": "resp"]
            ),
            formPageURL: #require(URL(string: "https://nemlog-in.mitid.dk/login/mitid")),
            cookies: [],
            expectedState: "state1",
            codeVerifier: "verifier",
            redirectHost: redirectHost,
            config: config(),
            http: http,
            urlSession: FakeURLProtocol.fakeSession()
        )

        #expect(result.tokens?.accessToken == "tok")
        #expect(http.requests.first?.form["SAMLResponse"] == "resp")
        // The broker's SAML endpoint rejects the POST without these — mirror
        // what a real browser sends when the page auto-submits the form.
        #expect(http.requests.first?
            .referer == URL(string: "https://nemlog-in.mitid.dk/login/mitid")!)
    }

    @Test func walksBrokerConfirmationFormBeforeReachingCallback() async throws {
        stubTokenExchange()
        let samlAction =
            try #require(
                URL(
                    string: "https://login.aula.dk/simplesaml/module.php/saml/sp/saml2-acs.php/app-level3-sp"
                )
            )
        let confirmAction =
            try #require(
                URL(
                    string: "https://broker.unilogin.dk/auth/realms/broker/login-actions/post-broker-login"
                )
            )
        let callback = try #require(URL(string: "https://\(redirectHost)?code=xyz&state=state2"))
        let portal = try #require(URL(string: "https://www.aula.dk/portal/"))

        let http = FakeAulaFormWalkerHTTP()
        // First hop lands on a 200 confirmation page (community-reference #306/#287).
        http.stub(
            samlAction,
            statusCode: 200,
            body: """
            <form action="\(confirmAction.absoluteString)">
            <input type="hidden" name="selected-aktoer" value="KONTAKT" />
            <button id="confirmation-button">Continue</button>
            </form>
            """
        )
        http.stub(confirmAction, statusCode: 302, location: callback)
        // After the code is minted the walk warms the web session by loading
        // the portal, so the sensitive-endpoint cookies (Csrfp-Token) are set.
        http.stub(portal, statusCode: 200, body: "<html><body>Aula</body></html>")

        let result = try await AulaFormWalker.walk(
            firstForm: AulaHTMLForm(
                action: samlAction.absoluteString,
                fields: ["SAMLResponse": "resp"]
            ),
            formPageURL: #require(URL(string: "https://login.aula.dk/some-page")),
            cookies: [],
            expectedState: "state2",
            codeVerifier: "verifier",
            redirectHost: redirectHost,
            config: config(),
            http: http,
            urlSession: FakeURLProtocol.fakeSession()
        )

        #expect(result.tokens?.accessToken == "tok")
        #expect(http.requests.map(\.url) == [samlAction, confirmAction, portal])
        #expect(http.requests.dropLast().last?.form["selected-aktoer"] == "KONTAKT")
    }

    @Test func succeedsCookieOnlyOnReachingPortal() async throws {
        let acs =
            try #require(
                URL(
                    string: "https://login.aula.dk/simplesaml/module.php/saml/sp/saml2-acs.php/app-level3-sp"
                )
            )
        let portal = try #require(URL(string: "https://www.aula.dk/portal/"))
        // The real browser login ends here: no OAuth code, just the aula.dk
        // web-session cookies. Reaching the portal *is* success — the walk
        // returns the jar and lets the verifier judge it, rather than chasing
        // a callback the web flow never produces.
        let http = FakeAulaFormWalkerHTTP()
        http.stub(acs, statusCode: 303, location: portal)
        http.stub(portal, statusCode: 200, body: "<html><body>Aula</body></html>")
        let sessionCookie = try #require(HTTPCookie(properties: [
            .name: "PHPSESSID",
            .value: "sess1",
            .domain: ".aula.dk",
            .path: "/",
        ]))

        let result = try await AulaFormWalker.walk(
            firstForm: AulaHTMLForm(action: acs.absoluteString, fields: ["SAMLResponse": "resp"]),
            formPageURL: #require(URL(string: "https://broker.unilogin.dk/page")),
            cookies: [sessionCookie],
            expectedState: "original-state",
            codeVerifier: "original-verifier",
            redirectHost: redirectHost,
            config: config(),
            http: http
        )

        #expect(result.tokens == nil)
        #expect(result.cookies.contains { $0.name == "PHPSESSID" && $0.value == "sess1" })
        // Stopped at the portal — never issued a further request.
        #expect(http.requests.map(\.url) == [acs, portal])
    }

    @Test func throwsOnStateMismatch() async throws {
        let action = try #require(URL(string: "https://broker.unilogin.dk/endpoint"))
        let callback = try #require(URL(string: "https://\(redirectHost)?code=abc&state=wrong"))
        let http = FakeAulaFormWalkerHTTP()
        http.stub(action, statusCode: 302, location: callback)

        await #expect(throws: (any Error).self) {
            _ = try await AulaFormWalker.walk(
                firstForm: AulaHTMLForm(action: action.absoluteString, fields: [:]),
                formPageURL: #require(URL(string: "https://nemlog-in.mitid.dk/")),
                cookies: [],
                expectedState: "expected",
                codeVerifier: "verifier",
                redirectHost: redirectHost,
                config: config(),
                http: http
            )
        }
    }

    @Test func throwsWhenPageHasNeitherFormNorCallback() async throws {
        let action = try #require(URL(string: "https://broker.unilogin.dk/endpoint"))
        let http = FakeAulaFormWalkerHTTP()
        http.stub(action, statusCode: 200, body: "<html><body>Dead end</body></html>")

        await #expect(throws: AulaConnectionError.sessionRejected) {
            _ = try await AulaFormWalker.walk(
                firstForm: AulaHTMLForm(action: action.absoluteString, fields: [:]),
                formPageURL: #require(URL(string: "https://nemlog-in.mitid.dk/")),
                cookies: [],
                expectedState: "state",
                codeVerifier: "verifier",
                redirectHost: redirectHost,
                config: config(),
                http: http
            )
        }
    }

    @Test func reauthorizeSilentlySSOsToTheCallback() async throws {
        // The happy path: the broker session is still alive, so GETting the
        // authorize URL directly (no MitID prompt) lands straight on an
        // auto-submit SAML confirmation form, then the callback — the same
        // hop shape `walk` sees after its intercepted form, minus the initial
        // interactive step.
        stubTokenExchange()
        let authorizeURL = try #require(
            URL(string: "https://login.aula.dk/simplesaml/module.php/oidc/authorize.php?x=1")
        )
        let samlAction = try #require(
            URL(
                string: "https://login.aula.dk/simplesaml/module.php/saml/sp/saml2-acs.php/app-level3-sp"
            )
        )
        let callback = try #require(URL(string: "https://\(redirectHost)?code=re1&state=state3"))
        let portal = try #require(URL(string: "https://www.aula.dk/portal/"))

        let http = FakeAulaFormWalkerHTTP()
        http.stub(
            authorizeURL,
            statusCode: 200,
            body: """
            <form action="\(samlAction.absoluteString)">
            <input type="hidden" name="SAMLResponse" value="resp" />
            </form>
            """
        )
        http.stub(samlAction, statusCode: 302, location: callback)
        // After the code is minted the walk warms the web session by loading
        // the portal, so the sensitive-endpoint cookies (Csrfp-Token) are set.
        http.stub(portal, statusCode: 200, body: "<html><body>Aula</body></html>")

        let result = try await AulaFormWalker.reauthorize(
            authorizationURL: authorizeURL,
            brokerCookies: [],
            expectedState: "state3",
            codeVerifier: "verifier",
            redirectHost: redirectHost,
            config: config(),
            http: http,
            urlSession: FakeURLProtocol.fakeSession()
        )

        #expect(result.tokens?.accessToken == "tok")
        #expect(http.requests.map(\.url) == [authorizeURL, samlAction, portal])
    }

    @Test func reauthorizeFailsWhenTheBrokerSessionHasLapsed() async throws {
        // A dead broker session lands on an interactive page (MitID prompt,
        // IdP selection) instead of an auto-submit form. In silent mode that
        // must not be resubmitted via the generic form fallback `walk` uses —
        // there's no credential to complete it headlessly — so it's treated
        // as a failed silent SSO.
        let authorizeURL = try #require(
            URL(string: "https://login.aula.dk/simplesaml/module.php/oidc/authorize.php?x=1")
        )
        let mitIDPage = try #require(URL(string: "https://nemlog-in.mitid.dk/login"))
        let http = FakeAulaFormWalkerHTTP()
        // No broker session left to silently SSO with, so the broker
        // redirects to a real, interactive MitID login page instead of an
        // auto-submit hop.
        http.stub(authorizeURL, statusCode: 302, location: mitIDPage)
        http.stub(
            mitIDPage,
            statusCode: 200,
            body: """
            <html><body>
            <form action="https://nemlog-in.mitid.dk/login">
            <input type="text" name="username" />
            <button type="submit">Log ind</button>
            </form>
            </body></html>
            """
        )

        await #expect(throws: AulaConnectionError.sessionRejected) {
            _ = try await AulaFormWalker.reauthorize(
                authorizationURL: authorizeURL,
                brokerCookies: [],
                expectedState: "state4",
                codeVerifier: "verifier",
                redirectHost: redirectHost,
                config: config(),
                http: http
            )
        }
    }

    @Test func givesUpAfterExceedingHopLimit() async throws {
        // A form that just posts to itself forever — never resolves, so the
        // walk must bail rather than loop indefinitely.
        let action = try #require(URL(string: "https://broker.unilogin.dk/loop"))
        let http = FakeAulaFormWalkerHTTP()
        http.stub(
            action,
            statusCode: 200,
            body: """
            <form action="\(action.absoluteString)">
            <input type="hidden" name="loop" value="1" />
            </form>
            """
        )

        await #expect(throws: (any Error).self) {
            _ = try await AulaFormWalker.walk(
                firstForm: AulaHTMLForm(action: action.absoluteString, fields: ["loop": "1"]),
                formPageURL: #require(URL(string: "https://nemlog-in.mitid.dk/")),
                cookies: [],
                expectedState: "state",
                codeVerifier: "verifier",
                redirectHost: redirectHost,
                config: config(),
                http: http
            )
        }
    }
}
