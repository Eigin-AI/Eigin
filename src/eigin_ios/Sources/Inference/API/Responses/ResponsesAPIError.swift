import Foundation

/// Errors from the Responses API under the ChatGPT subscription flow,
/// carrying the SIWC `subscription_sharing_*` codes and ordinary HTTP
/// failures. Surfaced through ``ConnectionError(from:)``.
enum ResponsesAPIError: Error, LocalizedError, Equatable {
    /// The signed-in account has no ChatGPT Plus/Pro subscription.
    case planNotEligible
    /// The plan's usage limit is used up.
    case usageLimitExceeded
    /// The sign-in is no longer valid — the credential should be cleared.
    case invalidUser
    /// OpenAI's plan-usage service is temporarily down or the account is
    /// settling — retry-able.
    case usageUnavailable
    /// The request used something the subscription flow can't do.
    case unsupportedCapability(param: String?)
    case httpError(Int, body: String?)
    case invalidResponse
    /// The SSE stream ended without a completion event.
    case interruptedStream

    var errorDescription: String? {
        switch self {
        case .planNotEligible:
            Localized.Errors.Chatgpt.plusRequiredTitle
                + ": " + Localized.Errors.Chatgpt.plusRequiredSuggestion
        case .usageLimitExceeded:
            Localized.Errors.Chatgpt.usageLimitTitle
                + ": " + Localized.Errors.Chatgpt.usageLimitSuggestion
        case .invalidUser:
            Localized.Errors.Chatgpt.invalidUserTitle
                + ": " + Localized.Errors.Chatgpt.invalidUserSuggestion
        case .usageUnavailable:
            Localized.Errors.Chatgpt.unavailableTitle
                + ": " + Localized.Errors.Chatgpt.unavailableSuggestion
        case .unsupportedCapability:
            Localized.Errors.Chatgpt.unsupportedCapabilityTitle + ": "
                + Localized.Errors.Chatgpt.unsupportedCapabilitySuggestion
        case .httpError(let code, let body):
            "\(Localized.Errors.Request.failed) (HTTP \(code))\(body.map { ": \($0)" } ?? "")"
        case .invalidResponse:
            Localized.Ui.unexpectedResponse
        case .interruptedStream:
            Localized.Errors.Connection.failed
        }
    }

    /// Whether the connection phase can be retried.
    var isRetryable: Bool {
        switch self {
        case .usageUnavailable:
            true
        case .httpError(let code, _):
            code == 429 || (500 ... 599).contains(code)
        default:
            false
        }
    }
}
