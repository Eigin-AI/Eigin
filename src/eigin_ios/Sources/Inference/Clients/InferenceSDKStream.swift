import EiginSDK

/// Adapts SDK pull streams to the app's text and structured event streams.
enum InferenceSDKStream {
    static func session(
        _ stream: EiginSDK.Experimental.Inference.Stream,
        mapError: @escaping @Sendable (any Error) -> any Error
    ) -> EiginSDK.Experimental.Inference.RequestSession {
        .init(next: {
            do { return try await stream.next() }
            catch { throw mapError(error) }
        }, cancel: { stream.cancel() })
    }

    static func events(
        _ session: EiginSDK.Experimental.Inference.RequestSession
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream(unfolding: {
            try await session.next().map(InferenceSDKConversion.event)
        })
    }

    static func text(
        _ completion: EiginSDK.Experimental.Inference.Stream,
        mapError: @escaping @Sendable (any Error) -> any Error = InferenceSDKConversion.error
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream(unfolding: {
            do {
                while let event = try await completion.next() {
                    if case .contentDelta(let text) = event { return text }
                }
                return nil
            } catch { throw mapError(error) }
        })
    }

    static func events(
        _ completion: EiginSDK.Experimental.Inference.Stream,
        mapError: @escaping @Sendable (any Error) -> any Error = InferenceSDKConversion.error
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream(unfolding: {
            do { return try await completion.next().map(InferenceSDKConversion.event) }
            catch { throw mapError(error) }
        })
    }
}
