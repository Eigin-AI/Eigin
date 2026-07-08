import Foundation

/// Shared PKCE authorization-code flow: build the authorization URL, present
/// the browser, validate the callback, and exchange/refresh tokens.
///
/// Extracted so ``MCPOAuthService`` and ``IntegrationOAuthService`` share one
/// implementation of the flow's mechanics instead of two near-duplicates.
/// Discovery (MCP) and static configuration (integrations) stay with their
/// callers — only the PKCE dance itself lives here.
enum PKCEOAuthFlow {
    /// HTTPS passthrough that redirects to `eigin://oauth/callback`. Used as the
    /// default redirect URI because some authorization servers (e.g. Google)
    /// don't accept arbitrary custom URL schemes directly.
    static let defaultRedirectURI = "https://auth.eigin.ai/callback/"

    /// Runs the full flow: browser auth → code exchange → tokens.
    ///
    /// The `ASWebAuthenticationSession` callback scheme is derived from
    /// `config.redirectURI`'s URL scheme by default, so it can't drift out of
    /// sync with the redirect URI actually sent to the authorization server —
    /// pass `callbackScheme` explicitly only to override that.
    static func authorize(
        config: PKCEOAuthConfig,
        callbackScheme: String? = nil,
        urlSession: URLSession = .shared
    ) async throws -> TokenResponse {
        let codeVerifier = PKCEUtilities.generateCodeVerifier()
        let codeChallenge = PKCEUtilities.generateCodeChallenge(from: codeVerifier)
        let state = PKCEUtilities.generateState()

        let authURL = try buildAuthorizationURL(
            config: config,
            codeChallenge: codeChallenge,
            state: state
        )
        let scheme = callbackScheme
            ?? URL(string: config.redirectURI)?.scheme
            ?? "eigin"

        let callbackURL: URL
        do {
            callbackURL = try await PKCEUtilities.presentAuthSession(
                url: authURL,
                callbackScheme: scheme
            )
        } catch PKCEUtilities.AuthSessionError.userCancelled {
            throw FlowError.userCancelled
        } catch let error as PKCEUtilities.AuthSessionError {
            throw FlowError.authorizationFailed(error.localizedDescription)
        }

        let code = try validateCallback(callbackURL, expectedState: state)

        return try await exchangeCode(
            code: code,
            codeVerifier: codeVerifier,
            config: config,
            urlSession: urlSession
        )
    }

    /// Exchanges a refresh token for a new access token.
    static func refresh(
        refreshToken: String,
        config: PKCEOAuthConfig,
        urlSession: URLSession = .shared
    ) async throws -> TokenResponse {
        var params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ]
        if let secret = config.clientSecret {
            params["client_secret"] = secret
        }
        for (key, value) in config.extraTokenParams {
            params[key] = value
        }

        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(params).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw FlowError.tokenRefreshFailed("Server returned an error")
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Private

    private static func buildAuthorizationURL(
        config: PKCEOAuthConfig,
        codeChallenge: String,
        state: String
    ) throws -> URL {
        guard var components = URLComponents(
            url: config.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw FlowError.authorizationFailed("Invalid authorization endpoint")
        }

        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if !config.scopes.isEmpty {
            queryItems.append(URLQueryItem(
                name: "scope",
                value: config.scopes.joined(separator: " ")
            ))
        }
        for (key, value) in config.extraAuthorizationParams {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw FlowError.authorizationFailed("Failed to build authorization URL")
        }
        return url
    }

    private static func validateCallback(_ url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw FlowError.authorizationFailed("Invalid callback URL")
        }

        let params = components.queryItems ?? []
        let returnedState = params.first(where: { $0.name == "state" })?.value
        let code = params.first(where: { $0.name == "code" })?.value
        let error = params.first(where: { $0.name == "error" })?.value

        if let error {
            throw FlowError.authorizationFailed(error)
        }
        guard returnedState == expectedState else {
            throw FlowError.authorizationFailed("State mismatch")
        }
        guard let code else {
            throw FlowError.authorizationFailed("No authorization code received")
        }
        return code
    }

    private static func exchangeCode(
        code: String,
        codeVerifier: String,
        config: PKCEOAuthConfig,
        urlSession: URLSession
    ) async throws -> TokenResponse {
        var params = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": codeVerifier,
        ]
        if let secret = config.clientSecret {
            params["client_secret"] = secret
        }
        for (key, value) in config.extraTokenParams {
            params[key] = value
        }

        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(params).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw FlowError.tokenExchangeFailed("Token exchange failed")
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let escapedKey = key
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }

    // MARK: - Errors

    enum FlowError: Error, LocalizedError, Equatable {
        case userCancelled
        case authorizationFailed(String)
        case tokenExchangeFailed(String)
        case tokenRefreshFailed(String)

        var errorDescription: String? {
            switch self {
            case .userCancelled:
                Localized.Errors.Authentication.cancelled
            case .authorizationFailed(let reason):
                "Authorization failed: \(reason)"
            case .tokenExchangeFailed(let reason):
                "Token exchange failed: \(reason)"
            case .tokenRefreshFailed(let reason):
                "Token refresh failed: \(reason)"
            }
        }
    }
}
