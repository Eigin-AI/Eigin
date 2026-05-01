import Foundation

/// A user-friendly representation of an error encountered while connecting to a provider.
struct ConnectionError: Equatable {
    let title: String
    let suggestion: String
    let rawDescription: String?

    init(title: String, suggestion: String, rawDescription: String? = nil) {
        self.title = title
        self.suggestion = suggestion
        self.rawDescription = rawDescription
    }

    init(from error: Error) {
        if let clientError = error as? OpenAICompatibleClientError,
           case .httpError(_, let body) = clientError, let body
        {
            rawDescription = body
        } else {
            rawDescription = error.localizedDescription
        }
        if let clientError = error as? OpenAICompatibleClientError {
            switch clientError {
            case .invalidURL:
                title = Localized.Ui.invalidUrl
                suggestion = Localized.Errors.Provider.baseUrlHint

            case .invalidResponse:
                title = Localized.Ui.unexpectedResponse
                suggestion = Localized.Errors.Provider.unexpectedResponse

            case .httpError(let code, _):
                switch code {
                case 401:
                    title = Localized.Errors.Authentication.failed
                    suggestion = Localized.Errors.Provider.invalidApiKey
                case 403:
                    title = Localized.Errors.Access.denied
                    suggestion = Localized.Errors.Provider.permissionDenied
                case 404:
                    title = Localized.Ui.endpointNotFound
                    suggestion = Localized.Errors.Provider.modelsEndpointNotFound
                case 429:
                    title = Localized.Ui.rateLimited
                    suggestion = Localized.Errors.Provider.rateLimited
                case 500 ... 599:
                    title = Localized.Errors.Server.error
                    suggestion = Localized.Errors.Provider.serverError
                case 0:
                    title = Localized.Errors.Request.failed
                    suggestion = Localized.Errors.Provider.returnedError
                default:
                    title = "\(Localized.Errors.Request.failed) (HTTP \(code))"
                    suggestion = Localized.Errors.Provider.returnedError
                }
            }
        } else {
            let nsError = error as NSError
            switch nsError.code {
            case NSURLErrorUnsupportedURL:
                title = Localized.Ui.invalidUrl
                suggestion = Localized.Errors.Provider.malformedUrl
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                title = Localized.Errors.Network.noConnection
                suggestion = Localized.Errors.Network.retryHint
            case NSURLErrorCannotFindHost:
                title = Localized.Ui.serverNotFound
                suggestion = Localized.Errors.Provider.hostNotFound
            case NSURLErrorCannotConnectToHost:
                title = Localized.Errors.Connection.refused
                suggestion = Localized.Errors.Provider.connectionRefused
            case NSURLErrorTimedOut:
                title = Localized.Ui.connectionTimedOut
                suggestion = Localized.Errors.Provider.timeout
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                title = Localized.Errors.Secure.Connection.failed
                suggestion = Localized.Errors.Provider.sslFailed
            default:
                title = Localized.Errors.Connection.failed
                suggestion = error.localizedDescription
            }
        }
    }
}
