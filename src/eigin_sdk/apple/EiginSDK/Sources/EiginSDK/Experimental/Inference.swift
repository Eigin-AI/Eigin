import EiginSDKBindings
import Foundation

public extension EiginSDK.Experimental {
    /// Inference values and Apple runtime adaptation.
    enum Inference {
        public typealias Configuration = InferenceProviderConfig
        public typealias EiginRelayConfiguration = EiginRelayProviderConfig
        public typealias EiginRelayWalletSource = EiginSDKBindings.EiginRelayWalletSource
        public typealias EiginRelayWalletFailure = EiginRelayWalletError
        public typealias Input = InferenceCompletionInput
        public typealias Message = InferenceMessage
        public typealias Image = InferenceImage
        public typealias ToolCall = InferenceToolCall
        public typealias ToolDefinition = InferenceToolDefinition
        public typealias ModelFamily = InferenceModelFamily
        public typealias ReasoningOrigin = InferenceReasoningOrigin
        public typealias ReasoningHistory = InferenceReasoningHistory
        public typealias Event = InferenceEvent
        public typealias Failure = InferenceError

        /// Uses the supplied URLSession for the SDK provider.
        public final class OpenAICompatible: Sendable {
            private let provider: OpenAiCompatibleProvider

            public init(configuration: Configuration, session: URLSession = .shared) {
                provider = OpenAiCompatibleProvider.withTransport(
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

        /// Releases network resources when cancelled or no longer retained by its consumer.
        public final class Stream: Sendable {
            private let read: @Sendable () async throws -> Event?
            private let cancelOperation: @Sendable () -> Void

            init(_ operation: OpenAiCompatibleStream) {
                read = { try await operation.next() }
                cancelOperation = { operation.cancel() }
            }

            init(_ operation: EiginRelayStream) {
                read = { try await operation.next() }
                cancelOperation = { operation.cancel() }
            }

            init(_ operation: OpenAiResponsesStream) {
                read = { try await operation.next() }
                cancelOperation = { operation.cancel() }
            }

            init(_ operation: AnthropicStream) {
                read = { try await operation.next() }
                cancelOperation = { operation.cancel() }
            }

            deinit { cancelOperation() }

            public func next() async throws -> Event? {
                try await withCancellation(cancel: cancelOperation, mapError: inferenceError) {
                    try await self.read()
                }
            }

            public func cancel() {
                cancelOperation()
            }
        }

        /// Model routing recovery requires both a relevant status and a model-specific body.
        public static func isModelNotFound(status: UInt16, body: String?) -> Bool {
            inferenceModelNotFound(status: status, body: body)
        }
    }
}
