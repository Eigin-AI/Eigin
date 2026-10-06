import Foundation

/// Errors surfaced by the sign-in flow, each with user-facing copy.
enum ChatGPTSubscriptionError: Error, LocalizedError, Equatable {
    case userCancelled
    /// The user actively denied the request in the consent screen.
    case declined
    /// Sign-in succeeded but ChatGPT plan usage wasn't approved — identity only.
    case planUsageNotGranted
    /// The token endpoint refused to mint the plan grant: the account has no
    /// eligible ChatGPT subscription (bare `invalid_grant`, no description).
    case subscriptionRequired
    case stateMismatch
    case clientIDMismatch
    case registrationIncomplete
    case tokenExchangeFailed(String)
    case idTokenValidation(String)
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            Localized.Errors.Authentication.cancelled
        case .declined:
            Localized.Errors.Authorization.failedWithReason("Access denied")
        case .planUsageNotGranted:
            Localized.Errors.Chatgpt.planUsageNotGranted
        case .subscriptionRequired:
            Localized.Errors.Chatgpt.plusRequiredSuggestion
        case .stateMismatch, .clientIDMismatch, .registrationIncomplete:
            Localized.Errors.Authorization
                .failedWithReason("The sign-in returned an unexpected result.")
        case .tokenExchangeFailed(let detail):
            Localized.Errors.Authorization.failedWithReason(detail)
        case .idTokenValidation:
            Localized.Errors.Authorization.failedWithReason("The sign-in could not be verified.")
        case .timedOut:
            Localized.Errors.Authorization.failedWithReason("Sign-in timed out.")
        case .failed(let detail):
            Localized.Errors.Authorization.failedWithReason(detail)
        }
    }
}
