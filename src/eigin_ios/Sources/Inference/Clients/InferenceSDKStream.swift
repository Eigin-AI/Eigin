import EiginSDK

/// Adapts SDK pull streams to the app's text and structured event streams.
enum InferenceSDKStream {
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
