import Foundation

/// How a saved provider record routes to its implementation, recognized from
/// its base URL.
///
/// Provider records persist only a base URL string, so capabilities that
/// aren't visible in the URL — a refreshable credential, a different wire
/// format — are encoded as sentinel prefixes. A preset can carry two real
/// ways in (e.g. Infercom by sign-in or by manual key), and the sentinel is
/// what tells their saved records apart.
extension ProviderPreset {
    /// The address every Eigin relay provider is saved with.
    static let relayBaseURL = "eigin-relay://"

    /// The address every Infercom sign-in provider is saved with. Distinguishes
    /// signed-in (refreshable OAuth credential) from manual-key Infercom,
    /// whose provider records carry the real base URL.
    static let infercomSignInBaseURL = "infercom-signin://"

    /// Whether this provider runs on-device (no API key, no network).
    static func isLocal(_ baseURL: String) -> Bool {
        baseURL.hasPrefix("local://")
    }

    /// Whether this provider routes inference through the Eigin relay
    /// (authorized by credits, not a keychain API key).
    static func isRelay(_ baseURL: String) -> Bool {
        baseURL.hasPrefix(relayBaseURL)
    }

    /// Whether this provider connects via ChatGPT subscription sign-in (SIWC).
    /// Inference goes to the Responses API on `api.openai.com`, authorized by
    /// a refreshable OAuth token rather than a keychain key.
    static func isChatGPTSubscription(_ baseURL: String) -> Bool {
        baseURL.hasPrefix("openai-chatgpt://")
    }

    /// Whether this provider connects via Infercom sign-in: PKCE login plus
    /// RFC 8693 token exchange, inference at `api.infercom.ai` with a
    /// refreshable Bearer token rather than a keychain key.
    static func isInfercomSignIn(_ baseURL: String) -> Bool {
        baseURL.hasPrefix(infercomSignInBaseURL)
    }

    /// Whether this provider runs on Anthropic's API (different wire format).
    static func isAnthropic(_ baseURL: String) -> Bool {
        baseURL.contains("api.anthropic.com")
    }

    /// The sign-in family a saved record belongs to, or `nil` when the record
    /// holds a plain API key or no credential at all. Sign-in records carry a
    /// sentinel base URL; everything else routes by its real URL.
    static func signInKind(_ baseURL: String) -> SignInKind? {
        if isChatGPTSubscription(baseURL) { return .chatGPTSubscription }
        if isInfercomSignIn(baseURL) { return .infercomSignIn }
        return nil
    }

    /// The two sign-in families today. Exist so views and services switch on
    /// one value instead of accumulating per-provider booleans.
    enum SignInKind {
        case chatGPTSubscription
        case infercomSignIn
    }
}

extension ProviderPreset.AuthMethod {
    /// Whether connecting goes through an interactive sign-in flow — the
    /// picker routes these presets into the sign-in group and the connect
    /// sheet starts with the sign-in button.
    var isSignIn: Bool {
        self == .oAuthPKCE || self == .chatGPTSubscription || self == .infercomSignIn
    }
}
