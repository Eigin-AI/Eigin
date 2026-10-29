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

    /// Maps a thrown error to the card it shows as. The first mapper that
    /// recognizes the error wins; the NSError fallback catches the rest.
    /// One mapper per error family — adding a provider means adding a
    /// mapper, not another branch here.
    init(from error: Error) {
        let mappers: [@Sendable (Error) -> ConnectionError?] = [
            Self.firstEventTimeoutCard,
            Self.creditsCard,
            Self.consentCard,
            Self.chatGPTSubscriptionCard,
            Self.infercomSignInCard,
            Self.responsesAPICard,
            Self.localClientCard,
            Self.openAICompatibleClientCard,
        ]
        self = mappers.lazy.compactMap { $0(error) }.first ?? Self.nsErrorCard(for: error)
    }

    // MARK: - Mappers

    /// The hedged race's first-token ceiling expired: silence from every
    /// side, no error body to quote. Reuse the network-timeout card.
    private static func firstEventTimeoutCard(for error: Error) -> ConnectionError? {
        guard error is FirstEventTimeout else { return nil }
        return ConnectionError(
            title: Localized.Ui.connectionTimedOut,
            suggestion: Localized.Errors.Provider.timeout
        )
    }

    private static func creditsCard(for error: Error) -> ConnectionError? {
        guard let creditsError = error as? CreditsError,
              case .noCreditsRemaining = creditsError
        else { return nil }
        return ConnectionError(
            title: Localized.Provider.Eigin.outOfCreditsTitle,
            suggestion: Localized.Provider.Eigin.outOfCreditsBody,
            rawDescription: error.localizedDescription,
            recovery: .purchaseEiginRelayCredits
        )
    }

    private static func consentCard(for error: Error) -> ConnectionError? {
        guard error is AIConsentError else { return nil }
        return ConnectionError(
            title: Localized.Provider.Consent.notAllowedTitle,
            suggestion: Localized.Provider.Consent.notAllowedBody,
            rawDescription: error.localizedDescription
        )
    }

    private static func chatGPTSubscriptionCard(for error: Error) -> ConnectionError? {
        guard let signInError = error as? ChatGPTSubscriptionError else { return nil }
        switch signInError {
        case .subscriptionRequired:
            // Grant refusal at the token endpoint — we can't tell from
            // OpenAI's bare invalid_grant whether it is eligibility or
            // something else, so the card stays generic.
            return ConnectionError(
                title: Localized.Errors.Chatgpt.signinFailedTitle,
                suggestion: Localized.Errors.Chatgpt.signinFailedSuggestion
            )
        case .planUsageNotGranted:
            return ConnectionError(
                title: Localized.Errors.Connection.title,
                suggestion: Localized.Errors.Chatgpt.planUsageNotGranted
            )
        default:
            return ConnectionError(
                title: Localized.Errors.Connection.title,
                suggestion: signInError.errorDescription ?? error.localizedDescription
            )
        }
    }

    private static func infercomSignInCard(for error: Error) -> ConnectionError? {
        guard let signInError = error as? InfercomSignInError else { return nil }
        switch signInError {
        case .unverifiedEmail:
            return ConnectionError(
                title: Localized.Errors.Infercom.unverifiedEmailTitle,
                suggestion: Localized.Errors.Infercom.unverifiedEmailSuggestion
            )
        case .httpError(402, _):
            // No payment method on the Infercom account — the same
            // generic payment card every provider's 402 gets.
            return ConnectionError(
                title: Localized.Errors.Billing.required,
                suggestion: Localized.Errors.Provider.billingRequired
            )
        default:
            return ConnectionError(
                title: Localized.Errors.Connection.title,
                suggestion: Localized.Errors.Infercom.signinFailedSuggestion
            )
        }
    }

    private static func responsesAPICard(for error: Error) -> ConnectionError? {
        guard let responsesError = error as? ResponsesAPIError else { return nil }
        switch responsesError {
        case .planNotEligible:
            return ConnectionError(
                title: Localized.Errors.Chatgpt.plusRequiredTitle,
                suggestion: Localized.Errors.Chatgpt.plusRequiredSuggestion,
                rawDescription: error.localizedDescription
            )
        case .usageLimitExceeded:
            return ConnectionError(
                title: Localized.Errors.Chatgpt.usageLimitTitle,
                suggestion: Localized.Errors.Chatgpt.usageLimitSuggestion,
                rawDescription: error.localizedDescription
            )
        case .invalidUser:
            return ConnectionError(
                title: Localized.Errors.Chatgpt.invalidUserTitle,
                suggestion: Localized.Errors.Chatgpt.invalidUserSuggestion,
                rawDescription: error.localizedDescription
            )
        case .usageUnavailable:
            return ConnectionError(
                title: Localized.Errors.Chatgpt.unavailableTitle,
                suggestion: Localized.Errors.Chatgpt.unavailableSuggestion,
                rawDescription: error.localizedDescription
            )
        case .unsupportedCapability:
            return ConnectionError(
                title: Localized.Errors.Chatgpt.unsupportedCapabilityTitle,
                suggestion: Localized.Errors.Chatgpt.unsupportedCapabilitySuggestion
            )
        case .httpError, .interruptedStream, .invalidResponse:
            return ConnectionError(
                title: Localized.Errors.Connection.failed,
                suggestion: error.localizedDescription
            )
        }
    }

    private static func localClientCard(for error: Error) -> ConnectionError? {
        guard let localError = error as? LocalClientError else { return nil }
        switch localError {
        case .deviceUnsupported(let detail):
            return ConnectionError(
                title: Localized.Model.deviceUnsupportedTitle,
                suggestion: Localized.Model.deviceUnsupportedSuggestion,
                rawDescription: detail
            )
        case .modelNotDownloaded:
            return ConnectionError(
                title: Localized.Model.NotDownloaded.title,
                suggestion: Localized.Model.NotDownloaded.suggestion,
                rawDescription: error.localizedDescription
            )
        case .modelNotLoaded:
            return ConnectionError(
                title: Localized.Model.NotLoaded.title,
                suggestion: Localized.Model.NotLoaded.suggestion,
                rawDescription: error.localizedDescription
            )
        }
    }

    private static func openAICompatibleClientCard(for error: Error) -> ConnectionError? {
        guard let clientError = error as? OpenAICompatibleClientError else { return nil }
        let rawDescription: String? = if case .httpError(_, let body) = clientError, let body {
            body
        } else {
            error.localizedDescription
        }
        let (title, suggestion): (String, String) = switch clientError {
        case .invalidURL:
            (Localized.Ui.invalidUrl, Localized.Errors.Provider.baseUrlHint)
        case .invalidResponse:
            (Localized.Ui.unexpectedResponse, Localized.Errors.Provider.unexpectedResponse)
        case .httpError(let code, let body):
            httpStatusCard(code: code, body: body)
        }
        return ConnectionError(
            title: title,
            suggestion: suggestion,
            rawDescription: rawDescription
        )
    }

    /// The last resort: reached only for errors no family mapper recognized.
    private static func nsErrorCard(for error: Error) -> ConnectionError {
        let rawDescription = error.localizedDescription
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorUnsupportedURL:
            return ConnectionError(
                title: Localized.Ui.invalidUrl,
                suggestion: Localized.Errors.Provider.malformedUrl,
                rawDescription: rawDescription
            )
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return ConnectionError(
                title: Localized.Errors.Network.noConnection,
                suggestion: Localized.Errors.Network.retryHint,
                rawDescription: rawDescription
            )
        case NSURLErrorCannotFindHost:
            return ConnectionError(
                title: Localized.Ui.serverNotFound,
                suggestion: Localized.Errors.Provider.hostNotFound,
                rawDescription: rawDescription
            )
        case NSURLErrorCannotConnectToHost:
            return ConnectionError(
                title: Localized.Errors.Connection.refused,
                suggestion: Localized.Errors.Provider.connectionRefused,
                rawDescription: rawDescription
            )
        case NSURLErrorTimedOut:
            return ConnectionError(
                title: Localized.Ui.connectionTimedOut,
                suggestion: Localized.Errors.Provider.timeout,
                rawDescription: rawDescription
            )
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return ConnectionError(
                title: Localized.Errors.Secure.Connection.failed,
                suggestion: Localized.Errors.Provider.sslFailed,
                rawDescription: rawDescription
            )
        default:
            return ConnectionError(
                title: Localized.Errors.Connection.failed,
                suggestion: rawDescription,
                rawDescription: rawDescription
            )
        }
    }

    private static func httpStatusCard(
        code: Int,
        body: String?
    ) -> (title: String, suggestion: String) {
        switch code {
        case 400:
            let creditPattern =
                /(?i)credit[s]?\s+balance|insufficient[_\s]+(?:credit[s]?|quota)|out\s+of\s+credit[s]?/
            if let body, body.contains(creditPattern) {
                return (
                    Localized.Errors.Billing.checkRequired,
                    Localized.Errors.Provider.billingCheckRequired
                )
            }
            return (Localized.Errors.Request.failed, Localized.Errors.Provider.returnedError)
        case 401:
            return (Localized.Errors.Authentication.failed, Localized.Errors.Provider.invalidApiKey)
        case 402:
            return (Localized.Errors.Billing.required, Localized.Errors.Provider.billingRequired)
        case 403:
            return (Localized.Errors.Access.denied, Localized.Errors.Provider.permissionDenied)
        case 404:
            return (Localized.Ui.endpointNotFound, Localized.Errors.Provider.modelsEndpointNotFound)
        case 413:
            return (Localized.Errors.Request.tooLarge, Localized.Errors.Provider.requestTooLarge)
        case 422:
            return (Localized.Errors.Request.invalid, Localized.Errors.Provider.invalidRequest)
        case 423:
            return (Localized.Errors.Account.locked, Localized.Errors.Provider.accountLocked)
        case 429:
            return (Localized.Ui.rateLimited, Localized.Errors.Provider.rateLimited)
        case 500 ... 599:
            return (Localized.Errors.Server.error, Localized.Errors.Provider.serverError)
        case 0:
            return (Localized.Errors.Request.failed, Localized.Errors.Provider.returnedError)
        default:
            return (
                "\(Localized.Errors.Request.failed) (HTTP \(code))",
                Localized.Errors.Provider.returnedError
            )
        }
    }
}
