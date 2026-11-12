import EiginSDKBindings
import Foundation

public extension EiginSDK.Experimental.Inference {
    /// Uses the supplied URLSession for the SDK provider.
    final class OpenAIResponses: Sendable {
        private let provider: OpenAiResponsesProvider

        public init(configuration: Configuration, session: URLSession = .shared) {
            provider = OpenAiResponsesProvider.withTransport(
                config: configuration, transport: URLSessionHTTPTransport(session: session)
            )
        }

        public func fetchModels() async throws -> [String] {
            let operation = provider.discovery()
            defer { operation.cancel() }
            return try await withCancellation(cancel: { operation.cancel() }, mapError: inferenceError) {
                try await operation.fetchModels()
            }
        }

        public func validateAPIKey(model: String) async throws {
            let operation = provider.keyValidation()
            defer { operation.cancel() }
            try await withCancellation(cancel: { operation.cancel() }, mapError: inferenceError) {
                try await operation.validateApiKey(model: model)
            }
        }

        /// Validates HTTP status before returning a pull-based stream handle.
        public func stream(_ input: Input) async throws -> Stream {
            let operation = try provider.stream(input: input)
            try await withCancellation(cancel: { operation.cancel() }, mapError: inferenceError) {
                try await operation.open()
            }
            return Stream(operation)
        }
    }
}
