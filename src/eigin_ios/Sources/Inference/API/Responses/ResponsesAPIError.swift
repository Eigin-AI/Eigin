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

    /// Maps an HTTP failure to the most specific SIWC error. Subscription
    /// error codes appear in `error.code` or in a `detail` body and outrank
    /// the status code.
    static func make(statusCode: Int, body: String?) -> ResponsesAPIError {
        if let code = subscriptionCode(in: body) {
            switch code {
            case "subscription_sharing_user_not_eligible":
                return .planNotEligible
            case "subscription_sharing_usage_limit_exceeded":
                return .usageLimitExceeded
            case "subscription_sharing_invalid_user":
                return .invalidUser
            case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
                return .usageUnavailable
            case "subscription_sharing_unsupported_capability":
                return .unsupportedCapability(param: param(in: body))
            default:
                return .httpError(statusCode, body: body)
            }
        }
        return .httpError(statusCode, body: body)
    }

    static func subscriptionCode(in body: String?) -> String? {
        guard let body else { return nil }
        let codes = [
            "subscription_sharing_user_not_eligible",
            "subscription_sharing_usage_limit_exceeded",
            "subscription_sharing_invalid_user",
            "subscription_sharing_usage_unavailable",
            "subscription_sharing_user_unavailable",
            "subscription_sharing_unsupported_capability",
        ]
        return codes.first { body.contains($0) }
    }

    /// Best-effort `param` extraction from an API error body.
    static func param(in body: String?) -> String? {
        guard let body,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["param"] as? String
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
