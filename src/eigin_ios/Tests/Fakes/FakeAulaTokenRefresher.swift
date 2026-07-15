@testable import Eigin
import Foundation

/// Scriptable ``AulaTokenRefresher`` fake: returns a fixed result and records
/// how many times a refresh was attempted, so tests can assert the provider
/// refreshes exactly when it should.
final class FakeAulaTokenRefresher: AulaTokenRefresher, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<TokenResponse, Error>
    private var count = 0

    init(result: Result<TokenResponse, Error>) {
        self.result = result
    }

    /// Convenience: a successful refresh returning the given access token.
    static func returning(accessToken: String, expiresIn: Int? = 3600) -> FakeAulaTokenRefresher {
        FakeAulaTokenRefresher(result: .success(TokenResponse(
            accessToken: accessToken,
            tokenType: "Bearer",
            expiresIn: expiresIn,
            refreshToken: "new-refresh",
            scope: "aula-sensitive"
        )))
    }

    var refreshCount: Int {
        lock.withLock { count }
    }

    func refresh(refreshToken: String) async throws -> TokenResponse {
        lock.withLock { count += 1 }
        return try result.get()
    }

    struct RefreshUnavailable: Error {}
}
