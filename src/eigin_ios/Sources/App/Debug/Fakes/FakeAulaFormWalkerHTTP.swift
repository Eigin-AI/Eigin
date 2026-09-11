#if DEBUG || EIGIN_DEV
import Foundation

/// Scriptable ``AulaFormWalkerHTTP`` fake: each stubbed URL returns a fixed
/// response for `GET`/`POST`, and every request is recorded so tests can
/// assert on the exact hop the walker took (URL, form fields posted).
final class FakeAulaFormWalkerHTTP: AulaFormWalkerHTTP, @unchecked Sendable {
    struct Stub {
        let statusCode: Int
        let location: URL?
        let body: String
    }

    struct RecordedRequest: Equatable {
        let method: String
        let url: URL
        let form: [String: String]
        let referer: URL?
    }

    private let lock = NSLock()
    private var stubs: [String: Stub] = [:]
    private var recorded: [RecordedRequest] = []

    var requests: [RecordedRequest] {
        lock.withLock { recorded }
    }

    func stub(_ url: URL, statusCode: Int, location: URL? = nil, body: String = "") {
        lock.withLock { stubs[url.absoluteString] = Stub(
            statusCode: statusCode,
            location: location,
            body: body
        ) }
    }

    func post(
        _ url: URL,
        form: [String: String],
        referer: URL
    ) async throws -> AulaFormWalkerResponse {
        lock.withLock {
            recorded.append(RecordedRequest(method: "POST", url: url, form: form, referer: referer))
        }
        return try response(for: url)
    }

    func get(_ url: URL) async throws -> AulaFormWalkerResponse {
        lock.withLock {
            recorded.append(RecordedRequest(method: "GET", url: url, form: [:], referer: nil))
        }
        return try response(for: url)
    }

    private func response(for url: URL) throws -> AulaFormWalkerResponse {
        guard let stub = lock.withLock({ stubs[url.absoluteString] }) else {
            throw AulaConnectionError.unexpectedResponse
        }
        return AulaFormWalkerResponse(
            statusCode: stub.statusCode,
            url: url,
            location: stub.location,
            body: stub.body
        )
    }
}
#endif
