import Foundation

/// A user-friendly representation of an error encountered while connecting to a provider.
struct ConnectionError: Equatable {
    /// An in-place way for the user to resolve the error, surfaced as a primary action on the
    /// error card.
    enum Recovery: Equatable {
        /// The Eigin relay has no spendable credits; offer to buy more.
        case purchaseEiginRelayCredits
    }

    let title: String
    let suggestion: String
    let rawDescription: String?
    /// Set when the error has a direct in-app remedy (e.g. buying credits). `nil` otherwise.
    var recovery: Recovery?

    init(
        title: String,
        suggestion: String,
        rawDescription: String? = nil,
        recovery: Recovery? = nil
    ) {
        self.title = title
        self.suggestion = suggestion
        self.rawDescription = rawDescription
        self.recovery = recovery
    }

    init(from error: Error) {
        // The hedged race's first-token ceiling expired: silence from every
        // side, no error body to quote. Reuse the network-timeout card.
        if error is FirstEventTimeout {
            title = Localized.Ui.connectionTimedOut
            suggestion = Localized.Errors.Provider.timeout
            rawDescription = nil
            recovery = nil
            return
        }
        if let creditsError = error as? CreditsError, case .noCreditsRemaining = creditsError {
            title = Localized.Provider.Eigin.outOfCreditsTitle
            suggestion = Localized.Provider.Eigin.outOfCreditsBody
            rawDescription = error.localizedDescription
            recovery = .purchaseEiginRelayCredits
            return
        }
        if let signInError = error as? ChatGPTSubscriptionError {
            switch signInError {
            case .subscriptionRequired:
                // Grant refusal at the token endpoint — we can't tell from
                // OpenAI's bare invalid_grant whether it is eligibility or
                // something else, so the card stays generic.
                title = Localized.Errors.Chatgpt.signinFailedTitle
                suggestion = Localized.Errors.Chatgpt.signinFailedSuggestion
                rawDescription = nil
            case .planUsageNotGranted:
                title = Localized.Errors.Connection.title
                suggestion = Localized.Errors.Chatgpt.planUsageNotGranted
                rawDescription = nil
            default:
                title = Localized.Errors.Connection.title
                suggestion = signInError.errorDescription ?? error.localizedDescription
                rawDescription = nil
            }
            return
        }
        if let responsesError = error as? ResponsesAPIError {
            switch responsesError {
            case .planNotEligible:
                title = Localized.Errors.Chatgpt.plusRequiredTitle
                suggestion = Localized.Errors.Chatgpt.plusRequiredSuggestion
                rawDescription = error.localizedDescription
            case .usageLimitExceeded:
                title = Localized.Errors.Chatgpt.usageLimitTitle
                suggestion = Localized.Errors.Chatgpt.usageLimitSuggestion
                rawDescription = error.localizedDescription
            case .invalidUser:
                title = Localized.Errors.Chatgpt.invalidUserTitle
                suggestion = Localized.Errors.Chatgpt.invalidUserSuggestion
                rawDescription = error.localizedDescription
            case .usageUnavailable:
                title = Localized.Errors.Chatgpt.unavailableTitle
                suggestion = Localized.Errors.Chatgpt.unavailableSuggestion
                rawDescription = error.localizedDescription
            case .unsupportedCapability(let param):
                title = Localized.Errors.Chatgpt.unsupportedCapabilityTitle
                suggestion = Localized.Errors.Chatgpt.unsupportedCapabilitySuggestion
                rawDescription = nil
            case .httpError, .interruptedStream, .invalidResponse:
                title = Localized.Errors.Connection.failed
                suggestion = error.localizedDescription
                rawDescription = nil
            }
            return
        }
        if let localError = error as? LocalClientError {
            switch localError {
            case .deviceUnsupported(let detail):
                title = Localized.Model.deviceUnsupportedTitle
                suggestion = Localized.Model.deviceUnsupportedSuggestion
                rawDescription = detail
            case .modelNotDownloaded:
                title = Localized.Model.NotDownloaded.title
                suggestion = Localized.Model.NotDownloaded.suggestion
                rawDescription = error.localizedDescription
            case .modelNotLoaded:
                title = Localized.Model.NotLoaded.title
                suggestion = Localized.Model.NotLoaded.suggestion
                rawDescription = error.localizedDescription
            }
            return
        }
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

            case .httpError(let code, let body):
                switch code {
                case 400:
                    let creditPattern =
                        /(?i)credit[s]?\s+balance|insufficient[_\s]+(?:credit[s]?|quota)|out\s+of\s+credit[s]?/
                    if let body, body.contains(creditPattern) {
                        title = Localized.Errors.Billing.checkRequired
                        suggestion = Localized.Errors.Provider.billingCheckRequired
                    } else {
                        title = "\(Localized.Errors.Request.failed)"
                        suggestion = Localized.Errors.Provider.returnedError
                    }
                case 401:
                    title = Localized.Errors.Authentication.failed
                    suggestion = Localized.Errors.Provider.invalidApiKey
                case 402:
                    title = Localized.Errors.Billing.required
                    suggestion = Localized.Errors.Provider.billingRequired
                case 403:
                    title = Localized.Errors.Access.denied
                    suggestion = Localized.Errors.Provider.permissionDenied
                case 404:
                    title = Localized.Ui.endpointNotFound
                    suggestion = Localized.Errors.Provider.modelsEndpointNotFound
                case 413:
                    title = Localized.Errors.Request.tooLarge
                    suggestion = Localized.Errors.Provider.requestTooLarge
                case 422:
                    title = Localized.Errors.Request.invalid
                    suggestion = Localized.Errors.Provider.invalidRequest
                case 423:
                    title = Localized.Errors.Account.locked
                    suggestion = Localized.Errors.Provider.accountLocked
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
