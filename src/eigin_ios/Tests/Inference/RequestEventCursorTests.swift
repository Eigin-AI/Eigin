@testable import Eigin
import EiginSDK
import Foundation
import os
import Testing

@Suite("Request host boundary")
struct RequestEventCursorTests {
    @Test func cancellationReleasesAnIdleNativeStream() async throws {
        let closed = OSAllocatedUnfairLock(initialState: false)
        let provider = EiginSDK.Experimental.Inference.Local { _, _ in
            .init(next: { nil }, cancel: { closed.withLock { $0 = true } })
        }
        func cursor() async throws -> RequestEventCursor {
            let native = try await provider.stream(.init(
                model: "local", messages: [], tools: nil, reasoningEffort: nil,
                promptCacheKey: nil, modelFamily: nil, isRelay: false, reasoningOrigin: nil,
                textOnly: false
            ))
            return RequestEventCursor(
                InferenceSDKStream.events(native)
            )
        }
        let stream = try await cursor()
        #expect(!closed.withLock { $0 })
        stream.cancel()
        let deadline = ContinuousClock.now + .seconds(2)
        while !closed.withLock({ $0 }), ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(closed.withLock { $0 })
    }

    @Test func hostFailureRestoresOriginalTypeAndIdentity() {
        let errors = RequestHostErrors()
        let original = NSError(
            domain: "host",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Original message"]
        )
        let carried = errors.encode(original)
        #expect((errors.restore(carried) as NSError) === original)
        guard case .Host(_, let message, let failure) = carried else {
            Issue.record("Expected host error identity")
            return
        }
        #expect(message == "Original message")
        #expect(failure == .notTheModelsFault)
    }

    @Test func responsesAndCompatibleFailuresKeepDifferentRoutingClassifications() {
        let errors = RequestHostErrors()
        let compatible = errors.encode(OpenAICompatibleClientError.httpError(503, body: "upstream"))
        let responses = errors.encode(ResponsesAPIError.httpError(503, body: "upstream"))
        guard case .Host(_, _, let compatibleFailure) = compatible,
              case .Host(_, _, let responsesFailure) = responses
        else {
            Issue.record("Expected host failures")
            return
        }
        #expect(compatibleFailure == .providerOverloaded)
        #expect(responsesFailure == .notTheModelsFault)
        #expect(errors.restore(compatible) is OpenAICompatibleClientError)
        #expect(errors.restore(responses) is ResponsesAPIError)
    }
}
