@testable import Eigin
import Foundation

/// Scriptable ``AulaReauthorizer`` fake: returns a fixed result and records
/// how many times a silent re-authorize was attempted, so tests can assert
/// the provider retries exactly once and only when it should.
final class FakeAulaReauthorizer: AulaReauthorizer, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<AulaReauthResult, Error>
    private var count = 0

    init(result: Result<AulaReauthResult, Error>) {
        self.result = result
    }

    /// Convenience: a successful re-authorize returning fresh tokens and the
    /// given cookie jar (defaults to a single `Csrfp-Token`, mirroring what a
    /// real re-warm leaves behind).
    static func returning(
        accessToken: String,
        cookies: [HTTPCookie]? = nil
    ) -> FakeAulaReauthorizer {
        let jar = cookies ?? [
            HTTPCookie(properties: [
                .name: "Csrfp-Token",
                .value: "fresh-csrf",
                .domain: "www.aula.dk",
                .path: "/",
            ])!,
        ]
        return FakeAulaReauthorizer(result: .success(AulaReauthResult(
            tokens: TokenResponse(
                accessToken: accessToken,
                tokenType: "Bearer",
                expiresIn: 3600,
                refreshToken: "new-refresh",
                scope: "aula-sensitive"
            ),
            cookies: jar
        )))
    }

    var reauthorizeCount: Int {
        lock.withLock { count }
    }

    func reauthorize(
        brokerCookies: [HTTPCookie],
        userAgent: String?
    ) async throws -> AulaReauthResult {
        lock.withLock { count += 1 }
        return try result.get()
    }

    struct ReauthorizeUnavailable: Error {}
}
