import Foundation
import Network

/// A minimal HTTP server on `127.0.0.1` that waits for exactly one `GET` on a fixed path
/// (e.g. `/auth/callback`), hands the full query to the caller, answers the browser with a
/// final HTML page, and stops.
///
/// For OAuth flows that redirect to an HTTP loopback URI — `http://127.0.0.1:<port>/<path>`,
/// where only the port may vary — so no custom URL scheme or web-hosted passthrough is needed.
final class LoopbackCallbackServer: @unchecked Sendable {
    enum LoopbackError: LocalizedError, Equatable {
        case listenerFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .listenerFailed(let detail):
                "Loopback listener failed: \(detail)"
            case .cancelled:
                "Waiting for the sign-in was cancelled."
            }
        }
    }

    private let path: String
    private let listener: NWListener
    /// All listener, connection, and continuation state is confined to this queue.
    private let queue = DispatchQueue(label: "ai.eigin.loopback-callback")

    private var continuation: CheckedContinuation<URLComponents, any Error>?
    /// Terminal failure recorded before a waiter arrives (listener failure or `stop()`).
    private var pendingError: (any Error)?
    private var boundPort: UInt16 = 0

    /// Starts listening on a free port, bound to `127.0.0.1` only.
    init(path: String) throws {
        self.path = path
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Loopback-only, as SIWC requires; the port is ephemeral and read back once ready.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw LoopbackError.listenerFailed(error.localizedDescription)
        }
        listener.stateUpdateHandler = { [weak self] state in
            // Runs on `queue` — touch state directly; a queue.sync here would
            // self-deadlock the serial queue.
            switch state {
            case .ready:
                self?.boundPort = self?.listener.port?.rawValue ?? 0
            case .failed(let error):
                self?.failOnQueue(LoopbackError.listenerFailed(error.localizedDescription))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    deinit {
        listener.cancel()
    }

    /// The loopback redirect URI this instance accepts, e.g.
    /// `http://127.0.0.1:54321/auth/callback` — the exact same string must go into the
    /// authorization request and the code exchange.
    func redirectURI() throws -> String {
        try waitUntilReady()
        return "http://127.0.0.1:\(queue.sync { boundPort })\(path)"
    }

    /// Waits for the first `GET <path>?…` request and returns the full URL as components.
    /// Requests that miss the path (favicon and friends) are answered 404 and ignored.
    /// Task cancellation stops the server, which resolves the wait with `cancelled`.
    func waitForCallback() async throws -> URLComponents {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.sync {
                    if let pendingError {
                        continuation.resume(throwing: pendingError)
                        return
                    }
                    self.continuation = continuation
                }
            }
        } onCancel: { [weak self] in
            self?.stop()
        }
    }

    /// Completes a waiter with the callback URL, then answers the browser and shuts down.
    func respondWith(components: URLComponents) {
        queue.sync {
            if let continuation {
                self.continuation = nil
                continuation.resume(returning: components)
            }
        }
        listener.cancel()
    }

    /// Completes a waiter with an error, then shuts down.
    func respondWith(error: any Error) {
        queue.sync { failOnQueue(error) }
        listener.cancel()
    }

    /// Cancels the wait; nothing is saved and the listener shuts down. Safe to
    /// call more than once and from any thread (never from `queue` itself).
    func stop() {
        queue.sync { failOnQueue(LoopbackError.cancelled) }
        listener.cancel()
    }

    // MARK: - Waiter plumbing

    /// On-queue only: resolve the waiter or park a terminal failure.
    private func failOnQueue(_ error: any Error) {
        if let continuation {
            self.continuation = nil
            continuation.resume(throwing: error)
        } else if pendingError == nil {
            pendingError = error
        }
    }

    /// Blocks briefly until the listener reports the bound port.
    private func waitUntilReady() throws {
        let deadline = Date().addingTimeInterval(5)
        while queue.sync(execute: { boundPort }) == 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard queue.sync(execute: { boundPort }) != 0 else {
            throw LoopbackError.listenerFailed("Listener never became ready.")
        }
    }

    // MARK: - Requests

    private func accept(_ connection: NWConnection) {
        // Listener-accepted connections must be started before they deliver;
        // handle() then runs on `queue` like every other state access.
        connection.start(queue: queue)
        // TCP has no message boundary — `receiveMessage` only delivers on EOF,
        // so pump the stream until the request headers are complete.
        var buffer = Data()
        func pump() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
                [weak self] data, _, isComplete, error in
                guard let self else {
                    connection.cancel()
                    return
                }
                if let data, !data.isEmpty {
                    buffer.append(data)
                }
                if error != nil || isComplete {
                    connection.cancel()
                    return
                }
                if let target = Self.requestTarget(buffer),
                   buffer.range(of: Data("\r\n\r\n".utf8)) != nil
                {
                    handle(connection: connection, target: target)
                    return
                }
                pump()
            }
        }
        pump()
    }

    /// Extracts the request target from the start line of a buffered request:
    /// the second token of `"GET /auth/callback?code=… HTTP/1.1"`.
    private static func requestTarget(_ buffer: Data) -> String? {
        guard let header = String(data: buffer, encoding: .utf8) else { return nil }
        return header
            .split(separator: "\r\n", omittingEmptySubsequences: true)
            .first
            .flatMap { $0.split(separator: " ").dropFirst().first.map(String.init) }
    }

    /// On `queue` (connection pump runs there).
    private func handle(connection: NWConnection, target: String) {
        guard target.hasPrefix(path) else {
            send(connection: connection, body: Self.emptyHTML, status: "404 Not Found")
            return
        }

        let portSuffix = boundPort == 0 ? "" : ":\(boundPort)"
        guard let components = URLComponents(string: "http://127.0.0.1\(portSuffix)\(target)")
        else {
            failOnQueue(LoopbackError.listenerFailed("Unparseable callback URL"))
            connection.cancel()
            return
        }
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: components)
        }
        send(connection: connection, body: Self.successHTML, status: "200 OK")
    }

    private func send(connection: NWConnection, body: String, status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { [weak connection] _ in
                connection?.cancel()
            }
        )
    }

    // MARK: - Browser-facing pages

    private static let successHTML = """
    <html><body style="font-family: -apple-system; text-align: center; padding-top: 48px">
    <h2>You're signed in</h2>
    <p>You can close this window and return to Eigin.</p>
    </body></html>
    """

    private static let emptyHTML = "<html><body></body></html>"
}
