import Foundation

/// The SIWC refresh-token grant: a rotating refresh token, so exactly one
/// refresh per stored token (enforced by the store's `inFlight` map).
enum ChatGPTTokenRefresh {
    static func perform(
        refreshToken: String,
        clientID: String?,
        urlSession: URLSession
    ) async throws -> RefreshedCredentialTokens {
        var request = URLRequest(url: ChatGPTSignInConstants.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(
                name: "client_id",
                value: clientID ?? ChatGPTSignInConstants.registrationClientID
            ),
            URLQueryItem(name: "resource", value: ChatGPTSignInConstants.resource),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CredentialRefreshError.transient("No response")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            // Only a rejected grant is terminal: the refresh token or client ID
            // is dead and the credential must be cleared (the durable "sign in
            // again" signal). A 429/5xx or otherwise unclassifiable failure is
            // an outage — clearing would permanently sign the user out.
            if isRejectedGrant(http.statusCode, body: body) {
                throw CredentialRefreshError.terminal(
                    "HTTP \(http.statusCode) \(body.prefix(300))"
                )
            }
            throw CredentialRefreshError.transient("HTTP \(http.statusCode)")
        }

        guard let decoded = try? JSONDecoder().decode(ChatGPTTokenResponse.self, from: data) else {
            throw CredentialRefreshError.transient("Unreadable refresh response")
        }
        return RefreshedCredentialTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresIn: decoded.expiresIn,
            scope: decoded.scope
        )
    }

    /// Whether the token endpoint rejected the grant itself: an expired,
    /// revoked, or already-used refresh token (RFC 6749 `invalid_grant` and
    /// friends), or a client ID that no longer exists. Everything else —
    /// throttling, outages, server errors — keeps the credential.
    private static func isRejectedGrant(_ statusCode: Int, body: String) -> Bool {
        guard (400 ... 499).contains(statusCode) else { return false }
        if body.contains("invalid_grant") || body.contains("unauthorized_client") {
            return true
        }
        return false
    }
}

/// Wire format of the SIWC token endpoint's response (both grants).
struct ChatGPTTokenResponse: Decodable {
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
