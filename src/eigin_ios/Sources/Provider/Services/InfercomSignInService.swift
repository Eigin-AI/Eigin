import Foundation

/// The Infercom sign-in credential. `apiToken` authorizes inference at
/// `api.infercom.ai` (it expires); `refreshToken` is the *login* refresh
/// token and rotates on every refresh — losing it forces a full re-login.
struct InfercomCredential: Equatable, Sendable {
    let apiToken: String
    let refreshToken: String
    let expiry: Date
}

enum InfercomSignInError: Error, Equatable {
    case userCancelled
    case authorizationFailed(String)
    /// The exchange returned 400 "identity is not verified" — the account's
    /// email is unconfirmed and the verification mail is sitting unread.
    case unverifiedEmail
    case httpError(code: Int, body: String?)
    case exchangeFailed(String)
}

protocol InfercomSignInService: Sendable {
    /// Runs the PKCE login and the RFC 8693 API-token exchange.
    func authenticate() async throws -> InfercomCredential
}

struct DefaultInfercomSignInService: InfercomSignInService {
    private let urlSession: URLSession
    private let config: PKCEOAuthConfig

    init(
        urlSession: URLSession = .shared,
        config: PKCEOAuthConfig = InfercomSignInConstants.pkceConfig
    ) {
        self.urlSession = urlSession
        self.config = config
    }

    func authenticate() async throws -> InfercomCredential {
        let loginTokens: TokenResponse
        do {
            loginTokens = try await PKCEOAuthFlow.authorize(config: config, urlSession: urlSession)
        } catch PKCEOAuthFlow.FlowError.userCancelled {
            throw InfercomSignInError.userCancelled
        } catch let error as PKCEOAuthFlow.FlowError {
            throw InfercomSignInError.authorizationFailed(error.localizedDescription)
        }

        let exchanged = try await exchange(accessToken: loginTokens.accessToken)
        guard let refreshToken = loginTokens.refreshToken else {
            throw InfercomSignInError.authorizationFailed("No refresh token granted")
        }
        // A missing expires_in is a malformed exchange response: defaulting
        // it to an expired credential would refresh (and burn a rotated
        // token) on every inference call.
        guard let expiresIn = exchanged.expiresIn else {
            throw InfercomSignInError.exchangeFailed("Exchange response has no expires_in")
        }
        return InfercomCredential(
            apiToken: exchanged.apiToken,
            refreshToken: refreshToken,
            expiry: Date.now.addingTimeInterval(expiresIn)
        )
    }

    // MARK: - RFC 8693 token exchange (internal for testing)

    /// Form-encoded exchange at `cloud.infercom.ai`. The response's
    /// `expires_in` is read — never hardcoded — because Infercom may shorten
    /// the token lifetime.
    func exchange(accessToken: String) async throws -> ExchangedTokens {
        let body = PKCEOAuthFlow.formEncode([
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "subject_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "subject_token": accessToken,
            "client_id": InfercomSignInConstants.clientID,
        ])

        var request = URLRequest(url: InfercomSignInConstants.exchangeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InfercomSignInError.exchangeFailed("No response")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            if http.statusCode == 400, let body,
               body.lowercased().contains("identity is not verified")
            {
                throw InfercomSignInError.unverifiedEmail
            }
            throw InfercomSignInError.httpError(code: http.statusCode, body: body)
        }

        struct ExchangeResponse: Decodable {
            let accessToken: String
            let expiresIn: Double?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
            }
        }

        guard let decoded = try? JSONDecoder().decode(ExchangeResponse.self, from: data) else {
            throw InfercomSignInError.exchangeFailed("Unreadable exchange response")
        }
        return ExchangedTokens(
            apiToken: decoded.accessToken,
            expiresIn: decoded.expiresIn
        )
    }
}

/// What the exchange yields — the caller pairs it with the login's own
/// refresh token to make a full ``InfercomCredential``.
struct ExchangedTokens: Equatable, Sendable {
    let apiToken: String
    /// Lifetime of the API token in seconds, read from the response.
    let expiresIn: TimeInterval?
}
