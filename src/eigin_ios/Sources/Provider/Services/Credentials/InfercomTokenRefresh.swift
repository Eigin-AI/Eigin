import Foundation

/// The Infercom refresh leg: a refresh-token grant at the login server
/// (`auth.infercom.ai`), then a re-exchange to mint a fresh API token.
/// The login refresh token rotates — exactly one refresh per stored token
/// (enforced by the store's `inFlight` map).
enum InfercomTokenRefresh {
    static func perform(
        refreshToken: String,
        urlSession: URLSession
    ) async throws -> RefreshedCredentialTokens {
        var request = URLRequest(url: InfercomSignInConstants.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = PKCEOAuthFlow.formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": InfercomSignInConstants.clientID,
        ]).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CredentialRefreshError.transient("No response")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            // Only a rejected grant is terminal: the rotated-away refresh
            // token or a revoked session. Throttling and outages keep the
            // credential — clearing would permanently sign the user out.
            if isRejectedGrant(http.statusCode, body: body) {
                throw CredentialRefreshError.terminal(
                    "HTTP \(http.statusCode) \(body.prefix(300))"
                )
            }
            throw CredentialRefreshError.transient("HTTP \(http.statusCode)")
        }

        guard let decoded = try? JSONDecoder().decode(RefreshTokenResponse.self, from: data) else {
            throw CredentialRefreshError.transient("Unreadable refresh response")
        }
        return RefreshedCredentialTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresIn: decoded.expiresIn,
            scope: decoded.scope
        )
    }

    /// Whether the token endpoint rejected the grant itself (RFC 6749
    /// `invalid_grant` and friends). Everything else keeps the credential.
    private static func isRejectedGrant(_ statusCode: Int, body: String) -> Bool {
        guard (400 ... 499).contains(statusCode) else { return false }
        return body.contains("invalid_grant") || body.contains("unauthorized_client")
    }
}

/// Wire format of the login token endpoint's refresh response.
private struct RefreshTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

/// Best-effort refresh-token revocation at `auth.infercom.ai`. There is no
/// third-party logout endpoint — sign-out is this call plus dropping the
/// stored tokens. Failure never blocks sign-out.
enum InfercomTokenRevocation {
    static func perform(
        refreshToken: String,
        urlSession: URLSession
    ) async {
        var request = URLRequest(url: InfercomSignInConstants.revocationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = PKCEOAuthFlow.formEncode([
            "token": refreshToken,
            "token_type_hint": "refresh_token",
            "client_id": InfercomSignInConstants.clientID,
        ]).data(using: .utf8)

        _ = try? await urlSession.data(for: request)
    }
}
