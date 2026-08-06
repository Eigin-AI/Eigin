import Foundation

extension RoutingFailure {
    /// Classifies a client error into the shape routing cares about.
    ///
    /// ``notTheModelsFault`` is the distinction that matters: switching models on a bad
    /// key or an empty wallet just spends more of the user's money failing the same way.
    init(from error: Error) {
        if error is FirstEventTimeout {
            self = .timedOut
            return
        }
        if let clientError = error as? OpenAICompatibleClientError {
            self = Self.from(clientError)
            return
        }
        if let relayError = error as? RelayClientError {
            self = Self.from(relayError)
            return
        }
        // Buy credits, download the model, use a supported device.
        if error is CreditsError || error is LocalClientError {
            self = .notTheModelsFault
            return
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotFindHost, .networkConnectionLost,
                 .dataNotAllowed, .internationalRoamingOff:
                self = .offline
            case .timedOut:
                self = .timedOut
            case .cannotConnectToHost, .badServerResponse:
                self = .providerOverloaded
            default:
                self = .notTheModelsFault
            }
            return
        }
        self = .notTheModelsFault
    }

    private static func from(_ error: OpenAICompatibleClientError) -> RoutingFailure {
        if error.isModelNotFound { return .modelNotFound }
        guard case .httpError(let code, _) = error else {
            // Invalid URL or unparseable response: configuration, not the model.
            return .notTheModelsFault
        }
        if code == 429 || (500 ... 599).contains(code) { return .providerOverloaded }
        return .notTheModelsFault
    }

    private static func from(_ error: RelayClientError) -> RoutingFailure {
        switch error {
        case .rateLimit, .serviceUnavailable, .upstream:
            .providerOverloaded
        case .server(let code, _):
            (500 ... 599).contains(code) ? .providerOverloaded : .notTheModelsFault
        case .network:
            .offline
        case .authentication, .invalidRequest, .insufficientCredits, .proofVerificationFailed,
             .decoding, .notConfigured:
            .notTheModelsFault
        }
    }

    /// Whether this failure should count against the model's health.
    var blamesModel: Bool {
        switch self {
        case .modelNotFound, .providerOverloaded, .timedOut: true
        case .offline, .notTheModelsFault: false
        }
    }
}
