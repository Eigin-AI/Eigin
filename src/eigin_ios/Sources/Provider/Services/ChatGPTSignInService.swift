import Foundation

// Sign in with ChatGPT (SIWC) for open-source apps — the official OAuth flow
// that lets ChatGPT Plus/Pro subscribers use their plan for inference
// (https://developers.openai.com/siwc).
//
// Mechanics per spec: dynamic client registration on first sign-in
// (`client_id=dynamic_agent_client`), a stable per-install
// `ext_agent_host_id`, an HTTP loopback redirect on `127.0.0.1`
// (scheme/host/path fixed, port varies), PKCE S256, and ID-token validation
// against OpenAI's JWKS before the credential is returned.

/// Runs one SIWC browser flow and returns a validated credential.
protocol ChatGPTSignInService: Sendable {
    /// Presents the consent screen in the caller's browser view and completes
    /// the exchange. `existingClientID`/`idTokenHint` turn the attempt into a
    /// reauthorization (omitted on first sign-in, where registration happens).
    func authenticate(
        existingClientID: String?,
        idTokenHint: String?,
        present: @MainActor @Sendable (URL) -> Void
    ) async throws -> ChatGPTCredential
}

struct DefaultChatGPTSignInService: ChatGPTSignInService {
    private let credentialStore: any ProviderCredentialStoring
    private let urlSession: URLSession

    init(
        credentialStore: any ProviderCredentialStoring,
        urlSession: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.urlSession = urlSession
    }

    func authenticate(
        existingClientID: String?,
        idTokenHint: String?,
        present: @MainActor @Sendable (URL) -> Void
    ) async throws -> ChatGPTCredential {
        guard let hostID = await credentialStore.hostID() else {
            throw ChatGPTSubscriptionError
                .failed("Could not create a stable host ID for this install.")
        }

        let listener: LoopbackCallbackServer
        let redirectURI: String
        do {
            listener = try LoopbackCallbackServer(path: ChatGPTSignInConstants.callbackPath)
            redirectURI = try listener.redirectURI()
        } catch {
            throw ChatGPTSubscriptionError.failed(error.localizedDescription)
        }
        defer { listener.stop() }

        let codeVerifier = PKCEUtilities.generateCodeVerifier()
        let state = PKCEUtilities.generateState()
        let nonce = PKCEUtilities.generateState()

        let authorizeURL = buildAuthorizeURL(
            clientID: existingClientID ?? ChatGPTSignInConstants.registrationClientID,
            redirectURI: redirectURI,
            hostID: hostID,
            idTokenHint: idTokenHint,
            codeVerifier: codeVerifier,
            state: state,
            nonce: nonce
        )

        await present(authorizeURL)

        let accepted = try await runWithTimeout { [self] in
            try await acceptCallback(
                on: listener,
                state: state,
                expectedClientID: existingClientID
            )
        }
        return try await exchange(
            code: accepted.code,
            clientID: accepted.clientID,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier,
            expectedNonce: nonce
        )
    }

    // MARK: - Authorization URL

    /// Internal for testing: builds the authorize request with all SIWC
    /// parameters. Registration-only fields (`agent_name_hint`) appear only
    /// when no client ID exists yet; reauthorization carries `id_token_hint`.
    func buildAuthorizeURL(
        clientID: String,
        redirectURI: String,
        hostID: String,
        idTokenHint: String?,
        codeVerifier: String,
        state: String,
        nonce: String
    ) -> URL {
        var components = URLComponents(
            url: ChatGPTSignInConstants.authorizeURL,
            resolvingAgainstBaseURL: false
        )!
        var query = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(
                name: "scope",
                value: ChatGPTSignInConstants.scopes.joined(separator: " ")
            ),
            URLQueryItem(name: "resource", value: ChatGPTSignInConstants.resource),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(
                name: "code_challenge",
                value: PKCEUtilities.generateCodeChallenge(from: codeVerifier)
            ),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        if idTokenHint != nil {
            query.append(URLQueryItem(name: "id_token_hint", value: idTokenHint))
        }
        components.queryItems = query
        // Registration display metadata only on the first-time dynamic registration.
        if clientID == ChatGPTSignInConstants.registrationClientID {
            additionalRegistrationQueryItems(into: &query)
            components.queryItems = query
        }
        return components.url!
    }

    private func additionalRegistrationQueryItems(into query: inout [URLQueryItem]) {
        query.append(URLQueryItem(
            name: "agent_name_hint",
            value: ChatGPTSignInConstants.agentNameHint
        ))
    }

    // MARK: - Callback

    /// Internal for testing: validates the callback the loopback server
    /// received and returns the authorization code.
    func acceptCallback(
        _ components: URLComponents,
        state expectedState: String,
        expectedClientID: String?
    ) throws -> (code: String, clientID: String?) {
        let items = components.queryItems ?? []

        if let error = items.first(where: { $0.name == "error" })?.value {
            if error == "access_denied" {
                throw ChatGPTSubscriptionError.declined
            }
            throw ChatGPTSubscriptionError.failed(error)
        }

        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw ChatGPTSubscriptionError.stateMismatch
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw ChatGPTSubscriptionError.failed("No authorization code received")
        }

        let issuedClientID = items.first(where: { $0.name == "client_id" })?.value
        if expectedClientID == nil, issuedClientID == nil {
            // New registration without an issued ID is incomplete — do not
            // exchange a code we cannot connect to a client.
            throw ChatGPTSubscriptionError.registrationIncomplete
        }
        if let expected = expectedClientID, let issued = issuedClientID, issued != expected {
            throw ChatGPTSubscriptionError.clientIDMismatch
        }

        return (code, issuedClientID ?? expectedClientID)
    }

    private func acceptCallback(
        on listener: LoopbackCallbackServer,
        state: String,
        expectedClientID: String?
    ) async throws -> (code: String, clientID: String?) {
        let components: URLComponents
        do {
            components = try await listener.waitForCallback()
        } catch LoopbackCallbackServer.LoopbackError.cancelled {
            // The browser sheet was dismissed or the wait was cancelled.
            throw ChatGPTSubscriptionError.userCancelled
        }
        let result = try acceptCallback(
            components,
            state: state,
            expectedClientID: expectedClientID
        )
        listener.respondWith(components: components)
        return result
    }

    // MARK: - Token exchange

    /// Internal for testing: the form-encoded `authorization_code` grant.
    func exchange(
        code: String,
        clientID: String?,
        redirectURI: String,
        codeVerifier: String,
        expectedNonce: String,
        urlSession: URLSession? = nil
    ) async throws -> ChatGPTCredential {
        var request = URLRequest(url: ChatGPTSignInConstants.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body: [URLQueryItem] = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "resource", value: ChatGPTSignInConstants.resource),
        ]
        if let clientID {
            body.append(URLQueryItem(name: "client_id", value: clientID))
        }
        var components = URLComponents()
        components.queryItems = body
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let session = urlSession ?? self.urlSession
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTSubscriptionError
                .tokenExchangeFailed("No response from the sign-in server.")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            // Staging build: the full failure body is the diagnosis (the
            // endpoint's error_description names the actual grant failure).
            AppLogger.error(
                "SIWC token exchange failed (HTTP \(public: http.statusCode)): \(public: detail)",
                category: .network
            )
            if detail.contains("invalid_grant") {
                // Verified live: an account without an eligible ChatGPT
                // subscription gets a bare invalid_grant — the grant cannot
                // be minted because there is no plan to bind it to.
                throw ChatGPTSubscriptionError.subscriptionRequired
            }
            throw ChatGPTSubscriptionError.tokenExchangeFailed(
                "Token exchange failed (HTTP \(http.statusCode)) \(detail.prefix(300))"
            )
        }

        let tokenResponse: TokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw ChatGPTSubscriptionError.tokenExchangeFailed("Unreadable token response.")
        }

        let granted = Set((tokenResponse.scope ?? "").split(separator: " ").map(String.init))
        guard granted.contains(ChatGPTSignInConstants.planUsageScope) else {
            throw ChatGPTSubscriptionError.planUsageNotGranted
        }

        guard let idToken = tokenResponse.idToken, let clientID else {
            throw ChatGPTSubscriptionError.tokenExchangeFailed("Missing ID token or client ID.")
        }

        do {
            _ = try await OIDCTokenValidator.validate(
                idToken,
                jwksURL: ChatGPTSignInConstants.jwksURL,
                expectedIssuer: ChatGPTSignInConstants.issuer,
                expectedAudience: clientID,
                expectedNonce: expectedNonce,
                session: session
            )
        } catch let error as OIDCTokenValidator.ValidationError {
            AppLogger.error(
                "SIWC ID token validation failed: \(public: error.localizedDescription)",
                category: .network
            )
            throw ChatGPTSubscriptionError.idTokenValidation(error.localizedDescription)
        }

        return ChatGPTCredential(
            clientID: clientID,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? "",
            idToken: idToken,
            expiry: Date.now.addingTimeInterval(tokenResponse.expiresIn ?? 3600),
            scopes: granted.sorted()
        )
    }

    // MARK: - Timeout wrapper

    private func runWithTimeout<T: Sendable>(
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            defer { group.cancelAll() }
            group.addTask {
                do {
                    return try await body()
                } catch is CancellationError {
                    return nil
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(ChatGPTSignInConstants.listenTimeout))
                } catch is CancellationError {
                    return nil
                }
                throw ChatGPTSubscriptionError.timedOut
            }
            guard let first = try await group.next(), let value = first else {
                // Either the timeout fired, or the body was cancelled.
                throw ChatGPTSubscriptionError.timedOut
            }
            return value
        }
    }
}

// MARK: - Wire types

extension DefaultChatGPTSignInService {
    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: Double?
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
            case scope
        }
    }
}
