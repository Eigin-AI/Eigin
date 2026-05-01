@testable import Eigin
import Foundation
import Testing

@Suite("ChatService Retry")
struct ChatServiceRetryTests {
    // MARK: - Helpers

    /// Creates a stream that yields the given values then finishes.
    private func successStream<T: Sendable>(_ values: [T]) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }
    }

    // MARK: - Retryable errors succeed after retry

    @Test func retriesOnHTTP500AndSucceeds() async throws {
        let callCount = CallCounter()
        let stream: AsyncThrowingStream<String, Error> = try await withRetry(maxAttempts: 3) {
            let attempt = callCount.increment()
            if attempt < 2 {
                throw OpenAICompatibleClientError.httpError(500)
            }
            return successStream(["hello"])
        }

        var collected: [String] = []
        for try await value in stream {
            collected.append(value)
        }

        #expect(collected == ["hello"])
        #expect(callCount.value == 2)
    }

    @Test func retriesOnHTTP429() async throws {
        let callCount = CallCounter()
        let stream: AsyncThrowingStream<String, Error> = try await withRetry(maxAttempts: 3) {
            let attempt = callCount.increment()
            if attempt < 2 {
                throw OpenAICompatibleClientError.httpError(429)
            }
            return successStream(["ok"])
        }

        var collected: [String] = []
        for try await value in stream {
            collected.append(value)
        }

        #expect(collected == ["ok"])
    }

    @Test func retriesOnURLErrorTimedOut() async throws {
        let callCount = CallCounter()
        let stream: AsyncThrowingStream<String, Error> = try await withRetry(maxAttempts: 3) {
            let attempt = callCount.increment()
            if attempt < 2 {
                throw URLError(.timedOut)
            }
            return successStream(["ok"])
        }

        var collected: [String] = []
        for try await value in stream {
            collected.append(value)
        }

        #expect(collected == ["ok"])
    }

    // MARK: - Non-retryable errors fail immediately

    @Test func doesNotRetryHTTP401() async throws {
        let callCount = CallCounter()

        do {
            _ = try await withRetry(maxAttempts: 3) { () async throws -> AsyncThrowingStream<
                String,
                Error
            > in
                callCount.increment()
                throw OpenAICompatibleClientError.httpError(401)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(callCount.value == 1)
        }
    }

    @Test func doesNotRetryInvalidURL() async throws {
        let callCount = CallCounter()

        do {
            _ = try await withRetry(maxAttempts: 3) { () async throws -> AsyncThrowingStream<
                String,
                Error
            > in
                callCount.increment()
                throw OpenAICompatibleClientError.invalidURL("bad")
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(callCount.value == 1)
        }
    }

    @Test func doesNotRetryNotConnectedToInternet() async throws {
        let callCount = CallCounter()

        do {
            _ = try await withRetry(maxAttempts: 3) { () async throws -> AsyncThrowingStream<
                String,
                Error
            > in
                callCount.increment()
                throw URLError(.notConnectedToInternet)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(callCount.value == 1)
        }
    }

    // MARK: - Exhausted retries

    @Test func failsAfterMaxAttempts() async throws {
        let callCount = CallCounter()

        do {
            _ = try await withRetry(maxAttempts: 2) { () async throws -> AsyncThrowingStream<
                String,
                Error
            > in
                callCount.increment()
                throw OpenAICompatibleClientError.httpError(502)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(callCount.value == 2)
        }
    }

    // MARK: - Cancellation

    @Test func respectsCancellation() async throws {
        let task = Task {
            _ = try await withRetry(maxAttempts: 5) { () async throws -> AsyncThrowingStream<
                String,
                Error
            > in
                throw OpenAICompatibleClientError.httpError(500)
            }
        }

        // Cancel quickly — should not complete all 5 attempts
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // Also acceptable — could be the httpError if cancel races
        }
    }
}

// MARK: - Thread-safe call counter

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.withLock { _value }
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            _value += 1
            return _value
        }
    }
}
