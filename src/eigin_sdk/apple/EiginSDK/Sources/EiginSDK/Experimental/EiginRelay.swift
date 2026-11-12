import EiginSDKBindings
import Foundation

public extension EiginSDK.Experimental.Inference {
    /// EiginRelay inference backed by host wallets and the supplied URLSession.
    final class EiginRelay: Sendable {
        private let provider: EiginRelayProvider

        public init(
            configuration: EiginRelayConfiguration,
            walletSource: any EiginRelayWalletSource,
            session: URLSession = .shared
        ) throws {
            provider = try EiginRelayProvider.withTransport(
                config: configuration,
                walletSource: walletSource,
                transport: URLSessionHTTPTransport(session: session)
            )
        }

        public func fetchModels() async throws -> [String] {
            let operation = provider.discovery()
            defer { operation.cancel() }
            return try await withCancellation(cancel: { operation.cancel() }, mapError: inferenceError) {
                try await operation.fetchModels()
            }
        }

        /// Opens with wallet failover before returning the stream to its consumer.
        public func stream(_ input: Input) async throws -> Stream {
            let operation = try provider.stream(input: input)
            try await withCancellation(cancel: { operation.cancel() }, mapError: inferenceError) {
                try await operation.open()
            }
            return Stream(operation)
        }
    }
}
