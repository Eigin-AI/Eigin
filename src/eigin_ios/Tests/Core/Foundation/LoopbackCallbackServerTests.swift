@testable import Eigin
import Foundation
import Testing

/// Integration tests for the loopback callback server: real listener, real
/// HTTP connection over 127.0.0.1. These guard the Network.framework wiring
/// (connection start, queue confinement) that unit stubs can't reach.
@Suite("LoopbackCallbackServer", .serialized)
struct LoopbackCallbackServerTests {
    @available(iOS 16.0, *)
    private func callbackURL(port: UInt16, query: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)/auth/callback?\(query)")!
    }

    @Test func deliversCallbackAndAnswersBrowser() async throws {
        let server = try LoopbackCallbackServer(path: "/auth/callback")
        let redirectURI = try server.redirectURI()
        #expect(redirectURI.hasPrefix("http://127.0.0.1:"))
        #expect(redirectURI.hasSuffix("/auth/callback"))
        let portString = redirectURI
            .dropFirst("http://127.0.0.1:".count)
            .dropLast("/auth/callback".count)
        let port = try #require(UInt16(portString))

        let waitTask = Task {
            try await server.waitForCallback()
        }

        // Small delay so the waiter is registered before the request arrives.
        try await Task.sleep(for: .milliseconds(100))

        let (data, response) = try await URLSession.shared.data(
            from: callbackURL(port: #require(port), query: "code=abc&state=xyz")
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("signed in"))

        let components = try await waitTask.value
        #expect(components.queryItems?.first(named: "code") == "abc")
        #expect(components.queryItems?.first(named: "state") == "xyz")
    }

    @Test func ignoresRequestsMissingThePath() async throws {
        let server = try LoopbackCallbackServer(path: "/auth/callback")
        let redirectURI = try server.redirectURI()
        let portString = redirectURI
            .dropFirst("http://127.0.0.1:".count)
            .dropLast("/auth/callback".count)
        let port = try #require(UInt16(portString))

        let waitTask = Task {
            try await server.waitForCallback()
        }
        try await Task.sleep(for: .milliseconds(100))

        // A favicon-style miss must be answered 404 without resolving the wait.
        let (_, response) = try await URLSession.shared.data(
            from: #require(URL(string: "http://127.0.0.1:\(port)/favicon.ico"))
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 404)

        // The real callback now resolves the still-pending wait.
        let (data, _) = try await URLSession.shared.data(
            from: callbackURL(port: port, query: "code=late")
        )
        #expect(String(decoding: data, as: UTF8.self).contains("signed in"))
        let components = try await waitTask.value
        #expect(components.queryItems?.first(named: "code") == "late")
    }

    @Test func stopResolvesTheWaitAsCancelled() async throws {
        let server = try LoopbackCallbackServer(path: "/auth/callback")
        _ = try server.redirectURI()

        let waitTask = Task {
            try await server.waitForCallback()
        }
        try await Task.sleep(for: .milliseconds(100))
        server.stop()

        do {
            _ = try await waitTask.value
            Issue.record("Expected cancelled")
        } catch let error as LoopbackCallbackServer.LoopbackError {
            #expect(error == .cancelled)
        }

        // stop() twice must stay safe (fail path is once-only).
        server.stop()
    }
}

private extension [URLQueryItem] {
    func first(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}
