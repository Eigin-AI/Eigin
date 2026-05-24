import Foundation

// MARK: - Protocol

/// Handles an OAuth PKCE flow, returning an API key on success.
protocol OAuthPKCEService: Sendable {
    /// Launches the full OAuth PKCE flow and returns the resulting API key.
    func authenticate() async throws -> String
}

// MARK: - Implementation

struct DefaultOAuthPKCEService: OAuthPKCEService {
    private let authorizationURL: URL
    private let tokenExchangeURL: URL
    private let urlSession: URLSession

    private static let callbackURL = "https://auth.eigin.ai/callback/"

    init(authorizationURL: URL, tokenExchangeURL: URL, urlSession: URLSession = .shared) {
        self.authorizationURL = authorizationURL
        self.tokenExchangeURL = tokenExchangeURL
        self.urlSession = urlSession
    }

    /// Convenience initializer that reads OAuth URLs from a provider preset.
    init(preset: ProviderPreset, urlSession: URLSession = .shared) {
        self.init(
            authorizationURL: URL(string: preset.oAuthAuthorizationURL!)!,
            tokenExchangeURL: URL(string: preset.oAuthTokenExchangeURL!)!,
            urlSession: urlSession
        )
    }

    func authenticate() async throws -> String {
        // Generate PKCE pair
        let codeVerifier = PKCEUtilities.generateCodeVerifier()
        let codeChallenge = PKCEUtilities.generateCodeChallenge(from: codeVerifier)

        // Build authorization URL
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: Self.callbackURL),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = components.url else {
            throw OAuthPKCEError.authorizationFailed("Failed to build authorization URL")
        }

        // Present browser — 42futures.com/eigin/callback redirects to eigin://oauth/callback
        // which ASWebAuthenticationSession intercepts.
        let callbackURL: URL
        do {
            callbackURL = try await PKCEUtilities.presentAuthSession(url: authURL)
        } catch PKCEUtilities.AuthSessionError.userCancelled {
            throw OAuthPKCEError.userCancelled
        } catch let error as PKCEUtilities.AuthSessionError {
            throw OAuthPKCEError.authorizationFailed(error.localizedDescription)
        }

        // Parse authorization code from callback
        guard let callbackComponents = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        ),
            let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw OAuthPKCEError.authorizationFailed("No authorization code received")
        }

        // Exchange code for API key
        return try await exchangeCodeForKey(code: code, codeVerifier: codeVerifier)
    }

    // MARK: - Private

    private func exchangeCodeForKey(code: String, codeVerifier: String) async throws -> String {
        var request = URLRequest(url: tokenExchangeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "code": code,
            "code_verifier": codeVerifier,
            "code_challenge_method": "S256",
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw OAuthPKCEError.keyExchangeFailed("Server returned an error")
        }

        let decoded = try JSONDecoder().decode(KeyResponse.self, from: data)
        return decoded.key
    }
}

// MARK: - Response Type

private struct KeyResponse: Decodable {
    let key: String
}

// MARK: - Errors

enum OAuthPKCEError: LocalizedError, Equatable {
    case userCancelled
    case authorizationFailed(String)
    case keyExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            Localized.Errors.Authentication.cancelled
        case .authorizationFailed(let message):
            String(format: Localized.Errors.Authorization.failedWithReason(message), message)
        case .keyExchangeFailed(let message):
            String(format: Localized.Errors.Provider.apiKeyRetrievalFailed(message), message)
        }
    }
}
